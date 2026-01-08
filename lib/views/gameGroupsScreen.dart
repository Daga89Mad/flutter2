// lib/screens/game_groups_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:plantillalogin/views/BetListScreen.dart';
import 'package:plantillalogin/views/betScreen.dart';
import 'package:plantillalogin/views/transferScreen.dart';

import '../core/firebaseCrudService.dart';
import '../models/group.dart';
import '../models/group_member.dart';

class GameGroupsScreen extends StatefulWidget {
  const GameGroupsScreen({Key? key}) : super(key: key);

  @override
  _GameGroupsScreenState createState() => _GameGroupsScreenState();
}

class _GameGroupsScreenState extends State<GameGroupsScreen> {
  final _service = FirebaseCrudService();

  late final Future<List<Group>> _groupsFuture;
  Future<List<GroupMember>>? _membersFuture;
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _groupsFuture = _service.getUserGroups(uid);
  }

  Future<void> _goToBetScreen() async {
    if (_selectedGroupId == null) return;
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BetScreen(groupId: _selectedGroupId!, uid: currentUid),
      ),
    );

    setState(() {
      _membersFuture = _service.getGroupMembersWithStats(_selectedGroupId!);
    });
  }

  Future<void> _goToMyBets() async {
    if (_selectedGroupId == null) return;
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            BetListScreen(groupId: _selectedGroupId!, uid: currentUid),
      ),
    );

    setState(() {
      _membersFuture = _service.getGroupMembersWithStats(_selectedGroupId!);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grupos de Juego')),
      body: FutureBuilder<List<Group>>(
        future: _groupsFuture,
        builder: (ctx, snapGroups) {
          if (snapGroups.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapGroups.hasError) {
            return Center(
              child: Text('Error cargando grupos:\n${snapGroups.error}'),
            );
          }

          final groups = snapGroups.data!;
          if (groups.isEmpty) {
            return const Center(child: Text('No perteneces a ningún grupo'));
          }

          // Inicializamos selección y miembros
          _selectedGroupId ??= groups.first.id;
          _membersFuture ??= _service.getGroupMembersWithStats(
            _selectedGroupId!,
          );

          return Column(
            children: [
              // Dropdown de selección de grupo
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 160,
                      child: ElevatedButton.icon(
                        onPressed: _selectedGroupId == null
                            ? null
                            : _goToBetScreen,
                        icon: const Icon(Icons.add),
                        label: const Text('Realizar apuesta'),
                      ),
                    ),
                    // Importa el modelo correcto arriba del archivo
                    // Dentro del widget:
                    SizedBox(
                      width: 160,
                      child: ElevatedButton.icon(
                        onPressed: _selectedGroupId == null
                            ? null
                            : () async {
                                // Mostrar indicador de carga
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );

                                try {
                                  final currentUid =
                                      FirebaseAuth.instance.currentUser!.uid;
                                  final List<GroupMember> membersOfGroup =
                                      await _service.getGroupMembersWithStats(
                                        _selectedGroupId!,
                                      );

                                  // Cerrar el diálogo de carga antes de navegar
                                  if (Navigator.canPop(context))
                                    Navigator.of(context).pop();

                                  // Navegar y esperar resultado al volver
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TransferScreen(
                                        members: membersOfGroup,
                                        groupId: _selectedGroupId!,
                                        senderUid: currentUid,
                                      ),
                                    ),
                                  );

                                  // Si quieres refrescar la lista de miembros al volver (recomendado)
                                  setState(() {
                                    _membersFuture = _service
                                        .getGroupMembersWithStats(
                                          _selectedGroupId!,
                                        );
                                  });

                                  // Opcional: manejar el resultado devuelto por TransferScreen
                                  if (result != null &&
                                      result is Map<String, dynamic>) {
                                    debugPrint(
                                      'Traspaso realizado: ${result['amount']} a ${result['receiverId']}',
                                    );
                                  }
                                } catch (e) {
                                  // Aseguramos cerrar el diálogo si hubo error
                                  if (Navigator.canPop(context))
                                    Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error cargando miembros: $e',
                                      ),
                                    ),
                                  );
                                }
                              },

                        icon: const Icon(Icons.add),
                        label: const Text('Realizar Traspaso'),
                      ),
                    ),

                    SizedBox(
                      width: 160,
                      child: ElevatedButton.icon(
                        onPressed: _selectedGroupId == null
                            ? null
                            : _goToMyBets,
                        icon: const Icon(Icons.list),
                        label: const Text('Ver mis apuestas'),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: ElevatedButton.icon(
                        onPressed: _selectedGroupId == null
                            ? null
                            : _goToMyBets,
                        icon: const Icon(Icons.list),
                        label: const Text('Ver Traspasos'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Totalizadores + listado de miembros
              Expanded(
                child: FutureBuilder<List<GroupMember>>(
                  future: _membersFuture,
                  builder: (ctx2, snapMembers) {
                    if (snapMembers.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapMembers.hasError) {
                      return Center(
                        child: Text(
                          'Error cargando miembros:\n${snapMembers.error}',
                        ),
                      );
                    }

                    final members = snapMembers.data!;
                    if (members.isEmpty) {
                      return const Center(
                        child: Text('Este grupo no tiene miembros'),
                      );
                    }

                    // Cálculo de totales de todo el grupo
                    final totalApostado = members.fold<double>(
                      0.0,
                      (sum, m) => sum + m.totalPerdidas,
                    );
                    final totalGanado = members.fold<double>(
                      0.0,
                      (sum, m) => sum + m.totalGanancias,
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Fila de totales
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Apostado: ${totalApostado.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Total Ganado: ${totalGanado.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Listado de miembros
                        Expanded(
                          child: ListView.builder(
                            itemCount: members.length,
                            itemBuilder: (ctx3, i) {
                              final m = members[i];
                              final beneficio =
                                  (m.totalGanancias - m.totalPerdidas) +
                                  m.traspasosRecibidos -
                                  m.traspasosEnviados;
                              // Asegúrate de que tu modelo GroupMember tenga
                              // un campo `capitalInicial`
                              final capitalIni = m.capitalInicial;
                              final tRecibido = m.traspasosRecibidos;
                              final tEnviado = m.traspasosEnviados;
                              m.totalGanancias - m.totalPerdidas;
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    child: Text(
                                      m.alias.isNotEmpty
                                          ? m.alias[0].toUpperCase()
                                          : '?',
                                    ),
                                  ),
                                  title: Text(m.alias),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      // Capital inicial
                                      Text(
                                        'Capital inicial: ${capitalIni.toStringAsFixed(2)}',
                                      ),
                                      // Ganancias y apostado
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Ganado: ${m.totalGanancias.toStringAsFixed(2)}',
                                          ),
                                          Text(
                                            'Apostado: ${m.totalPerdidas.toStringAsFixed(2)}',
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'T.Enviado: -${tEnviado.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            'T.recibido: +${tRecibido.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          //const SizedBox(height: 4),
                                          // Beneficio neto
                                          Text(
                                            'Beneficio: ${beneficio.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: beneficio >= 0
                                                  ? Colors.green
                                                  : Colors.red,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),

                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => BetListScreen(
                                          groupId: _selectedGroupId!,
                                          uid: m.uid,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
