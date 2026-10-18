import 'roundBetting.dart';
import 'roundAuthorization.dart';

class ArchivedRoundSession {
  final List<RehearsalBet> bets;
  final String? requestId;
  final DateTime endedAt;
  const ArchivedRoundSession({
    required this.bets,
    required this.endedAt,
    this.requestId,
  });
  int get spentCents => bets.fold<int>(0, (sum, b) => sum + b.cents);
  Map<String, dynamic> toJson() => {
    'bets': bets.map((b) => b.toJson()).toList(),
    'requestId': requestId,
    'endedAt': endedAt.toUtc().toIso8601String(),
  };
  factory ArchivedRoundSession.fromJson(Map<String, dynamic> data) =>
      ArchivedRoundSession(
        bets: (data['bets'] as List)
            .map(
              (b) => RehearsalBet.fromJson(Map<String, dynamic>.from(b as Map)),
            )
            .toList(),
        requestId: data['requestId'] as String?,
        endedAt: DateTime.parse(data['endedAt'] as String),
      );
}

class RoundRehearsal {
  final List<RehearsalBet> bets;
  final Map<String, DateTime> kickoffs;
  final RoundAuthorization? authorization;
  final String? pcRequestId;
  final List<ArchivedRoundSession> archives;
  final int carriedSpentCents;
  RoundRehearsal({
    required this.bets,
    required this.kickoffs,
    this.authorization,
    this.pcRequestId,
    this.archives = const [],
    this.carriedSpentCents = 0,
  });
  int get archivedSpentCents {
    final listed = archives.fold<int>(0, (sum, a) => sum + a.spentCents);
    return listed > carriedSpentCents ? listed : carriedSpentCents;
  }

  int get totalSpentCents =>
      archivedSpentCents + bets.fold<int>(0, (sum, b) => sum + b.cents);
  List<ArchivedRoundSession> archiveCurrent(DateTime now) => [
    ...archives,
    if ((bets.isNotEmpty || pcRequestId != null || authorization != null) &&
        (pcRequestId == null ||
            !archives.any((a) => a.requestId == pcRequestId)))
      ArchivedRoundSession(
        bets: List.unmodifiable(bets),
        requestId: pcRequestId,
        endedAt: now,
      ),
  ];
}
