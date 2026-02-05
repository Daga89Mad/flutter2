// lib/models/group_member.dart

class GroupMember {
  final String uid;
  final String alias;
  final double capitalInicial;
  final double totalPerdidas;
  final double totalGanancias;
  final double traspasosRecibidos;
  final double traspasosEnviados;
  final double totalApostado; // nuevo: suma de stakes apostados

  GroupMember({
    required this.uid,
    required this.alias,
    required this.capitalInicial,
    required this.totalPerdidas,
    required this.totalGanancias,
    required this.traspasosRecibidos,
    required this.traspasosEnviados,
    required this.totalApostado,
  });

  /// Crea instancia a partir de Map de MiembrosGrupos y stats
  factory GroupMember.fromMaps({
    required String uid,
    required Map<String, dynamic> memberData,
    required double totalPerdidas,
    required double totalGanancias,
    required double traspasosRecibidos,
    required double traspasosEnviados,
    required double totalApostado, // nuevo parámetro
  }) {
    return GroupMember(
      uid: uid,
      alias: memberData['Alias'] as String? ?? '',
      capitalInicial: (memberData['CapitalInicial'] as num?)?.toDouble() ?? 0.0,
      totalPerdidas: totalPerdidas,
      totalGanancias: totalGanancias,
      traspasosRecibidos: traspasosRecibidos,
      traspasosEnviados: traspasosEnviados,
      totalApostado: totalApostado,
    );
  }
}
