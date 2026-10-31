import '../lib/core/liveRoundRestart.dart';

void main() {
  final command = <String, dynamic>{
    'mode': 'live-round-128-v1',
    'requestId': 'a' * 32,
  };
  final state = <String, dynamic>{
    'requestId': 'a' * 32,
    'fingerprint': 'hash',
    'terminal': true,
    'reservedCount': 0,
    'orders': <dynamic>[],
    'spentCents': 0,
    'status': 'stopped',
  };
  var checks = 0;
  void check(bool ok) {
    if (!ok) throw StateError('restart check failed: $checks');
    checks++;
  }

  check(canReplaceUnusedLiveRound(command, state));
  check(!canReplaceUnusedLiveRound(null, state));
  check(!canReplaceUnusedLiveRound(command, null));
  for (final change in <Map<String, dynamic>>[
    {'terminal': false},
    {'reservedCount': 1},
    {
      'orders': [{}],
    },
    {'orders': null},
    {'spentCents': 100},
    {'requestId': 'b' * 32},
    {'status': 'review'},
    {'status': 'won'},
    {'fingerprint': ''},
  ]) {
    check(!canReplaceUnusedLiveRound(command, {...state, ...change}));
  }
  check(!canReplaceUnusedLiveRound({...command, 'mode': 'simulation'}, state));
  check(canReplaceUnusedLiveRound(command, {...state, 'status': 'revoked'}));
  final settled = <String, dynamic>{
    'requestId': command['requestId'],
    'fingerprint': 'A' * 64,
    'terminal': true,
    'status': 'review_reconciled',
    'reservedCount': 1,
    'spentCents': 100,
    'evidence': 'recovery:${'B' * 64}',
    'orders': [
      <String, dynamic>{
        'status': 'SETTLED',
        'cents': 100,
        'matchedCents': 100,
        'profitLossCents': -100,
        'betId': 'bet',
        'strategyId': 'strategy',
        'settledAt': '2026-10-31T17:13:28Z',
        'odds': 3.25,
      },
    ],
  };
  check(canResumeReviewedLiveRound(command, settled));
  check(!canReplaceUnusedLiveRound(command, settled));
  for (final change in <Map<String, dynamic>>[
    {'spentCents': 0},
    {'terminal': false},
    {'status': 'review'},
    {'status': 'won'},
    {'reservedCount': 0},
    {'reservedCount': 8},
    {'fingerprint': 'wrong'},
    {'evidence': 'wrong'},
    {'requestId': 'b' * 32},
    {'orders': []},
    {
      'orders': [
        {
          ...(settled['orders'] as List).first as Map<String, dynamic>,
          'profitLossCents': 100,
        },
      ],
    },
  ]) {
    check(!canResumeReviewedLiveRound(command, {...settled, ...change}));
  }
  print('$checks comprobaciones Dart de rearme superadas.');
}
