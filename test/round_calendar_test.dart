import 'package:flutter_test/flutter_test.dart';
import 'package:plantillalogin/core/roundCalendar.dart';

void main() {
  Map<String, dynamic> response() => {
    'events': List.generate(
      10,
      (i) => <String, dynamic>{
        'idEvent': '${100 + i}',
        'idLeague': '4335',
        'strSeason': '2026-2027',
        'intRound': '8',
        'strHomeTeam': 'Local $i',
        'strAwayTeam': 'Visitante $i',
        'strTimestamp': '2026-10-${18 + i}T16:00:00Z',
        'strStatus': 'Not Started',
        'intHomeScore': null,
        'intAwayScore': null,
      },
    ),
  };
  List<RoundCalendarEntry> parse(Map<String, dynamic> raw) =>
      RoundCalendarEntry.parse(raw, season: '2026-2027', round: 8);
  Map<String, dynamic> event(Map<String, dynamic> raw, int i) =>
      (raw['events'] as List)[i] as Map<String, dynamic>;

  test('Obtiene los diez horarios sin entrada manual', () {
    final entries = parse(response());
    expect(entries.length, 10);
    expect(entries.first.kickoff, DateTime.utc(2026, 10, 18, 16));
    expect(entries.first.finished, isFalse);
  });
  test('Interpreta offsets y hora UTC separada', () {
    final raw = response();
    event(raw, 0)['strTimestamp'] = '2026-10-18T18:00:00+02:00';
    event(raw, 1).remove('strTimestamp');
    event(raw, 1).addAll({'dateEvent': '2026-10-19', 'strTime': '16:00:00'});
    expect(parse(raw)[0].kickoff, DateTime.utc(2026, 10, 18, 16));
    expect(parse(raw)[1].kickoff, DateTime.utc(2026, 10, 19, 16));
  });
  test('Horario no publicado permanece desconocido', () {
    final raw = response();
    event(raw, 0).remove('strTimestamp');
    expect(parse(raw).first.kickoff, isNull);
  });
  test('Rechaza calendario incompleto y proveedor sin eventos', () {
    final raw = response();
    (raw['events'] as List).removeLast();
    expect(() => parse(raw), throwsFormatException);
    expect(() => parse({'events': null}), throwsFormatException);
  });
  test('Rechaza otra liga, temporada o jornada', () {
    for (final field in ['idLeague', 'strSeason', 'intRound']) {
      final raw = response();
      event(raw, 0)[field] = {
        'idLeague': '4332',
        'strSeason': '2025-2026',
        'intRound': '9',
      }[field];
      expect(() => parse(raw), throwsFormatException);
    }
  });
  test('Rechaza identificadores y parejas duplicados o vacíos', () {
    for (final field in ['idEvent', 'strHomeTeam']) {
      final raw = response();
      event(raw, 0)[field] = '';
      expect(() => parse(raw), throwsFormatException);
    }
    final sameId = response();
    event(sameId, 1)['idEvent'] = event(sameId, 0)['idEvent'];
    expect(() => parse(sameId), throwsFormatException);
    final sameTeams = response();
    event(
      sameTeams,
      1,
    ).addAll({'strHomeTeam': ' LOCAL 0 ', 'strAwayTeam': 'Visitante 0'});
    expect(() => parse(sameTeams), throwsFormatException);
  });
  test('No publica 0-0 en directo como resultado final', () {
    final raw = response();
    event(
      raw,
      0,
    ).addAll({'strStatus': '1H', 'intHomeScore': '0', 'intAwayScore': '0'});
    final entry = parse(raw).first;
    expect(entry.finished, isFalse);
    expect(entry.homeGoals, '');
    expect(entry.awayGoals, '');
  });
  test('Solo publica goles finales confirmados', () {
    final raw = response();
    event(
      raw,
      0,
    ).addAll({'strStatus': 'FT', 'intHomeScore': '1', 'intAwayScore': '1'});
    expect(parse(raw).first.finished, isTrue);
    expect(parse(raw).first.homeGoals, '1');
    event(raw, 0)['intAwayScore'] = null;
    expect(parse(raw).first.finished, isFalse);
  });
  test('IDs nuevos son estables al cargar desde varios móviles', () {
    final a = planCalendarWrites(parse(response()), {});
    final b = planCalendarWrites(parse(response()), {});
    expect(a.map((w) => w.id), b.map((w) => w.id));
    expect(a.first.id, 'tsdb_100');
  });
  test('Conserva los IDs anteriores y no crea duplicados', () {
    final existing = {
      'id-anterior': <String, dynamic>{
        'Local': 'Local 0',
        'Visitante': 'Visitante 0',
      },
    };
    final writes = planCalendarWrites(parse(response()), existing);
    expect(writes.first.id, 'id-anterior');
    expect(writes.map((w) => w.id).toSet().length, 10);
  });
  test('Se bloquea si hay partidos ajenos o duplicados guardados', () {
    final entries = parse(response());
    expect(
      () => planCalendarWrites(entries, {
        'otro': {'Local': 'X', 'Visitante': 'Y'},
      }),
      throwsFormatException,
    );
    expect(
      () => planCalendarWrites(entries, {
        'a': {'Local': 'Local 0', 'Visitante': 'Visitante 0'},
        'b': {'Local': 'Local 0', 'Visitante': 'Visitante 0'},
      }),
      throwsFormatException,
    );
  });
  test('No degrada un resultado final a pendiente', () {
    final existing = {
      'a': <String, dynamic>{
        'Local': 'Local 0',
        'Visitante': 'Visitante 0',
        'Finalizado': true,
        'GolesLocal': '1',
        'GolesVisitante': '0',
      },
    };
    expect(
      () => planCalendarWrites(parse(response()), existing),
      throwsFormatException,
    );
  });
  test('Un cambio de hora actualiza el mismo documento', () {
    final raw = response();
    event(raw, 0)['strTimestamp'] = '2026-10-18T20:00:00Z';
    final writes = planCalendarWrites(parse(raw), {
      'a': {'Local': 'Local 0', 'Visitante': 'Visitante 0'},
    });
    expect(writes.first.id, 'a');
    expect(writes.first.entry.kickoff, DateTime.utc(2026, 10, 18, 20));
  });
  test('Bloquea colisión de IDs existentes con IDs de proveedor', () {
    expect(
      () => planCalendarWrites(parse(response()), {
        'tsdb_101': {'Local': 'Local 0', 'Visitante': 'Visitante 0'},
      }),
      throwsFormatException,
    );
  });
}
