import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:plantillalogin/core/roundAuthorization.dart';
import 'package:plantillalogin/core/roundBetting.dart';

/// Canal privado por usuario. Solo admite autorizaciones de ensayo.
class RoundPcBridge {
  final DocumentReference<Map<String, dynamic>> command;
  RoundPcBridge(String uid)
    : command = FirebaseFirestore.instance.collection('PuenteJornada').doc(uid);

  Stream<DocumentSnapshot<Map<String, dynamic>>> get states =>
      command.collection('Estado').doc('actual').snapshots();

  Future<Map<String, dynamic>?> current() async =>
      (await command.get(const GetOptions(source: Source.server))).data();

  Future<String> publish(
    RoundAuthorization auth,
    List<RehearsalBet> bets,
  ) async {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final previous = (await tx.get(command)).data();
      if (previous?['action'] == 'authorize') {
        final raw = previous?['authorization'];
        final expires = raw is Map
            ? DateTime.tryParse('${raw['expiresAt']}')
            : null;
        if (expires == null || expires.isAfter(DateTime.now())) {
          throw StateError(
            'Ya hay una jornada enviada al PC. Revócala antes de autorizar otra.',
          );
        }
      }
      tx.set(command, {
        'schema': 1,
        'mode': 'simulation',
        'requestId': id,
        'action': 'authorize',
        'scope': auth.scope,
        'authorization': auth.toJson(),
        'initialBets': bets.map((b) => b.toJson()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return id;
  }

  Future<void> revoke(String id) async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(command);
      if (!snap.exists) return;
      if (snap.data()?['requestId'] != id) {
        throw StateError(
          'Hay otra autorización en el PC. Actualiza antes de detenerla.',
        );
      }
      tx.update(command, {
        'action': 'revoke',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
