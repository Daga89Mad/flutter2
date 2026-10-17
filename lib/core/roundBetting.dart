/// Motor de preparación. No tiene acceso a dinero, Firestore ni a Betfair.
class RoundFixture {
  final String id;
  final String home;
  final String away;
  final DateTime? kickoff;
  final bool finished;
  final int? homeGoals;
  final int? awayGoals;
  final bool unavailable;

  const RoundFixture({
    required this.id,
    required this.home,
    required this.away,
    this.kickoff,
    this.finished = false,
    this.homeGoals,
    this.awayGoals,
    this.unavailable = false,
  });

  bool get hasResult => finished && homeGoals != null && awayGoals != null;
  bool get draw => hasResult && homeGoals == awayGoals;
  String get label => '$home — $away';

  RoundFixture withKickoff(DateTime value) => RoundFixture(
    id: id,
    home: home,
    away: away,
    kickoff: value,
    finished: finished,
    homeGoals: homeGoals,
    awayGoals: awayGoals,
    unavailable: unavailable,
  );
}

class RehearsalBet {
  final String matchId;
  final String label;
  final int cents;
  final double odds;
  final DateTime approvedAt;

  const RehearsalBet({
    required this.matchId,
    required this.label,
    required this.cents,
    required this.odds,
    required this.approvedAt,
  });

  Map<String, dynamic> toJson() => {
    'matchId': matchId,
    'label': label,
    'cents': cents,
    'odds': odds,
    'approvedAt': approvedAt.toUtc().toIso8601String(),
    'mode': 'simulation',
  };

  factory RehearsalBet.fromJson(Map<String, dynamic> data) {
    final cents = data['cents'] as int;
    final odds = (data['odds'] as num).toDouble();
    final validStakes = List.generate(9, (i) => 100 * (1 << i));
    if (data['mode'] != 'simulation' ||
        !validStakes.contains(cents) ||
        !odds.isFinite ||
        odds < RoundBetting.minimumOdds ||
        (data['matchId'] as String).isEmpty) {
      throw const FormatException('Registro de simulación no válido.');
    }
    return RehearsalBet(
      matchId: data['matchId'] as String,
      label: data['label'] as String,
      cents: cents,
      odds: odds,
      approvedAt: DateTime.parse(data['approvedAt'] as String),
    );
  }
}

class RoundPlan {
  final String message;
  final List<RoundFixture> candidates;
  final int cents;
  final bool stopped;
  const RoundPlan(
    this.message, {
    this.candidates = const [],
    this.cents = 100,
    this.stopped = false,
  });
  bool get canPrepare => candidates.isNotEmpty;
}

class RoundBetting {
  static const minimumOdds = 2.8;
  static const maximumCents = 25600;

  static RoundPlan plan({
    required List<RoundFixture> fixtures,
    required List<RehearsalBet> bets,
    required DateTime now,
  }) {
    if (fixtures.isEmpty) return const RoundPlan('No hay partidos cargados.');
    if (fixtures.any((m) => m.draw)) {
      return const RoundPlan(
        'Jornada detenida: ya hay un empate final.',
        stopped: true,
      );
    }
    final byId = {for (final m in fixtures) m.id: m};
    final seen = <String>{};
    var cents = 100;
    for (final bet in bets) {
      final match = byId[bet.matchId];
      if (!seen.add(bet.matchId) || match == null || bet.cents != cents) {
        return const RoundPlan(
          'El historial no coincide con la jornada. Revisa los datos.',
        );
      }
      if (!match.hasResult) {
        return const RoundPlan(
          'Esperando el resultado final de la apuesta simulada.',
        );
      }
      cents *= 2;
    }
    if (cents > maximumCents) {
      return const RoundPlan(
        'Límite de 256 € alcanzado. La próxima jornada empieza en 1 €.',
        stopped: true,
      );
    }
    final remaining = fixtures
        .where((m) => !m.hasResult && !m.unavailable)
        .toList();
    if (remaining.isEmpty)
      return const RoundPlan('Jornada terminada.', stopped: true);
    if (remaining.any((m) => m.kickoff == null)) {
      return const RoundPlan(
        'Completa los horarios de todos los partidos pendientes.',
      );
    }
    if (remaining.any((m) => !m.kickoff!.isAfter(now))) {
      return const RoundPlan(
        'Hay partidos iniciados sin resultado final confirmado. Actualiza resultados.',
      );
    }
    remaining.sort((a, b) {
      final comparison = a.kickoff!.compareTo(b.kickoff!);
      return comparison != 0 ? comparison : a.id.compareTo(b.id);
    });
    final end = remaining.first.kickoff!.add(const Duration(minutes: 120));
    final candidates = remaining
        .where((m) => m.kickoff!.isBefore(end))
        .toList();
    return RoundPlan(
      candidates.length > 1
          ? 'Hay horarios que se solapan. Elige un solo partido antes de confirmar.'
          : 'Próximo partido disponible.',
      candidates: candidates,
      cents: cents,
    );
  }
}
