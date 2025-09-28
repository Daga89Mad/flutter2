// lib/views/bet_list_screen.dart

import 'package:flutter/material.dart';

import '../core/firebaseCrudService.dart';
import '../models/bet_detail.dart';

class BetListScreen extends StatefulWidget {
  final String groupId;
  final String uid;

  const BetListScreen({Key? key, required this.groupId, required this.uid})
    : super(key: key);

  @override
  _BetListScreenState createState() => _BetListScreenState();
}

class _BetListScreenState extends State<BetListScreen> {
  late Future<List<BetDetail>> _betsFuture;
  final FirebaseCrudService _crud = FirebaseCrudService();

  @override
  void initState() {
    super.initState();
    _betsFuture = _crud.fetchRealizedBets(
      groupId: widget.groupId,
      uid: widget.uid,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apuestas realizadas')),
      body: FutureBuilder<List<BetDetail>>(
        future: _betsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final bets = snapshot.data;
          if (bets == null || bets.isEmpty) {
            return const Center(child: Text('No hay apuestas realizadas aún.'));
          }
          return ListView.builder(
            itemCount: bets.length,
            itemBuilder: (context, index) {
              final bet = bets[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: Icon(
                    bet.acierto ? Icons.check_circle : Icons.cancel,
                    color: bet.acierto ? Colors.green : Colors.red,
                  ),
                  title: Text('${bet.local} vs ${bet.visitante}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Jornada: ${bet.jornada}'),
                      Text('Fecha: ${bet.fechaApuesta.toLocal()}'),
                      Text('Cantidad: ${bet.cantidad.toStringAsFixed(2)}'),
                      Text('Cuota: ${bet.cuota.toStringAsFixed(2)}'),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
