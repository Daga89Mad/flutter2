import 'package:flutter_test/flutter_test.dart';
import 'package:plantillalogin/core/roundAuthorization.dart';
import 'package:plantillalogin/core/roundBetting.dart';
import 'package:plantillalogin/core/roundRehearsal.dart';

void main() {
  final now = DateTime.utc(2026, 10, 18, 15);
  List<RoundFixture> fixtures() => List.generate(
    10,
    (i) => RoundFixture(
      id: '$i',
      home: 'Local $i',
      away: 'Visitante $i',
      kickoff: now.add(Duration(hours: (i - 2) * 3, minutes: 4)),
      finished: i < 2,
      homeGoals: i < 2 ? 1 : null,
      awayGoals: i == 0
          ? 1
          : i == 1
          ? 0
          : null,
    ),
  );
  RoundAuthorization start(
    List<RoundFixture> matches, {
    int previous = 0,
    int budget = 51100,
  }) => RoundAuthorization.issue(
    scope: 'LaLiga/2026-2027/9',
    fixtures: matches,
    selectedIds: matches.where((m) => !m.hasResult).map((m) => m.id).toSet(),
    budgetCents: budget,
    rehearsalOdds: 3.2,
    now: now,
    fromNow: true,
    previousSpentCents: previous,
  );
  RehearsalBet bet(String id, int cents) => RehearsalBet(
    matchId: id,
    label: id,
    cents: cents,
    odds: 3.2,
    approvedAt: now,
  );
  List<RoundFixture> finish(
    List<RoundFixture> matches,
    String id,
    int h,
    int a,
  ) => matches
      .map(
        (m) => m.id == id
            ? RoundFixture(
                id: m.id,
                home: m.home,
                away: m.away,
                kickoff: m.kickoff,
                finished: true,
                homeGoals: h,
                awayGoals: a,
              )
            : m,
      )
      .toList();

  test('Inicio desde ahora permite un empate anterior y empieza en 1 euro', () {
    final a = start(fixtures());
    expect(a.fromNow, isTrue);
    expect(a.baselineFinishedIds, {'0', '1'});
    final p = a.next(
      currentScope: a.scope,
      fixtures: fixtures(),
      bets: [],
      now: now,
    );
    expect(p.canPrepare, isTrue);
    expect(p.cents, 100);
    expect(p.candidates.single.id, '2');
  });
  test('El modo original sigue detenido por el primer empate', () {
    expect(
      () => RoundAuthorization.issue(
        scope: 'LaLiga/2026-2027/9',
        fixtures: fixtures(),
        selectedIds: {'2'},
        budgetCents: 51100,
        rehearsalOdds: 3.2,
        now: now,
      ),
      throwsStateError,
    );
  });
  test(
    'El siguiente empate no seleccionado también detiene el nuevo ensayo',
    () {
      final a = start(fixtures());
      final updated = finish(fixtures(), '3', 0, 0);
      expect(
        a
            .next(currentScope: a.scope, fixtures: updated, bets: [], now: now)
            .stopped,
        isTrue,
      );
    },
  );
  test('Duplica tras una derrota nueva sin contar resultados anteriores', () {
    final a = start(fixtures());
    final updated = finish(fixtures(), '2', 1, 0);
    final p = a.next(
      currentScope: a.scope,
      fixtures: updated,
      bets: [bet('2', 100)],
      now: now.add(const Duration(hours: 3)),
    );
    expect(p.cents, 200);
    expect(p.candidates.single.id, '3');
  });
  test('El gasto de ensayos anteriores consume el presupuesto de jornada', () {
    final a = start(fixtures(), previous: 51000);
    final updated = finish(fixtures(), '2', 1, 0);
    expect(
      a
          .next(
            currentScope: a.scope,
            fixtures: updated,
            bets: [bet('2', 100)],
            now: now.add(const Duration(hours: 3)),
          )
          .stopped,
      isTrue,
    );
    expect(() => start(fixtures(), previous: 51100), throwsStateError);
  });
  test('No permite apostar partidos iniciados sin resultado confirmado', () {
    final matches = fixtures();
    final m = matches[2];
    matches[2] = m.withKickoff(now.subtract(const Duration(minutes: 10)));
    expect(() => start(matches), throwsStateError);
  });
  test('No ignora una pérdida de confirmación de un resultado anterior', () {
    final a = start(fixtures());
    final updated = fixtures();
    final m = updated[0];
    updated[0] = RoundFixture(
      id: m.id,
      home: m.home,
      away: m.away,
      kickoff: m.kickoff,
    );
    expect(
      a
          .next(currentScope: a.scope, fixtures: updated, bets: [], now: now)
          .stopped,
      isTrue,
    );
  });
  test('No reutiliza apuestas de partidos anteriores al nuevo OK', () {
    final a = start(fixtures());
    expect(
      a
          .next(
            currentScope: a.scope,
            fixtures: fixtures(),
            bets: [bet('0', 100)],
            now: now,
          )
          .stopped,
      isTrue,
    );
  });
  test('Persistencia v2 conserva la lista congelada y el gasto anterior', () {
    final a = start(fixtures(), previous: 300);
    final restored = RoundAuthorization.fromJson(a.toJson());
    expect(restored.toJson(), a.toJson());
    expect(restored.previousSpentCents, 300);
    expect(restored.toJson()['mode'], 'round-simulation-v2');
  });
  test('Rechaza baseline ajeno, seleccionado, duplicado y gasto negativo', () {
    final valid = start(fixtures()).toJson();
    for (final change in <Map<String, dynamic>>[
      {
        'baselineFinishedIds': ['ajeno'],
      },
      {
        'baselineFinishedIds': ['2'],
      },
      {
        'baselineFinishedIds': ['0', '0'],
      },
      {'previousSpentCents': -1},
      {'previousSpentCents': 51100},
      {'startMode': 'otro'},
    ]) {
      expect(
        () => RoundAuthorization.fromJson({...valid, ...change}),
        throwsFormatException,
      );
    }
  });
  test('Archivar conserva el historial y el acumulado sin duplicarlo', () {
    final old = RoundRehearsal(
      bets: [bet('0', 100), bet('1', 200)],
      kickoffs: {},
      pcRequestId: 'old',
    );
    final archived = old.archiveCurrent(now);
    final next = RoundRehearsal(
      bets: [],
      kickoffs: {},
      archives: archived,
      carriedSpentCents: old.totalSpentCents,
    );
    expect(next.totalSpentCents, 300);
    expect(next.archives.single.bets.length, 2);
    final saved = ArchivedRoundSession.fromJson(archived.single.toJson());
    expect(saved.spentCents, 300);
    expect(saved.requestId, 'old');
    final duplicate = RoundRehearsal(
      bets: old.bets,
      kickoffs: {},
      pcRequestId: 'old',
      archives: archived,
    );
    expect(duplicate.archiveCurrent(now).length, 1);
    final second = RoundRehearsal(
      bets: [bet('2', 100)],
      kickoffs: {},
      archives: archived,
      carriedSpentCents: 300,
    );
    expect(second.totalSpentCents, 400);
    final third = RoundRehearsal(
      bets: [],
      kickoffs: {},
      archives: second.archiveCurrent(now),
      carriedSpentCents: 400,
    );
    expect(third.totalSpentCents, 400);
  });
  test('Recuperar solo el contador del servidor no borra el acumulado', () {
    final recovered = RoundRehearsal(
      bets: [bet('2', 100)],
      kickoffs: {},
      carriedSpentCents: 700,
    );
    expect(recovered.totalSpentCents, 800);
    final restarted = RoundRehearsal(
      bets: [],
      kickoffs: {},
      carriedSpentCents: 800,
      archives: recovered.archiveCurrent(now),
    );
    expect(restarted.totalSpentCents, 800);
  });
}
