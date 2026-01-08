// lib/models/bet_detail.dart

class BetDetail {
  final String id;
  final bool acierto;
  final double cuota;
  final double cantidad;
  final DateTime fechaApuesta;
  final int jornada;
  final String local;
  final String visitante;

  BetDetail({
    required this.id,
    required this.acierto,
    required this.cuota,
    required this.cantidad,
    required this.fechaApuesta,
    required this.jornada,
    required this.local,
    required this.visitante,
  });
}
