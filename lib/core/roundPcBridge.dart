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

  Future<Map<String, dynamic>> terminalState(String id) async {
    final state =
        (await command
                .collection('Estado')
                .doc('actual')
                .get(const GetOptions(source: Source.server)))
            .data();
    if (state == null ||
        state['requestId'] != id ||
        !['stopped', 'revoked'].contains(state['status'])) {
      throw StateError(
        'Espera a que el PC confirme que el ensayo anterior terminó o fue revocado.',
      );
    }
    return state;
  }

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
      final state = (await tx.get(command.collection('Estado').doc('actual')))
          .data();
      final canRestart =
          auth.fromNow &&
          state?['requestId'] == previous?['requestId'] &&
          ['stopped', 'revoked'].contains(state?['status']);
      if (previous != null && auth.fromNow) {
        if (!canRestart)
          throw StateError(
            'El PC debe confirmar el final del ensayo anterior antes de reiniciar.',
          );
        if (previous['scope'] == auth.scope) {
          final priorAuth = Map<String, dynamic>.from(
            previous['authorization'] as Map,
          );
          final priorSpent = priorAuth['previousSpentCents'] as int? ?? 0;
          final spent = (state!['bets'] as List).fold<int>(
            priorSpent,
            (sum, b) => sum + (b['cents'] as int),
          );
          if (spent != auth.previousSpentCents)
            throw StateError(
              'Cambió el historial del PC. Actualiza antes del nuevo OK.',
            );
        }
      }
      if (previous?['action'] == 'authorize' && !canRestart) {
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
        'schema': auth.fromNow ? 2 : 1,
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
