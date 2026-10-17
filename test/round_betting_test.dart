import 'package:flutter_test/flutter_test.dart';
import 'package:plantillalogin/core/roundBetting.dart';
import 'package:plantillalogin/core/sportsDbFixture.dart';

void main() {
  final now = DateTime.utc(2026, 10, 17, 10);
  RoundFixture fixture(
    String id,
    int hour, {
    bool finished = false,
    int? homeGoals,
    int? awayGoals,
  }) => RoundFixture(
    id: id,
    home: 'Local $id',
    away: 'Visitante $id',
    kickoff: DateTime.utc(2026, 10, 17, hour),
    finished: finished,
    homeGoals: homeGoals,
    awayGoals: awayGoals,
  );
  RehearsalBet bet(String id, int cents) => RehearsalBet(
    matchId: id,
    label: id,
    cents: cents,
    odds: 3.2,
    approvedAt: now,
  );
  RoundPlan plan(
    List<RoundFixture> matches, [
    List<RehearsalBet> bets = const [],
  ]) => RoundBetting.plan(fixtures: matches, bets: bets, now: now);

  test('Cada jornada independiente empieza en un euro', () {
    expect(plan([fixture('a', 12)]).cents, 100);
    expect(plan([fixture('otra-jornada', 15)]).cents, 100);
  });
  test('Duplica solo tras una apuesta con derrota final confirmada', () {
    final p = plan(
      [
        fixture('a', 8, finished: true, homeGoals: 1, awayGoals: 0),
        fixture('b', 12),
      ],
      [bet('a', 100)],
    );
    expect(p.cents, 200);
    expect(p.candidates.single.id, 'b');
  });
  test('Un empate final no apostado también detiene la jornada', () {
    final p = plan([
      fixture('a', 8, finished: true, homeGoals: 1, awayGoals: 1),
      fixture('b', 12),
    ]);
    expect(p.stopped, isTrue);
    expect(p.canPrepare, isFalse);
  });
  test('Un 0-0 en directo no se considera empate final', () {
    final p = plan([
      fixture('a', 9, homeGoals: 0, awayGoals: 0),
      fixture('b', 12),
    ]);
    expect(p.stopped, isFalse);
    expect(p.canPrepare, isFalse);
    expect(p.message, contains('sin resultado final'));
  });
  test('No se prepara otra apuesta mientras la anterior está pendiente', () {
    expect(
      plan([fixture('a', 12), fixture('b', 15)], [bet('a', 100)]).canPrepare,
      isFalse,
    );
  });
  test('Los horarios simultáneos y solapados ofrecen todas las opciones', () {
    final p = plan([
      fixture('a', 12),
      fixture('b', 12),
      fixture('c', 13),
      fixture('d', 14),
    ]);
    expect(p.candidates.map((m) => m.id), ['a', 'b', 'c']);
  });
  test('Un horario desconocido bloquea la preparación', () {
    final p = plan([
      fixture('a', 12),
      const RoundFixture(id: 'b', home: 'B', away: 'C'),
    ]);
    expect(p.canPrepare, isFalse);
    expect(p.message, contains('horarios'));
  });
  test('No inventa resultados cuando faltan goles', () {
    expect(plan([fixture('a', 8, finished: true)]).stopped, isFalse);
    expect(plan([fixture('a', 8, finished: true)]).canPrepare, isFalse);
  });
  test(
    'Un historial duplicado o con importe incorrecto bloquea la preparación',
    () {
      final fixtures = [
        fixture('a', 8, finished: true, homeGoals: 1, awayGoals: 0),
        fixture('b', 12),
      ];
      expect(plan(fixtures, [bet('a', 200)]).canPrepare, isFalse);
      expect(
        plan(fixtures, [bet('a', 100), bet('a', 200)]).canPrepare,
        isFalse,
      );
    },
  );
  test(
    'Nueve derrotas alcanzan el límite y otra jornada reinicia en 1 euro',
    () {
      final fixtures = List.generate(
        9,
        (i) => fixture('$i', 8, finished: true, homeGoals: 1, awayGoals: 0),
      );
      final bets = List.generate(9, (i) => bet('$i', 100 * (1 << i)));
      expect(
        plan([...fixtures, fixture('siguiente', 12)], bets).stopped,
        isTrue,
      );
      expect(plan([fixture('nueva-jornada', 12)]).cents, 100);
    },
  );
  test('Los registros guardados conservan el modo simulación', () {
    final original = bet('a', 100);
    final restored = RehearsalBet.fromJson(original.toJson());
    expect(restored.cents, 100);
    expect(restored.odds, 3.2);
    expect(restored.approvedAt, original.approvedAt);
    expect(
      () => RehearsalBet.fromJson({...original.toJson(), 'mode': 'live'}),
      throwsFormatException,
    );
    expect(
      () => RehearsalBet.fromJson({...original.toJson(), 'odds': double.nan}),
      throwsFormatException,
    );
  });
  test('El proveedor exige estado final, no solo marcador', () {
    expect(
      sportsDbFinished({
        'intHomeScore': '0',
        'intAwayScore': '0',
        'strStatus': '1H',
      }),
      isFalse,
    );
    expect(sportsDbFinished({'strStatus': 'Match Finished'}), isTrue);
    expect(sportsDbFinished({}), isFalse);
  });
  test('Interpreta UTC explícito, offsets y el horario UTC separado', () {
    expect(
      sportsDbKickoff({'strTimestamp': '2026-10-17T12:00:00'}),
      DateTime.utc(2026, 10, 17, 12),
    );
    expect(
      sportsDbKickoff({'strTimestamp': '2026-10-17T14:00:00+02:00'}),
      DateTime.utc(2026, 10, 17, 12),
    );
    expect(
      sportsDbKickoff({'dateEvent': '2026-10-17', 'strTime': '12:00:00'}),
      DateTime.utc(2026, 10, 17, 12),
    );
    expect(sportsDbKickoff({'dateEvent': '2026-10-17'}), isNull);
  });
}
