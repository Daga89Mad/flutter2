import 'dart:math' as math;

/// Modelo experimental: parámetros estimados en 2024/25, evaluación 2025/26.
/// No se debe usar para apostar sin validación adicional.
class DrawModelD {
  static const version = 'logistica-multivariable-v0';
  static double predict({
    double? pointsPerGameDifference,
    double? combinedVenueScoringAverage,
    required bool eitherTeamEightWithoutDraw,
  }) {
    final ppgAbsent = pointsPerGameDifference == null;
    final goalsAbsent = combinedVenueScoringAverage == null;
    final ppg = pointsPerGameDifference ?? 0.47017544;
    final goals = combinedVenueScoringAverage ?? 2.55555556;
    final streak = eitherTeamEightWithoutDraw ? 1.0 : 0.0;
    final z = -1.02435621
      - 0.29192078 * ((ppg - 0.54760333) / 0.37821043)
      - 0.08023905 * ((goals - 2.63135318) / 0.78600253)
      - 0.04684367 * ((streak - 0.13684211) / 0.34368058)
      + 0.17912062 * (((ppgAbsent ? 1.0 : 0.0) - 0.13157895) / 0.33803244)
      - 0.09603251 * (((goalsAbsent ? 1.0 : 0.0) - 0.13421053) / 0.34087837);
    return 1 / (1 + math.exp(-z));
  }
}
