import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class JornadaAccess {
  static const collection = 'AccesoApuestaJornada';
  static const firstUid = 'DBbLkTOEvqMTUP4zMAn7ap8iLFZ2';
  final FirebaseFirestore firestore;
  JornadaAccess({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> user(String uid) =>
      firestore.collection(collection).doc(uid);

  /// La marca impide que borrar el permiso vuelva a dar acceso en otro login.
  Future<void> initialize(String uid) async {
    if (uid != firstUid) return;
    final marker = user('_inicializacion');
    final permission = user(uid);
    await firestore.runTransaction((tx) async {
      final initialized = await tx.get(marker);
      if (initialized.exists) return;
      final existing = await tx.get(permission);
      if (!existing.exists) tx.set(permission, {'activo': true});
      tx.set(marker, {'uidInicial': firstUid});
    });
  }
}

/// Oculta el acceso hasta confirmar el permiso en el servidor. Reacciona a
/// cambios de usuario, retirada del permiso y errores de lectura.
class JornadaAccessGate extends StatefulWidget {
  final Widget Function(BuildContext context, bool allowed) builder;
  const JornadaAccessGate({super.key, required this.builder});

  @override
  State<JornadaAccessGate> createState() => _JornadaAccessGateState();
}

class _JornadaAccessGateState extends State<JornadaAccessGate> {
  StreamSubscription<User?>? _auth;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _permission;
  bool _allowed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _auth = FirebaseAuth.instance.authStateChanges().listen(
      (user) => unawaited(_watch(user)),
      onError: (Object _) {
        if (mounted) setState(() => _allowed = false);
      },
    );
  }

  Future<void> _watch(User? user) async {
    final generation = ++_generation;
    if (mounted) setState(() => _allowed = false);
    await _permission?.cancel();
    if (!mounted || generation != _generation || user == null) return;
    final access = JornadaAccess();
    try {
      await access.initialize(user.uid);
    } catch (_) {
      /* Un error de inicialización nunca concede acceso. */
    }
    if (!mounted || generation != _generation) return;
    _permission = access
        .user(user.uid)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (!mounted || generation != _generation) return;
            setState(
              () => _allowed =
                  !snapshot.metadata.isFromCache &&
                  snapshot.exists &&
                  snapshot.data()?['activo'] == true,
            );
          },
          onError: (Object _) {
            if (mounted && generation == _generation)
              setState(() => _allowed = false);
          },
        );
  }

  @override
  void dispose() {
    _generation++;
    _auth?.cancel();
    _permission?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _allowed);
}
