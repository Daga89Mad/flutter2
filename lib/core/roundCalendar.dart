import 'sportsDbFixture.dart';

/// Calendario de LaLiga recibido del proveedor, sin dependencias de Flutter.
class RoundCalendarEntry {
  final String providerId;
  final String home;
  final String away;
  final DateTime? kickoff;
  final String status;
  final bool finished;
  final String homeGoals;
  final String awayGoals;

  const RoundCalendarEntry({
    required this.providerId,
    required this.home,
    required this.away,
    required this.kickoff,
    required this.status,
    required this.finished,
    required this.homeGoals,
    required this.awayGoals,
  });

  static String teamKey(String home, String away) {
    String normalized(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return '${normalized(home)}\u0000${normalized(away)}';
  }

  String get key => teamKey(home, away);

  static List<RoundCalendarEntry> parse(
    Object? response, {
    required String season,
    required int round,
  }) {
    if (!RegExp(r'^\d{4}-\d{4}$').hasMatch(season) || round < 1 || round > 38) {
      throw const FormatException('Temporada o jornada no válida.');
    }
    final years = season.split('-').map(int.parse).toList();
    if (years[1] != years[0] + 1)
      throw const FormatException('Temporada no válida.');
    if (response is! Map ||
        response['events'] is! List ||
        (response['events'] as List).length != 10) {
      throw const FormatException(
        'El proveedor todavía no devuelve los diez partidos de esta jornada.',
      );
    }
    String value(Map event, String key) => '${event[key] ?? ''}'.trim();
    final entries = <RoundCalendarEntry>[];
    final ids = <String>{};
    final teams = <String>{};
    for (final raw in response['events'] as List) {
      if (raw is! Map)
        throw const FormatException('Partido del proveedor no válido.');
      final id = value(raw, 'idEvent');
      final home = value(raw, 'strHomeTeam');
      final away = value(raw, 'strAwayTeam');
      if (!RegExp(r'^\d+$').hasMatch(id) ||
          home.isEmpty ||
          away.isEmpty ||
          !ids.add(id) ||
          !teams.add(teamKey(home, away))) {
        throw const FormatException(
          'El calendario contiene partidos incompletos o duplicados.',
        );
      }
      if ((value(raw, 'idLeague').isNotEmpty &&
              value(raw, 'idLeague') != '4335') ||
          (value(raw, 'strSeason').isNotEmpty &&
              value(raw, 'strSeason') != season) ||
          (value(raw, 'intRound').isNotEmpty &&
              int.tryParse(value(raw, 'intRound')) != round)) {
        throw const FormatException(
          'El calendario recibido pertenece a otra liga, temporada o jornada.',
        );
      }
      final hs = value(raw, 'intHomeScore');
      final awayScore = value(raw, 'intAwayScore');
      final finalScore =
          sportsDbFinished(raw) &&
          RegExp(r'^\d+$').hasMatch(hs) &&
          RegExp(r'^\d+$').hasMatch(awayScore);
      entries.add(
        RoundCalendarEntry(
          providerId: id,
          home: home,
          away: away,
          kickoff: sportsDbKickoff(raw),
          status: value(raw, 'strStatus'),
          finished: finalScore,
          homeGoals: finalScore ? hs : '',
          awayGoals: finalScore ? awayScore : '',
        ),
      );
    }
    return entries;
  }
}

class RoundCalendarWrite {
  final String id;
  final RoundCalendarEntry entry;
  const RoundCalendarWrite(this.id, this.entry);
}

/// Conserva IDs existentes: los OK y las apuestas se refieren a esos documentos.
/// Los documentos nuevos tienen un ID estable para evitar duplicados entre móviles.
List<RoundCalendarWrite> planCalendarWrites(
  List<RoundCalendarEntry> entries,
  Map<String, Map<String, dynamic>> existing,
) {
  if (entries.length != 10 ||
      entries.map((e) => e.key).toSet().length != 10 ||
      entries.map((e) => e.providerId).toSet().length != 10)
    throw const FormatException('Calendario incompleto o duplicado.');
  final allowed = entries.map((e) => e.key).toSet();
  final byTeams = <String, String>{};
  for (final doc in existing.entries) {
    final key = RoundCalendarEntry.teamKey(
      '${doc.value['Local'] ?? ''}',
      '${doc.value['Visitante'] ?? ''}',
    );
    if (!allowed.contains(key) || byTeams.containsKey(key)) {
      throw const FormatException(
        'Los partidos guardados no coinciden con el calendario o están duplicados. Revisa los datos de esta jornada.',
      );
    }
    byTeams[key] = doc.key;
  }
  final usedIds = <String>{};
  return entries.map((e) {
    final id = byTeams[e.key] ?? 'tsdb_${e.providerId}';
    if (!usedIds.add(id))
      throw const FormatException(
        'Hay identificadores de partidos en conflicto.',
      );
    final old = existing[id];
    if (old != null) {
      final priorStatus = '${old['Estado'] ?? ''}'.trim().toLowerCase();
      final priorFinal =
          old['Finalizado'] == true ||
          const [
            'ft',
            'match finished',
            'full time',
            'finalizado',
          ].contains(priorStatus);
      final hasGoals =
          int.tryParse('${old['GolesLocal'] ?? ''}') != null &&
          int.tryParse('${old['GolesVisitante'] ?? ''}') != null;
      if (priorFinal && hasGoals && !e.finished) {
        throw const FormatException(
          'El proveedor aún no confirma un resultado final ya guardado. Intenta actualizar de nuevo.',
        );
      }
    }
    return RoundCalendarWrite(id, e);
  }).toList();
}
