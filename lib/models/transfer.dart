class Transfer {
  final String id;
  final DateTime fecha;
  final double cantidad;
  final String idReceptor;
  final String idEmisor;

  Transfer({
    required this.id,
    required this.fecha,
    required this.cantidad,
    required this.idReceptor,
    required this.idEmisor,
  });
}
