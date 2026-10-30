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
  print('$checks comprobaciones Dart de rearme superadas.');
}
