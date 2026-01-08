// lib/screens/transferListScreen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/group_member.dart';
import '../core/firebaseCrudService.dart';

class TransferRecord {
  final String id;
  final double amount;
  final Timestamp date;
  final String type; // 'enviada' | 'recibida'
  final String fromUid;
  final String toUid;
  final String memberOwnerUid;

  TransferRecord({
    required this.id,
    required this.amount,
    required this.date,
    required this.type,
    required this.fromUid,
    required this.toUid,
    required this.memberOwnerUid,
  });
}

class TransferListScreen extends StatefulWidget {
  final String groupId;
  final List<GroupMember>? members; // opcional: si se pasa, usamos alias

  const TransferListScreen({Key? key, required this.groupId, this.members})
    : super(key: key);

  @override
  State<TransferListScreen> createState() => _TransferListScreenState();
}

class _TransferListScreenState extends State<TransferListScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseCrudService _service = FirebaseCrudService();

  late Future<List<TransferRecord>> _transfersFuture;
  Map<String, String> _aliasMap = {}; // uid -> alias

  @override
  void initState() {
    super.initState();
    _transfersFuture = _initAndFetch();
  }

  Future<List<TransferRecord>> _initAndFetch() async {
    // Si nos pasan members, construimos el mapa de alias inmediatamente
    if (widget.members != null) {
      _aliasMap = {
        for (var m in widget.members!)
          m.uid: (m.alias.isNotEmpty ? m.alias : m.uid),
      };
    } else {
      // Si no se pasan, intentamos cargar miembros del servicio
      try {
        final members = await _service.getGroupMembersWithStats(widget.groupId);
        _aliasMap = {
          for (var m in members) m.uid: (m.alias.isNotEmpty ? m.alias : m.uid),
        };
      } catch (_) {
        _aliasMap = {};
      }
    }

    // Luego obtenemos todos los traspasos del grupo
    return _fetchAllTransfers();
  }

  Future<List<TransferRecord>> _fetchAllTransfers() async {
    final List<TransferRecord> combined = [];

    // Obtener la lista de miembros (documentos bajo Traspasos/{groupId}/Personas)
    final personsSnap = await _db
        .collection('Traspasos')
        .doc(widget.groupId)
        .collection('Personas')
        .get();

    if (personsSnap.docs.isEmpty) return combined;

    for (final personDoc in personsSnap.docs) {
      final memberUid = personDoc.id;

      final sentSnap = await personDoc.reference.collection('Enviadas').get();
      for (final d in sentSnap.docs) {
        final data = d.data();
        final amount = (data['Cantidad'] is num)
            ? (data['Cantidad'] as num).toDouble()
            : double.tryParse('${data['Cantidad']}') ?? 0.0;
        final date = (data['Fecha'] is Timestamp)
            ? data['Fecha'] as Timestamp
            : Timestamp.now();
        final idReceptor = data['IdReceptor']?.toString() ?? '';
        combined.add(
          TransferRecord(
            id: d.id,
            amount: amount,
            date: date,
            type: 'enviada',
            fromUid: memberUid,
            toUid: idReceptor,
            memberOwnerUid: memberUid,
          ),
        );
      }

      final recSnap = await personDoc.reference.collection('Recibidas').get();
      for (final d in recSnap.docs) {
        final data = d.data();
        final amount = (data['Cantidad'] is num)
            ? (data['Cantidad'] as num).toDouble()
            : double.tryParse('${data['Cantidad']}') ?? 0.0;
        final date = (data['Fecha'] is Timestamp)
            ? data['Fecha'] as Timestamp
            : Timestamp.now();
        final idEmisor = data['IdEmisor']?.toString() ?? '';
        combined.add(
          TransferRecord(
            id: d.id,
            amount: amount,
            date: date,
            type: 'recibida',
            fromUid: idEmisor,
            toUid: memberUid,
            memberOwnerUid: memberUid,
          ),
        );
      }
    }

    combined.sort((a, b) => b.date.compareTo(a.date));
    return combined;
  }

  String _aliasFor(String uid) {
    if (_aliasMap.containsKey(uid)) return _aliasMap[uid]!;
    // Si no tenemos alias en el mapa, devolvemos uid (o podrías devolver 'Desconocido')
    return uid;
  }

  Future<void> _refresh() async {
    setState(() {
      _transfersFuture = _initAndFetch();
    });
    await _transfersFuture.catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Traspasos del grupo'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: FutureBuilder<List<TransferRecord>>(
        future: _transfersFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text('Error cargando traspasos:\n${snap.error}'),
            );
          }
          final transfers = snap.data ?? [];
          if (transfers.isEmpty) {
            return const Center(child: Text('No hay traspasos en este grupo'));
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: transfers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final t = transfers[i];
                final date = t.date.toDate();
                final formattedDate =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                final fromAlias = _aliasFor(t.fromUid);
                final toAlias = _aliasFor(t.toUid);
                final isSent = t.type == 'enviada';

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSent
                          ? Colors.red.shade100
                          : Colors.green.shade100,
                      child: Icon(
                        isSent ? Icons.arrow_upward : Icons.arrow_downward,
                        color: isSent ? Colors.red : Colors.green,
                      ),
                    ),
                    title: Text(
                      '${isSent ? 'Enviado' : 'Recibido'}: ${t.amount.toStringAsFixed(2)}',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('Fecha: $formattedDate'),
                        const SizedBox(height: 2),
                        Text('De: $fromAlias'),
                        Text('A: $toAlias '),
                      ],
                    ),
                    trailing: Text(
                      isSent
                          ? '-${t.amount.toStringAsFixed(2)}'
                          : '+${t.amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isSent ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
