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
