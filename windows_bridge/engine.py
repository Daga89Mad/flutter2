"""Motor de ensayo: nunca conecta con Betfair ni produce órdenes de apuestas."""
from __future__ import annotations
import json
import math
import re
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

UTC = timezone.utc
FINAL = {'ft', 'match finished', 'full time', 'finalizado'}
UNAVAILABLE = {'postponed', 'cancelled', 'canceled', 'aplazado', 'cancelado', 'pst', 'canc'}
STAKES = [100 * 2**i for i in range(9)]


def instant(value: str) -> datetime:
    if not isinstance(value, str):
        raise ValueError('Fecha no válida.')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('La fecha debe incluir su zona horaria.')
    return parsed.astimezone(UTC)


def iso(value: datetime) -> str:
    return value.astimezone(UTC).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def score(value):
    if isinstance(value, bool):
        return None
    text = str(value).strip()
    return int(text) if re.fullmatch(r'\d+', text) else None


@dataclass(frozen=True)
class Fixture:
    id: str
    home: str
    away: str
    kickoff: datetime | None
    finished: bool = False
    hg: int | None = None
    ag: int | None = None
    unavailable: bool = False

    @property
    def final(self):
        return self.finished and self.hg is not None and self.ag is not None

    @property
    def draw(self):
        return self.final and self.hg == self.ag

    @classmethod
    def from_document(cls, identifier: str, data: dict):
        status = str(data.get('Estado', '')).strip().lower()
        raw = data.get('InicioUTC')
        return cls(identifier, str(data.get('Local', '')), str(data.get('Visitante', '')),
                   instant(raw) if raw else None,
                   data.get('Finalizado') is True or status in FINAL,
                   score(data.get('GolesLocal')), score(data.get('GolesVisitante')),
                   status in UNAVAILABLE)


def normalized_schedule(fixtures: list[Fixture]):
    return sorted((m.id, m.home, m.away, m.kickoff, m.unavailable) for m in fixtures)


def parse_schedule(raw: str):
    rows = json.loads(raw)
    if not isinstance(rows, list) or len(rows) != 10:
        raise ValueError('El calendario autorizado debe tener diez partidos.')
    result = []
    for row in rows:
        if not isinstance(row, list) or len(row) != 5 or not isinstance(row[4], bool):
            raise ValueError('Calendario no válido.')
        if not all(isinstance(x, str) and x for x in row[:3]):
            raise ValueError('Faltan identificadores o equipos.')
        result.append((row[0], row[1], row[2], instant(row[3]) if row[3] else None, row[4]))
    if len({r[0] for r in result}) != 10:
        raise ValueError('El calendario contiene identificadores duplicados.')
    return sorted(result)


@dataclass(frozen=True)
class Authorization:
    scope: str
    schedule: list
    selected: frozenset
    budget: int
    odds: float
    approved: datetime
    expires: datetime

    @classmethod
    def parse(cls, data: dict):
        if data.get('mode') != 'round-simulation-v1':
            raise ValueError('Solo se admite simulación; no hay modo de dinero real.')
        scope = data.get('scope', '')
        if not re.fullmatch(r'LaLiga/\d{4}-\d{4}/(?:[1-9]|[12]\d|3[0-8])', scope):
            raise ValueError('Jornada no válida.')
        years = scope.split('/')[1].split('-')
        if int(years[1]) != int(years[0]) + 1:
            raise ValueError('Temporada no válida.')
        budget = data.get('budgetCents')
        odds = data.get('rehearsalOdds')
        if type(budget) is not int or not 100 <= budget <= 51100:
            raise ValueError('Presupuesto de ensayo fuera de los límites.')
        if isinstance(odds, bool) or not isinstance(odds, (float, int)) or not math.isfinite(odds) or odds < 2.8:
            raise ValueError('Cuota ficticia no válida.')
        selected = data.get('selectedIds')
        if not isinstance(selected, list) or not selected or not all(isinstance(i, str) for i in selected):
            raise ValueError('Faltan los partidos elegidos.')
        if len(set(selected)) != len(selected):
            raise ValueError('Selecciones duplicadas.')
        schedule = parse_schedule(data['schedule'])
        if not set(selected) <= {r[0] for r in schedule}:
            raise ValueError('Se autorizó un partido ajeno al calendario.')
        approved, expires = instant(data['approvedAt']), instant(data['expiresAt'])
        if expires <= approved:
            raise ValueError('Caducidad incorrecta.')
        # Ninguna autorización puede seleccionar dos encuentros solapados.
        times = [r[3] for r in schedule if r[0] in selected]
        if any(t is None for t in times):
            raise ValueError('Falta el horario de una selección.')
        times.sort()
        if any(b - a < timedelta(minutes=120) for a, b in zip(times, times[1:])):
            raise ValueError('Las selecciones autorizadas se solapan.')
        return cls(scope, schedule, frozenset(selected), budget, float(odds), approved, expires)


def valid_bet(raw: dict):
    if raw.get('mode') != 'simulation' or type(raw.get('cents')) is not int or raw['cents'] not in STAKES:
        raise ValueError('Apuesta ajena al modo de ensayo o con importe no válido.')
    odds = raw.get('odds')
    if isinstance(odds, bool) or not isinstance(odds, (int, float)) or not math.isfinite(odds) or odds < 2.8:
        raise ValueError('Cuota de historial no válida.')
    if not isinstance(raw.get('matchId'), str) or not raw['matchId']:
        raise ValueError('Identificador de historial no válido.')
    instant(raw['approvedAt'])
    return raw


@dataclass(frozen=True)
class Decision:
    status: str
    message: str
    match: Fixture | None = None
    cents: int = 100


def decide(auth: Authorization, fixtures: list[Fixture], bets: list[dict], now: datetime):
    if now < auth.approved or now >= auth.expires:
        return Decision('stopped', 'Autorización caducada o reloj incorrecto. Requiere otro OK.')
    if normalized_schedule(fixtures) != auth.schedule:
        return Decision('stopped', 'Cambió el calendario. Revisa la jornada y autoriza de nuevo.')
    if any(m.draw for m in fixtures):
        return Decision('stopped', 'Jornada detenida: ya hay un empate final.')
    by_id = {m.id: m for m in fixtures}
    cents, seen, spent = 100, set(), 0
    for raw in bets:
        bet = valid_bet(raw)
        match = by_id.get(bet['matchId'])
        if match is None or match.id in seen or bet['cents'] != cents or instant(bet['approvedAt']) > now:
            return Decision('stopped', 'El historial no coincide con la progresión autorizada.')
        seen.add(match.id)
        spent += cents
        if not match.final:
            return Decision('waiting', 'Esperando resultado final de la apuesta simulada.')
        cents *= 2
    if cents > 25600:
        return Decision('stopped', 'Alcanzado el límite de 256 €. La próxima jornada empieza en 1 €.')
    remaining = [m for m in fixtures if not m.final and not m.unavailable]
    if not remaining:
        return Decision('stopped', 'Jornada terminada.')
    if any(m.kickoff is None for m in remaining):
        return Decision('waiting', 'Faltan horarios fiables.')
    if any(m.kickoff <= now for m in remaining):
        return Decision('waiting', 'Hay encuentros iniciados sin resultado final confirmado.')
    if spent + cents > auth.budget:
        return Decision('stopped', 'Presupuesto acumulado de la jornada alcanzado.')
    remaining.sort(key=lambda m: (m.kickoff, m.id))
    end = remaining[0].kickoff + timedelta(minutes=120)
    chosen = [m for m in remaining if m.kickoff < end and m.id in auth.selected]
    if len(chosen) != 1:
        return Decision('waiting', 'Esperando el siguiente partido elegido.')
    match = chosen[0]
    if match.kickoff - now > timedelta(minutes=5):
        return Decision('waiting', f'Esperando los cinco minutos previos a {match.home} — {match.away}.', cents=cents)
    return Decision('ready', 'Preparada para simular, sin envío de dinero.', match, cents)


class Ledger:
    """SQLite conserva el ensayo antes de notificarlo; UNIQUE evita repetirlo tras un fallo de red."""
    def __init__(self, path: Path | str):
        self.db = sqlite3.connect(str(path), timeout=10)
        self.db.execute('CREATE TABLE IF NOT EXISTS bets (request_id TEXT, match_id TEXT, sequence INTEGER, data TEXT, PRIMARY KEY(request_id, match_id), UNIQUE(request_id, sequence))')
        self.db.execute('CREATE TABLE IF NOT EXISTS sessions (request_id TEXT PRIMARY KEY, terminal TEXT)')
        self.db.commit()

    def bets(self, request_id):
        return [json.loads(r[0]) for r in self.db.execute('SELECT data FROM bets WHERE request_id=? ORDER BY sequence', (request_id,))]

    def seed(self, request_id, initial):
        if self.db.execute('SELECT 1 FROM sessions WHERE request_id=?', (request_id,)).fetchone():
            return
        seen = set()
        if len(initial) > 9:
            raise ValueError('Historial demasiado largo.')
        with self.db:
            self.db.execute('INSERT INTO sessions(request_id, terminal) VALUES (?, NULL)', (request_id,))
            for i, bet in enumerate(initial):
                valid_bet(bet)
                if bet['matchId'] in seen or bet['cents'] != STAKES[i]:
                    raise ValueError('Historial inicial incoherente.')
                seen.add(bet['matchId'])
                self.db.execute('INSERT INTO bets VALUES (?, ?, ?, ?)', (request_id, bet['matchId'], i, json.dumps(bet)))

    def insert(self, request_id, bet, sequence):
        valid_bet(bet)
        with self.db:
            cursor = self.db.execute('INSERT OR IGNORE INTO bets VALUES (?, ?, ?, ?)',
                                     (request_id, bet['matchId'], sequence, json.dumps(bet)))
        return cursor.rowcount == 1

    def terminate(self, request_id, reason):
        with self.db:
            self.db.execute('UPDATE sessions SET terminal=? WHERE request_id=?', (reason, request_id))

    def terminal(self, request_id):
        row = self.db.execute('SELECT terminal FROM sessions WHERE request_id=?', (request_id,)).fetchone()
        return row[0] if row else None

    def close(self):
        self.db.close()
