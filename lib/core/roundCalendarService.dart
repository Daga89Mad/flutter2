import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import 'roundCalendar.dart';

/// Carga automática al abrir o actualizar la pantalla. No autoriza apuestas.
class RoundCalendarService {
  Future<int> sync({
    required CollectionReference<Map<String, dynamic>> matches,
    required String season,
    required int round,
    required bool Function() isCurrent,
  }) async {
    final uri = Uri.https(
      'www.thesportsdb.com',
      '/api/v1/json/123/eventsround.php',
      {'id': '4335', 'r': '$round', 's': season},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200)
      throw StateError(
        'No se pudo consultar el calendario (HTTP ${response.statusCode}).',
      );
    final entries = RoundCalendarEntry.parse(
      jsonDecode(response.body),
      season: season,
      round: round,
    );
    if (!isCurrent()) return 0;
    final snapshot = await matches.get(const GetOptions(source: Source.server));
    if (!isCurrent()) return 0;
    final writes = planCalendarWrites(entries, {
      for (final doc in snapshot.docs) doc.id: doc.data(),
    });
    final batch = matches.firestore.batch();
    for (final write in writes) {
      final e = write.entry;
      final home = int.tryParse(e.homeGoals);
      final away = int.tryParse(e.awayGoals);
      batch.set(matches.doc(write.id), {
        'Local': e.home,
        'Visitante': e.away,
        'Jornada': '$round',
        'Temporada': season,
        'Estado': e.status,
        'Finalizado': e.finished,
        'InicioUTC': e.kickoff == null ? null : Timestamp.fromDate(e.kickoff!),
        'GolesLocal': e.homeGoals,
        'GolesVisitante': e.awayGoals,
        'Empate': e.finished && home == away,
        'VictoriaLocal': e.finished && home! > away!,
        'VictoriaVisitante': e.finished && away! > home!,
      }, SetOptions(merge: true));
    }
    if (!isCurrent()) return 0;
    await batch.commit();
    return entries.where((e) => e.kickoff == null).length;
  }
}
