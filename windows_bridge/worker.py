"""Coordinador de ensayo. No contiene ningún adaptador de apuestas reales."""
import hashlib
import json
import re
from datetime import datetime, timedelta, timezone
from engine import Authorization, decide, iso


class Worker:
    def __init__(self, client, ledger, provider, agent_id, should_stop=lambda: False):
        self.client, self.ledger, self.provider, self.agent_id = client, ledger, provider, agent_id
        self.should_stop = should_stop
        self.ledger.db.execute('CREATE TABLE IF NOT EXISTS requests (id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL)')
        self.ledger.db.commit()

    def tick(self, now=None):
        try:
            return self._tick(now)
        except Exception as error:
            # Publica el bloqueo si el lease sigue siendo nuestro. Si no hay red,
            # el móvil detectará que no llegan señales nuevas.
            try:
                state, version = self.client.get(self.client.state_path)
                if state and state.get('agentId') == self.agent_id:
                    state.update(status='blocked', message=f'En espera: {error}')
                    self.client.patch(self.client.state_path, state, expected=version)
            except Exception:
                pass
            raise

    def _tick(self, now=None):
        clock = (lambda: now) if now is not None else (lambda: datetime.now(timezone.utc))
        now = clock()
        command, _ = self.client.get(self.client.command_path)
        previous_state, _ = self.client.get(self.client.state_path)
        version = self.client.claim(self.agent_id, now)
        state = {'mode': 'simulation', 'agentId': self.agent_id,
                 'lastSeenAt': now, 'leaseUntil': now + timedelta(seconds=60),
                 'requestId': '', 'scope': '', 'status': 'idle',
                 'message': 'Conectado. Esperando el OK desde la app.', 'bets': [], 'results': {}}
        if command is not None:
            if command.get('schema') != 1 or command.get('mode') != 'simulation':
                raise ValueError('Este programa solo acepta ensayos de la app.')
            rid = command.get('requestId', '')
            if not re.fullmatch(r'[a-f0-9]{32}', rid):
                raise ValueError('Identificador de autorización no válido.')
            auth = Authorization.parse(command['authorization'])
            if command.get('scope') != auth.scope:
                raise ValueError('La jornada no coincide con la autorización.')
            state.update(requestId=rid, scope=auth.scope)
            if previous_state and previous_state.get('requestId') == rid:
                state['results'] = previous_state.get('results', {})
            immutable = {k: command.get(k) for k in ('scope', 'authorization', 'initialBets')}
            fingerprint = hashlib.sha256(json.dumps(immutable, sort_keys=True, allow_nan=False).encode()).hexdigest()
            row = self.ledger.db.execute('SELECT fingerprint FROM requests WHERE id=?', (rid,)).fetchone()
            if row and row[0] != fingerprint:
                raise ValueError('Se modificó una autorización existente. Requiere un nuevo OK.')
            with self.ledger.db:
                self.ledger.db.execute('INSERT OR IGNORE INTO requests VALUES (?, ?)', (rid, fingerprint))
            initial = command.get('initialBets', [])
            if not isinstance(initial, list): raise ValueError('Historial no válido.')
            remote_bets = None
            if previous_state and previous_state.get('requestId') == rid:
                remote_bets = previous_state.get('bets')
                if remote_bets is not None and not isinstance(remote_bets, list):
                    raise ValueError('Historial remoto no válido.')
            seed = remote_bets if remote_bets is not None else initial
            if seed[:len(initial)] != initial:
                raise ValueError('El historial remoto no conserva el historial autorizado.')
            self.ledger.seed(rid, seed)
            local = self.ledger.bets(rid)
            if remote_bets is not None:
                common = min(len(local), len(remote_bets))
                if local[:common] != remote_bets[:common]:
                    raise ValueError('Los historiales del PC y del servidor no coinciden.')
                for i in range(len(local), len(remote_bets)):
                    if i >= 9 or remote_bets[i].get('cents') != 100 * 2**i:
                        raise ValueError('Progresión remota incorrecta.')
                    if not self.ledger.insert(rid, remote_bets[i], i):
                        raise ValueError('Historial remoto duplicado.')
            if previous_state and previous_state.get('requestId') == rid and previous_state.get('status') in ('stopped', 'revoked'):
                self.ledger.terminate(rid, str(previous_state.get('message') or 'Ensayo detenido.'))
            action = command.get('action')
            if action not in ('authorize', 'revoke'):
                raise ValueError('Acción no reconocida.')
            if action == 'revoke':
                self.ledger.terminate(rid, 'Autorización revocada desde la app.')
            terminal = self.ledger.terminal(rid)
            bets = self.ledger.bets(rid)
            if terminal:
                state.update(status='revoked' if action == 'revoke' else 'stopped', message=terminal)
            else:
                fixtures = self.provider.enrich(auth.scope, self.client.fixtures(auth.scope), now)
                state['results'] = {m.id: {'finished': m.final, 'homeGoals': m.hg, 'awayGoals': m.ag} for m in fixtures}
                plan = decide(auth, fixtures, bets, clock())
                state.update(status=plan.status, message=plan.message)
                if plan.status == 'stopped':
                    self.ledger.terminate(rid, plan.message)
                elif plan.status == 'ready':
                    # Releer después de consultar resultados: una revocación o sustitución impide avanzar.
                    current, _ = self.client.get(self.client.command_path)
                    if self.should_stop() or not current or current.get('requestId') != rid or current.get('action') != 'authorize' or any(current.get(k) != command.get(k) for k in immutable):
                        state.update(status='waiting', message='Cambió la autorización; se revisará antes de continuar.')
                    else:
                        # No registrar tarde tras un acceso de red lento.
                        plan = decide(auth, fixtures, bets, clock())
                        if plan.status != 'ready':
                            state.update(status=plan.status, message=plan.message, bets=bets)
                            state['spentCents'] = sum(b['cents'] for b in bets)
                            if plan.status == 'stopped': self.ledger.terminate(rid, plan.message)
                            self.client.patch(self.client.state_path, state, expected=version)
                            return state
                        bet = {'mode': 'simulation', 'matchId': plan.match.id,
                               'label': f'{plan.match.home} — {plan.match.away}', 'cents': plan.cents,
                               'odds': auth.odds, 'approvedAt': iso(clock())}
                        self.ledger.insert(rid, bet, len(bets))
                        bets = self.ledger.bets(rid)
                        state.update(status='waiting', message=f'Ensayo registrado: {bet["label"]}, {plan.cents / 100:.2f} €. Esperando resultado.')
            state['bets'] = bets
        state['spentCents'] = sum(b['cents'] for b in state['bets'])
        self.client.patch(self.client.state_path, state, expected=version)
        return state
