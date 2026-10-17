import copy
import json
import tempfile
import unittest
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from engine import Authorization, Fixture, Ledger, decide, iso
from firebase_client import FirebaseClient, SportsDbResults, encode, decode
from worker import Worker
from unittest.mock import patch

NOW = datetime(2026, 10, 17, 10, tzinfo=timezone.utc)
RID = 'a' * 32


def fixtures():
    return [Fixture(str(i), f'Local {i}', f'Visitante {i}', NOW + timedelta(minutes=4, hours=3*i)) for i in range(10)]


def authorization(matches=None, budget=51100):
    matches = matches or fixtures()
    return {'mode': 'round-simulation-v1', 'scope': 'LaLiga/2026-2027/1',
            'schedule': json.dumps([[m.id, m.home, m.away, iso(m.kickoff) if m.kickoff else None, m.unavailable] for m in matches]),
            'selectedIds': [m.id for m in matches], 'budgetCents': budget, 'rehearsalOdds': 3.2,
            'approvedAt': iso(NOW - timedelta(minutes=1)), 'expiresAt': iso(NOW + timedelta(days=2))}


def bet(identifier='0', cents=100):
    return {'mode': 'simulation', 'matchId': identifier, 'label': identifier, 'cents': cents,
            'odds': 3.2, 'approvedAt': iso(NOW)}


class FakeClient:
    command_path = 'command'
    state_path = 'state'
    def __init__(self):
        self.command = {'schema': 1, 'mode': 'simulation', 'requestId': RID, 'action': 'authorize',
                        'scope': 'LaLiga/2026-2027/1', 'authorization': authorization(), 'initialBets': []}
        self.state = None
        self.matches = fixtures()
        self.fail_patch = False
        self.revoke_on_second_read = False
        self.reads = 0
    def get(self, path):
        if path == self.state_path: return copy.deepcopy(self.state), 'lease-version'
        self.reads += 1
        if self.revoke_on_second_read and self.reads == 2: self.command['action'] = 'revoke'
        return copy.deepcopy(self.command), 'command-version'
    def claim(self, agent, now):
        self.state = {**(self.state or {}), 'mode':'simulation', 'agentId':agent}
        return 'lease-version'
    def fixtures(self, scope): return self.matches
    def patch(self, path, data, expected=None):
        if self.fail_patch: raise OSError('sin red')
        assert expected == 'lease-version'
        self.state = copy.deepcopy(data)


class Provider:
    def enrich(self, scope, matches, now): return matches


class EngineTests(unittest.TestCase):
    def test_authorization_exported_by_dart_is_compatible(self):
        raw = json.loads((Path(__file__).parent / 'dart_authorization.json').read_text())
        auth = Authorization.parse(raw)
        plan = decide(auth, fixtures(), [], NOW)
        self.assertEqual((plan.status, plan.cents, plan.match.id), ('ready', 100, '0'))
    def test_start_one_and_wait_for_window(self):
        a = Authorization.parse(authorization())
        self.assertEqual(decide(a, fixtures(), [], NOW).cents, 100)
        self.assertEqual(decide(a, fixtures(), [], NOW - timedelta(seconds=30)).status, 'ready')
        self.assertEqual(decide(a, fixtures(), [], NOW - timedelta(minutes=2)).status, 'stopped')
    def test_only_final_result_doubles(self):
        matches = fixtures()
        matches[0] = replace(matches[0], hg=0, ag=0)
        a = Authorization.parse(authorization())
        self.assertEqual(decide(a, matches, [bet()], NOW).status, 'waiting')
        matches[0] = replace(matches[0], finished=True, hg=1)
        plan = decide(a, matches, [bet()], NOW + timedelta(hours=3))
        self.assertEqual((plan.status, plan.cents, plan.match.id), ('ready', 200, '1'))
    def test_draw_in_unselected_match_stops(self):
        matches = fixtures()
        raw = authorization()
        raw['selectedIds'] = ['0']
        matches[4] = replace(matches[4], finished=True, hg=2, ag=2)
        self.assertEqual(decide(Authorization.parse(raw), matches, [], NOW).status, 'stopped')
    def test_changed_calendar_stops(self):
        matches = fixtures()
        matches[0] = replace(matches[0], kickoff=NOW + timedelta(minutes=6))
        self.assertEqual(decide(Authorization.parse(authorization()), matches, [], NOW).status, 'stopped')
    def test_budget_and_expiry(self):
        matches = fixtures()
        matches[0] = replace(matches[0], finished=True, hg=1, ag=0)
        self.assertEqual(decide(Authorization.parse(authorization(budget=100)), matches, [bet()], NOW).status, 'stopped')
        self.assertEqual(decide(Authorization.parse(authorization()), fixtures(), [], NOW + timedelta(days=3)).status, 'stopped')
    def test_cap_and_independent_round(self):
        matches = fixtures()
        bets = [bet(str(i), 100*2**i) for i in range(9)]
        matches = [replace(m, finished=True, hg=1, ag=0) if i<9 else m for i,m in enumerate(matches)]
        self.assertEqual(decide(Authorization.parse(authorization()), matches, bets, NOW).status, 'stopped')
        self.assertEqual(decide(Authorization.parse(authorization()), fixtures(), [], NOW).cents, 100)
    def test_invalid_inputs(self):
        for changes in [{'mode':'live'}, {'budgetCents': True}, {'budgetCents':51200}, {'rehearsalOdds':float('nan')}, {'scope':'LaLiga/2026-2028/1'}, {'selectedIds':['0','0']}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                Authorization.parse({**authorization(), **changes})
    def test_unknown_time_and_overlaps_rejected(self):
        for kickoff in (None, fixtures()[0].kickoff):
            matches = fixtures()
            matches[1] = replace(matches[1], kickoff=kickoff)
            with self.assertRaises(ValueError): Authorization.parse(authorization(matches))
    def test_duplicate_or_incorrect_history(self):
        a = Authorization.parse(authorization())
        matches = [replace(m, finished=True, hg=1, ag=0) for m in fixtures()]
        for bets in ([bet(), bet('0', 200)], [bet('0', 200)], [bet('unknown')]):
            self.assertEqual(decide(a, matches, bets, NOW).status, 'stopped')
    def test_started_unknown_result_blocks(self):
        self.assertEqual(decide(Authorization.parse(authorization()), fixtures(), [], NOW + timedelta(minutes=5)).status, 'waiting')


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)/'ledger.sqlite'
        self.ledger = Ledger(self.path)
        self.client = FakeClient()
        self.worker = Worker(self.client, self.ledger, Provider(), 'pc')
    def tearDown(self):
        self.ledger.close()
        self.temp.cleanup()
    def test_restart_does_not_repeat(self):
        self.worker.tick(NOW)
        self.ledger.close()
        self.ledger = Ledger(self.path)
        Worker(self.client, self.ledger, Provider(), 'pc').tick(NOW)
        self.assertEqual(len(self.client.state['bets']), 1)
    def test_network_failure_after_insert_is_idempotent(self):
        self.client.fail_patch = True
        with self.assertRaises(OSError): self.worker.tick(NOW)
        self.client.fail_patch = False
        self.worker.tick(NOW)
        self.assertEqual(len(self.client.state['bets']), 1)
    def test_revoke_during_fetch(self):
        self.client.revoke_on_second_read = True
        self.worker.tick(NOW)
        self.assertEqual(self.client.state['bets'], [])
        self.worker.tick(NOW)
        self.assertEqual(self.client.state['status'], 'revoked')
    def test_terminal_stays_stopped_after_results_change(self):
        self.client.matches[4] = replace(self.client.matches[4], finished=True, hg=0, ag=0)
        self.worker.tick(NOW)
        self.client.matches = fixtures()
        self.worker.tick(NOW)
        self.assertEqual(self.client.state['bets'], [])
        self.assertEqual(self.client.state['status'], 'stopped')
    def test_modified_authorization_is_rejected(self):
        self.worker.tick(NOW)
        self.client.command['authorization']['budgetCents'] = 100
        with self.assertRaises(ValueError): self.worker.tick(NOW)
    def test_revoked_before_start_has_no_bet(self):
        self.client.command['action'] = 'revoke'
        self.worker.tick(NOW)
        self.assertEqual(self.client.state['bets'], [])
        self.assertEqual(self.client.state['status'], 'revoked')
    def test_unavailable_feed_does_not_register(self):
        with patch.object(Provider, 'enrich', side_effect=OSError('sin resultados')):
            with self.assertRaises(OSError): self.worker.tick(NOW)
        self.assertEqual(self.ledger.bets(RID), [])
    def test_second_pc_recovers_cloud_history_without_duplicate(self):
        self.worker.tick(NOW)
        another = Ledger(':memory:')
        try:
            Worker(self.client, another, Provider(), 'pc2').tick(NOW)
            self.assertEqual(len(another.bets(RID)), 1)
            self.assertEqual(another.bets(RID), self.ledger.bets(RID))
        finally: another.close()
    def test_stopped_pc_does_not_register_after_fetch(self):
        Worker(self.client, self.ledger, Provider(), 'pc', should_stop=lambda:True).tick(NOW)
        self.assertEqual(self.client.state['bets'], [])
    def test_feed_error_is_published_as_blocked(self):
        with patch.object(Provider, 'enrich', side_effect=OSError('sin resultados')):
            with self.assertRaises(OSError): self.worker.tick(NOW)
        self.assertEqual(self.client.state['status'], 'blocked')
    def test_new_request_is_independent(self):
        self.client.command['action'] = 'revoke'
        self.worker.tick(NOW)
        self.client.command.update(requestId='b'*32, action='authorize')
        self.worker.tick(NOW)
        self.assertEqual(self.client.state['bets'][0]['cents'], 100)


class RestTests(unittest.TestCase):
    def test_field_encoding(self):
        data = {'x': [True, 1, 3.2, None, {'s':'hola'}]}
        self.assertEqual(decode(encode(data)), data)
        self.assertEqual(decode(encode(NOW)), iso(NOW))
        with self.assertRaises(ValueError): encode(float('inf'))
    def test_lease_prevents_other_pc(self):
        client = FirebaseClient('project', 'public')
        client.get = lambda path: ({'agentId':'other', 'leaseUntil':iso(NOW+timedelta(seconds=20))}, 'version')
        with self.assertRaises(ValueError): client.claim('new-pc', NOW)
    def test_claim_uses_compare_and_swap(self):
        client = FirebaseClient('project', 'public')
        client.get = lambda path: (None, None)
        with patch.object(client, 'patch', return_value={'updateTime':'created'}) as write:
            self.assertEqual(client.claim('pc', NOW), 'created')
            self.assertTrue(write.call_args.kwargs['create'])
        client.get = lambda path: ({'agentId':'pc'}, 'previous')
        with patch.object(client, 'patch', return_value={'updateTime':'updated'}) as write:
            client.claim('pc', NOW)
            self.assertEqual(write.call_args.kwargs['expected'], 'previous')
    def test_provider_requires_ten_events(self):
        with patch('firebase_client.request_json', return_value={'events':None}):
            with self.assertRaises(ValueError): SportsDbResults().enrich('LaLiga/2026-2027/1', fixtures(), NOW)
    def test_pending_zero_zero_not_final_and_feed_cache_expires(self):
        events = [{'strHomeTeam':m.home, 'strAwayTeam':m.away, 'strTimestamp':iso(m.kickoff),
                   'strStatus':'Not Started', 'intHomeScore':'0', 'intAwayScore':'0'} for m in fixtures()]
        provider = SportsDbResults()
        with patch('firebase_client.request_json', return_value={'events':events}) as fetch:
            self.assertFalse(provider.enrich('LaLiga/2026-2027/1', fixtures(), NOW)[0].draw)
            provider.enrich('LaLiga/2026-2027/1', fixtures(), NOW+timedelta(seconds=30))
            self.assertEqual(fetch.call_count, 1)
        with patch('firebase_client.request_json', side_effect=OSError('sin red')):
            with self.assertRaises(OSError): provider.enrich('LaLiga/2026-2027/1', fixtures(), NOW+timedelta(seconds=61))


if __name__ == '__main__': unittest.main()
