// lib/models/last_bet_team.dart

/// Un equipo de uno de los últimos partidos apostados, junto con la jornada
/// y la cantidad de esa apuesta. Se usa en el desplegable de la apuesta
/// automática: un mismo equipo puede aparecer varias veces, diferenciado
/// por la jornada (J1, J2, ...).
class LastBetTeam {
  final String team; // Equipo (local o visitante del partido apostado)
  final String league; // Liga en la que se apostó
  final String temporada; // Temporada de la apuesta (p.ej. 2025-2026)
  final int jornada; // Jornada de la apuesta
  final double amount; // Cantidad apostada en esa jornada
  final String matchId; // Id del partido original

  LastBetTeam({
    required this.team,
    required this.league,
    required this.temporada,
    required this.jornada,
    required this.amount,
    required this.matchId,
  });

  /// Texto del desplegable: "Equipo A J3"
  String get displayName => '$team J$jornada';

  /// Clave para eliminar duplicados exactos (mismo equipo, liga y jornada)
  String get key => '$league|$temporada|$team|$jornada';
}
