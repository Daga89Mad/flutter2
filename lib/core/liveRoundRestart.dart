/// Sólo una autorización terminada sin reservas puede reemplazarse desde la app.
/// Windows vuelve a comprobar archivo, recibos, CSV e historial de apuestas.
bool canReplaceUnusedLiveRound(
  Map<String, dynamic>? command,
  Map<String, dynamic>? state,
) {
  if (command == null || state == null) return false;
  final id = command['requestId'];
  final orders = state['orders'];
  return command['mode'] == 'live-round-128-v1' &&
      id is String &&
      RegExp(r'^[a-f0-9]{32}$').hasMatch(id) &&
      state['requestId'] == id &&
      state['fingerprint'] is String &&
      (state['fingerprint'] as String).isNotEmpty &&
      state['terminal'] == true &&
      state['reservedCount'] == 0 &&
      orders is List &&
      orders.isEmpty &&
      (state['spentCents'] ?? 0) == 0 &&
      const ['stopped', 'revoked', 'completed'].contains(state['status']);
}

/// La recuperación conserva las pérdidas; no habilita un reinicio desde 1 €.
bool canResumeReviewedLiveRound(
  Map<String, dynamic>? command,
  Map<String, dynamic>? state,
) {
  if (command == null || state == null) return false;
  final count = state['reservedCount'];
  final orders = state['orders'];
  if (command['mode'] != 'live-round-128-v1' ||
      state['requestId'] != command['requestId'] ||
      state['terminal'] != true ||
      state['status'] != 'review_reconciled' ||
      count is! int ||
      count < 1 ||
      count > 7 ||
      orders is! List ||
      orders.length != count ||
      state['spentCents'] != 100 * ((1 << count) - 1) ||
      state['fingerprint'] is! String ||
      !RegExp(r'^[A-F0-9]{64}$').hasMatch(state['fingerprint'] as String) ||
      state['evidence'] is! String ||
      !RegExp(r'^recovery:[A-F0-9]{64}$').hasMatch(state['evidence'] as String))
    return false;
  for (var i = 0; i < count; i++) {
    final order = orders[i];
    final cents = 100 << i;
    if (order is! Map ||
        order['status'] != 'SETTLED' ||
        order['cents'] != cents ||
        order['matchedCents'] != cents ||
        order['profitLossCents'] != -cents ||
        order['betId'] is! String ||
        (order['betId'] as String).isEmpty ||
        order['strategyId'] is! String ||
        (order['strategyId'] as String).isEmpty ||
        order['settledAt'] is! String ||
        order['odds'] is! num ||
        !(order['odds'] as num).isFinite ||
        (order['odds'] as num) < 2.8 ||
        (order['odds'] as num) > 20)
      return false;
  }
  return true;
}
