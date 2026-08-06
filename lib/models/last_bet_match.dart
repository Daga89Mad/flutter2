// lib/models/last_bet_match.dart

class LastBetMatch {
  final String local; // Equipo local del partido apostado
  final String visitante; // Equipo visitante del partido apostado
  final String league; // Liga en la que se apostó
  final String temporada; // Temporada de la apuesta (p.ej. 2025-2026)
  final int jornada; // Jornada de la apuesta
  final double amount; // Cantidad apostada
  final String matchId; // Id del partido original

  LastBetMatch({
    required this.local,
    required this.visitante,
    required this.league,
    required this.temporada,
    required this.jornada,
    required this.amount,
    required this.matchId,
  });

  String get displayName => '$local vs $visitante';
}
