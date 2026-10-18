import 'dart:convert';

import 'roundRehearsal.dart';
export 'roundRehearsal.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:plantillalogin/core/roundBetting.dart';
import 'package:plantillalogin/core/roundAuthorization.dart';

/// Un registro local por usuario/temporada/jornada; nunca representa una orden real.
class RoundBettingStore {
  final SharedPreferences preferences;
  final String key;
  RoundBettingStore(this.preferences, String uid, String season, int round)
    : key = 'round-betting-simulation-v1/$uid/LaLiga/$season/$round';

  RoundRehearsal read() {
    final raw = preferences.getString(key);
    if (raw == null) return RoundRehearsal(bets: [], kickoffs: {});
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return RoundRehearsal(
      pcRequestId: data['pcRequestId'] as String?,
      carriedSpentCents: data['carriedSpentCents'] as int? ?? 0,
      archives: ((data['archives'] as List?) ?? [])
          .map(
            (a) => ArchivedRoundSession.fromJson(
              Map<String, dynamic>.from(a as Map),
            ),
          )
          .toList(),
      bets: (data['bets'] as List)
          .map(
            (b) => RehearsalBet.fromJson(Map<String, dynamic>.from(b as Map)),
          )
          .toList(),
      kickoffs: (data['kickoffs'] as Map<String, dynamic>).map(
        (id, value) => MapEntry(id, DateTime.parse(value as String)),
      ),
      authorization: data['authorization'] == null
          ? null
          : RoundAuthorization.fromJson(
              Map<String, dynamic>.from(data['authorization'] as Map),
            ),
    );
  }

  Future<void> save(RoundRehearsal rehearsal) async {
    final saved = await preferences.setString(
      key,
      jsonEncode({
        'bets': rehearsal.bets.map((b) => b.toJson()).toList(),
        'authorization': rehearsal.authorization?.toJson(),
        'pcRequestId': rehearsal.pcRequestId,
        'carriedSpentCents': rehearsal.carriedSpentCents,
        'archives': rehearsal.archives.map((a) => a.toJson()).toList(),
        'kickoffs': rehearsal.kickoffs.map(
          (id, time) => MapEntry(id, time.toUtc().toIso8601String()),
        ),
      }),
    );
    if (!saved) throw StateError('No se pudo guardar la simulación.');
  }
}
