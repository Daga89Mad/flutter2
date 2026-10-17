/// TheSportsDB publica strTimestamp/strTime en UTC.
DateTime? sportsDbKickoff(Map<dynamic, dynamic> event) {
  final stamp = '${event['strTimestamp'] ?? ''}'.trim();
  if (stamp.isNotEmpty) {
    final zoned = RegExp(
      r'(Z|[+-]\d{2}:?\d{2})$',
      caseSensitive: false,
    ).hasMatch(stamp);
    final parsed = DateTime.tryParse(zoned ? stamp : '${stamp}Z')?.toUtc();
    if (parsed != null) return parsed;
  }
  final date = '${event['dateEvent'] ?? ''}'.trim();
  final time = '${event['strTime'] ?? ''}'.trim();
  if (date.isEmpty || time.isEmpty) return null;
  return DateTime.tryParse('${date}T${time}Z')?.toUtc();
}

bool sportsDbFinished(Map<dynamic, dynamic> event) => const [
  'ft',
  'match finished',
  'full time',
  'finalizado',
].contains('${event['strStatus'] ?? ''}'.trim().toLowerCase());
