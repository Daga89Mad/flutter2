import 'dart:convert';

import 'roundBetting.dart';

/// Consentimiento de ensayo para una sola jornada; no es una orden de dinero real.
class RoundAuthorization {
  final bool fromNow;
  final Set<String> baselineFinishedIds;
  final int previousSpentCents;
  final String scope;
  final String schedule;
  final Set<String> selectedIds;
  final int budgetCents;
  final double rehearsalOdds;
  final DateTime approvedAt;
  final DateTime expiresAt;

  RoundAuthorization._({
    required this.scope,
    this.fromNow = false,
    Set<String> baselineFinishedIds = const {},
    this.previousSpentCents = 0,
    required this.schedule,
    required Set<String> selectedIds,
    required this.budgetCents,
    required this.rehearsalOdds,
    required this.approvedAt,
    required this.expiresAt,
  }) : selectedIds = Set.unmodifiable(selectedIds),
       baselineFinishedIds = Set.unmodifiable(baselineFinishedIds);

  static String fingerprint(List<RoundFixture> fixtures) {
    final sorted = [...fixtures]..sort((a, b) => a.id.compareTo(b.id));
    return jsonEncode(
      sorted
          .map(
            (m) => [
              m.id,
              m.home,
              m.away,
              m.kickoff?.toUtc().toIso8601String(),
              m.unavailable,
            ],
          )
          .toList(),
    );
  }

  /// Componentes de horarios solapados: el usuario elige uno por grupo.
  /// Los 120 minutos agrupan horarios, nunca certifican un resultado final.
  static List<List<RoundFixture>> groups(
    List<RoundFixture> fixtures,
    DateTime now,
  ) {
    final remaining =
        fixtures
            .where(
              (m) =>
                  !m.hasResult &&
                  !m.unavailable &&
                  m.kickoff != null &&
                  m.kickoff!.isAfter(now),
            )
            .toList()
          ..sort((a, b) {
            final order = a.kickoff!.compareTo(b.kickoff!);
            return order == 0 ? a.id.compareTo(b.id) : order;
          });
    final result = <List<RoundFixture>>[];
    DateTime? end;
    for (final fixture in remaining) {
      if (end == null || !fixture.kickoff!.isBefore(end)) {
        result.add([]);
      }
      result.last.add(fixture);
      end = fixture.kickoff!.add(const Duration(minutes: 120));
    }
    return result;
  }

  factory RoundAuthorization.issue({
    required String scope,
    required List<RoundFixture> fixtures,
    required Set<String> selectedIds,
    required int budgetCents,
    required double rehearsalOdds,
    required DateTime now,
    bool fromNow = false,
    int previousSpentCents = 0,
  }) {
    if (fixtures.length != 10 ||
        fixtures.map((m) => m.id).toSet().length != 10) {
      throw StateError('Carga los diez partidos de LaLiga antes de autorizar.');
    }
    if (!fromNow && fixtures.any((m) => m.draw))
      throw StateError('La jornada ya tiene un empate final.');
    final baseline = fromNow
        ? fixtures.where((m) => m.hasResult).map((m) => m.id).toSet()
        : <String>{};
    if (fromNow &&
        fixtures.any(
          (m) =>
              baseline.contains(m.id) &&
              (m.kickoff == null || m.kickoff!.isAfter(now)),
        )) {
      throw StateError(
        'Un resultado anterior tiene un horario incoherente. Actualiza el calendario.',
      );
    }
    if (previousSpentCents < 0 ||
        previousSpentCents > 51000 ||
        (!fromNow && previousSpentCents != 0) ||
        previousSpentCents + 100 > budgetCents) {
      throw StateError(
        'El presupuesto de la jornada debe cubrir lo ya simulado y el nuevo ensayo de 1 €.',
      );
    }
    final remaining = fixtures
        .where((m) => !m.hasResult && !m.unavailable)
        .toList();
    if (remaining.isEmpty ||
        remaining.any((m) => m.kickoff == null || !m.kickoff!.isAfter(now))) {
      throw StateError(
        'Completa horarios y espera los resultados de los partidos iniciados.',
      );
    }
    if (budgetCents < 100 ||
        budgetCents > 51100 ||
        !rehearsalOdds.isFinite ||
        rehearsalOdds < RoundBetting.minimumOdds) {
      throw StateError(
        'El presupuesto debe ser de 1 a 511 € y la cuota de ensayo al menos 2,80.',
      );
    }
    final slots = groups(fixtures, now);
    final allowed = slots.expand((g) => g).map((m) => m.id).toSet();
    if (selectedIds.isEmpty ||
        !allowed.containsAll(selectedIds) ||
        slots.any(
          (g) => g.where((m) => selectedIds.contains(m.id)).length != 1,
        )) {
      throw StateError(
        'Elige exactamente un partido en cada grupo de horarios.',
      );
    }
    final last = remaining
        .map((m) => m.kickoff!)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return RoundAuthorization._(
      scope: scope,
      fromNow: fromNow,
      baselineFinishedIds: baseline,
      previousSpentCents: previousSpentCents,
      schedule: fingerprint(fixtures),
      selectedIds: selectedIds,
      budgetCents: budgetCents,
      rehearsalOdds: rehearsalOdds,
      approvedAt: now,
      expiresAt: last.add(const Duration(minutes: 1)),
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': fromNow ? 'round-simulation-v2' : 'round-simulation-v1',
    if (fromNow) ...{
      'startMode': 'from-now',
      'baselineFinishedIds': baselineFinishedIds.toList(),
      'previousSpentCents': previousSpentCents,
    },
    'scope': scope,
    'schedule': schedule,
    'selectedIds': selectedIds.toList(),
    'budgetCents': budgetCents,
    'rehearsalOdds': rehearsalOdds,
    'approvedAt': approvedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory RoundAuthorization.fromJson(Map<String, dynamic> data) {
    final budget = data['budgetCents'] as int;
    final odds = (data['rehearsalOdds'] as num).toDouble();
    final ids = (data['selectedIds'] as List).cast<String>().toSet();
    final approved = DateTime.parse(data['approvedAt'] as String);
    final expires = DateTime.parse(data['expiresAt'] as String);
    final fromNow = data['mode'] == 'round-simulation-v2';
    final baselineList = fromNow
        ? (data['baselineFinishedIds'] as List).cast<String>()
        : <String>[];
    final baseline = baselineList.toSet();
    final previousSpent = fromNow ? data['previousSpentCents'] as int : 0;
    final rows = jsonDecode(data['schedule'] as String) as List;
    final allIds = rows.map((r) => (r as List).first as String).toSet();
    if ((data['mode'] != 'round-simulation-v1' && !fromNow) ||
        (!fromNow &&
            [
              'startMode',
              'baselineFinishedIds',
              'previousSpentCents',
            ].any(data.containsKey)) ||
        (fromNow &&
            (data['startMode'] != 'from-now' ||
                baseline.length != baselineList.length ||
                baseline.length > 9 ||
                !allIds.containsAll(baseline) ||
                baseline.intersection(ids).isNotEmpty ||
                previousSpent < 0 ||
                previousSpent > 51000 ||
                previousSpent + 100 > budget ||
                rows.any(
                  (r) =>
                      baseline.contains(r[0]) &&
                      (r[3] == null ||
                          DateTime.parse(r[3] as String).isAfter(approved)),
                ))) ||
        budget < 100 ||
        budget > 51100 ||
        !odds.isFinite ||
        odds < RoundBetting.minimumOdds ||
        ids.isEmpty ||
        !expires.isAfter(approved))
      throw const FormatException('Autorización de ensayo inválida.');
    return RoundAuthorization._(
      scope: data['scope'] as String,
      fromNow: fromNow,
      baselineFinishedIds: baseline,
      previousSpentCents: previousSpent,
      schedule: data['schedule'] as String,
      selectedIds: ids,
      budgetCents: budget,
      rehearsalOdds: odds,
      approvedAt: approved,
      expiresAt: expires,
    );
  }

  RoundPlan next({
    required String currentScope,
    required List<RoundFixture> fixtures,
    required List<RehearsalBet> bets,
    required DateTime now,
  }) {
    if (currentScope != scope ||
        now.isBefore(approvedAt) ||
        !now.isBefore(expiresAt)) {
      return const RoundPlan(
        'Autorización caducada o de otra jornada.',
        stopped: true,
      );
    }
    if (fingerprint(fixtures) != schedule) {
      return const RoundPlan(
        'Cambió el calendario. Revisa las elecciones y autoriza otra vez.',
        stopped: true,
      );
    }
    if (bets.any((b) => b.approvedAt.isAfter(now))) {
      return const RoundPlan('Revisa el reloj y el historial de simulación.');
    }
    if (baselineFinishedIds.any(
      (id) => !fixtures.any((m) => m.id == id && m.hasResult),
    )) {
      return const RoundPlan(
        'Un resultado previo dejó de estar confirmado. Actualiza y revisa el ensayo.',
        stopped: true,
      );
    }
    if (bets.any((b) => baselineFinishedIds.contains(b.matchId))) {
      return const RoundPlan(
        'El historial incluye un partido anterior al nuevo OK.',
        stopped: true,
      );
    }
    final plan = RoundBetting.plan(
      fixtures: fixtures
          .where((m) => !baselineFinishedIds.contains(m.id))
          .toList(),
      bets: bets,
      now: now,
    );
    if (!plan.canPrepare) return plan;
    final spent = bets.fold<int>(0, (sum, b) => sum + b.cents);
    if (previousSpentCents + spent + plan.cents > budgetCents) {
      return const RoundPlan(
        'Presupuesto de jornada alcanzado. No se aumenta automáticamente.',
        stopped: true,
      );
    }
    final chosen = plan.candidates
        .where((m) => selectedIds.contains(m.id))
        .toList();
    if (chosen.length != 1)
      return const RoundPlan(
        'Esperando el siguiente partido elegido y sus resultados previos.',
      );
    if (chosen.single.kickoff!.difference(now) > const Duration(minutes: 5)) {
      return RoundPlan(
        'Jornada autorizada. Esperando los cinco minutos previos al partido.',
        cents: plan.cents,
      );
    }
    return RoundPlan(
      'Lista para simular dentro de la autorización de jornada.',
      candidates: chosen,
      cents: plan.cents,
    );
  }
}
