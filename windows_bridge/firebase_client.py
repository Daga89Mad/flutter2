"""Firebase REST con la cuenta normal de la app; sin Admin SDK ni claves de servicio."""
from __future__ import annotations
import json
import math
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from engine import Fixture, FINAL, UNAVAILABLE, instant, iso, score


class ApiError(RuntimeError):
    def __init__(self, status, message):
        super().__init__(f'HTTP {status}: {message}')
        self.status = status


def request_json(url, *, data=None, headers=None, method=None, form=False):
    headers = dict(headers or {})
    if data is not None:
        body = urllib.parse.urlencode(data).encode() if form else json.dumps(data, allow_nan=False).encode()
        headers['Content-Type'] = 'application/x-www-form-urlencoded' if form else 'application/json'
    else:
        body = None
    req = urllib.request.Request(url, body, headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        try:
            message = json.loads(error.read()).get('error', {})
            message = message.get('message', 'Solicitud rechazada') if isinstance(message, dict) else str(message)
        except (ValueError, AttributeError):
            message = 'Solicitud rechazada'
        # No mostrar URL, tokens, contraseña, cuerpo enviado ni cabeceras.
        raise ApiError(error.code, message[:240]) from None


def encode(value):
    if value is None: return {'nullValue': None}
    if isinstance(value, bool): return {'booleanValue': value}
    if isinstance(value, int): return {'integerValue': str(value)}
    if isinstance(value, float):
        if not math.isfinite(value): raise ValueError('Número no finito.')
        return {'doubleValue': value}
    if isinstance(value, datetime): return {'timestampValue': iso(value)}
    if isinstance(value, str): return {'stringValue': value}
    if isinstance(value, list): return {'arrayValue': {'values': [encode(x) for x in value]}}
    if isinstance(value, dict): return {'mapValue': {'fields': {k: encode(v) for k, v in value.items()}}}
    raise ValueError('Tipo no compatible con Firestore.')


def decode(value):
    if 'nullValue' in value: return None
    for key in ['booleanValue', 'stringValue', 'timestampValue', 'doubleValue']:
        if key in value: return value[key]
    if 'integerValue' in value: return int(value['integerValue'])
    if 'arrayValue' in value: return [decode(x) for x in value['arrayValue'].get('values', [])]
    if 'mapValue' in value: return {k: decode(v) for k, v in value['mapValue'].get('fields', {}).items()}
    raise ValueError('Campo de Firestore no compatible.')


class FirebaseClient:
    def __init__(self, project, api_key):
        if not project or not api_key: raise ValueError('Falta la configuración pública de Firebase.')
        self.project, self.api_key = project, api_key
        self.uid = self.token = self.refresh = None
        self.expires = 0

    def sign_in(self, email, password):
        url = 'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=' + urllib.parse.quote(self.api_key)
        result = request_json(url, data={'email': email, 'password': password, 'returnSecureToken': True})
        self.uid, self.token, self.refresh = result['localId'], result['idToken'], result['refreshToken']
        self.expires = time.monotonic() + int(result['expiresIn']) - 90

    def headers(self):
        if not self.token: raise ValueError('Inicia sesión en la cuenta de la app.')
        if time.monotonic() >= self.expires:
            url = 'https://securetoken.googleapis.com/v1/token?key=' + urllib.parse.quote(self.api_key)
            result = request_json(url, data={'grant_type': 'refresh_token', 'refresh_token': self.refresh}, form=True)
            if result['user_id'] != self.uid: raise ValueError('La sesión cambió de usuario.')
            self.token, self.refresh = result['id_token'], result['refresh_token']
            self.expires = time.monotonic() + int(result['expires_in']) - 90
        return {'Authorization': 'Bearer ' + self.token}

    def url(self, path):
        return f'https://firestore.googleapis.com/v1/projects/{urllib.parse.quote(self.project)}/databases/(default)/documents/' + urllib.parse.quote(path, safe='/')

    def get(self, path):
        try:
            result = request_json(self.url(path), headers=self.headers())
        except ApiError as error:
            if error.status == 404: return None, None
            raise
        return {k: decode(v) for k, v in result.get('fields', {}).items()}, result.get('updateTime')

    def patch(self, path, data, *, expected=None, create=False):
        query = {'currentDocument.updateTime': expected} if expected else {'currentDocument.exists': 'false'} if create else {}
        url = self.url(path) + ('?' + urllib.parse.urlencode(query) if query else '')
        return request_json(url, method='PATCH', headers=self.headers(), data={'fields': {k: encode(v) for k, v in data.items()}})

    def fixtures(self, scope):
        league, season, round_number = scope.split('/')
        path = f'{league}/Resultados/'
        if season != '2025-2026': path += f'Temporadas/{season}/'
        path += f'Jornadas/{round_number}/Partidos'
        result, token, docs = {}, None, []
        while True:
            query = {'pageSize': '100'}
            if token: query['pageToken'] = token
            result = request_json(self.url(path) + '?' + urllib.parse.urlencode(query), headers=self.headers())
            docs.extend(result.get('documents', []))
            token = result.get('nextPageToken')
            if not token: break
            if len(docs) > 100: raise ValueError('Demasiados partidos en la jornada.')
        return [Fixture.from_document(d['name'].rsplit('/', 1)[-1], {k: decode(v) for k, v in d.get('fields', {}).items()}) for d in docs]

    @property
    def command_path(self): return f'PuenteJornada/{self.uid}'
    @property
    def state_path(self): return self.command_path + '/Estado/actual'

    def claim(self, agent_id, now):
        previous, version = self.get(self.state_path)
        previous = previous or {}
        lease = previous.get('leaseUntil')
        if previous.get('agentId') not in (None, agent_id) and lease and instant(lease) > now:
            raise ValueError('Otro PC tiene el ensayo activo. Cierra el otro programa y espera un minuto.')
        claim = {**previous, 'mode': 'simulation', 'agentId': agent_id,
                 'leaseUntil': now + timedelta(seconds=60), 'lastSeenAt': now}
        result = self.patch(self.state_path, claim, expected=version, create=version is None)
        return result['updateTime']


class SportsDbResults:
    def __init__(self, api_key='123'):
        self.api_key = str(api_key)
        self.cache = {}

    def enrich(self, scope, fixtures, now):
        cached = self.cache.get(scope)
        if cached and now - cached[0] < timedelta(seconds=60):
            events = cached[1]
        else:
            _, season, round_number = scope.split('/')
            params = urllib.parse.urlencode({'id': '4335', 'r': round_number, 's': season})
            url = 'https://www.thesportsdb.com/api/v1/json/' + urllib.parse.quote(self.api_key, safe='') + '/eventsround.php?' + params
            events = request_json(url).get('events')
            if not isinstance(events, list) or len(events) != 10:
                raise ValueError('El proveedor no confirmó los diez partidos. No se simula una apuesta nueva.')
            self.cache[scope] = (now, events)
        def key(home, away): return (' '.join(home.casefold().split()), ' '.join(away.casefold().split()))
        actual = {key(str(e.get('strHomeTeam', '')), str(e.get('strAwayTeam', ''))): e for e in events}
        if len(actual) != 10: raise ValueError('El proveedor devolvió equipos duplicados.')
        output = []
        for m in fixtures:
            event = actual.get(key(m.home, m.away))
            if event is None: raise ValueError('Los equipos de Firestore no coinciden exactamente con el proveedor.')
            status = str(event.get('strStatus') or '').strip().lower()
            stamp = event.get('strTimestamp')
            if not stamp:
                day, hour = event.get('dateEvent'), event.get('strTime')
                stamp = f'{day}T{hour}' if day and hour else None
            if not stamp: raise ValueError('El proveedor no confirmó todos los horarios.')
            if not re_zone(stamp): stamp += 'Z'
            output.append(Fixture(m.id, m.home, m.away, instant(stamp), status in FINAL,
                                  score(event.get('intHomeScore')), score(event.get('intAwayScore')), status in UNAVAILABLE))
        return output


def re_zone(stamp):
    import re
    return re.search(r'(Z|[+-]\d{2}:?\d{2})$', stamp, re.I)
