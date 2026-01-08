// lib/core/firebaseCrudService.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:plantillalogin/models/group.dart';
import 'package:plantillalogin/models/group_member.dart';
import 'package:plantillalogin/models/match_option.dart';
import 'package:plantillalogin/models/bet_detail.dart';

class FirebaseCrudService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Constructor por defecto, sin parámetros
  FirebaseCrudService();

  // Helper que convierte cualquier raw a double
  double _parseDouble(dynamic raw) {
    if (raw == null) return 0.0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0.0;
  }

  /// Registra un usuario con email y contraseña
  /// Lanza Exception con mensaje legible si hay error
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapAuthError(e));
    }
  }

  /// Mapea los códigos de FirebaseAuthException a mensajes legibles
  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El correo electrónico no tiene un formato válido.';
      case 'user-not-found':
        return 'No existe una cuenta con ese correo.';
      case 'wrong-password':
        return 'La contraseña es incorrecta.';
      case 'email-already-in-use':
        return 'Ya existe una cuenta registrada con ese correo.';
      case 'weak-password':
        return 'La contraseña debe tener al menos 6 caracteres.';
      default:
        return e.message ?? 'Ocurrió un error de autenticación.';
    }
  }

  /// Traduce códigos de FirebaseAuthException a mensajes legibles
  String _translateErrorCode(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El correo electrónico no es válido.';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con ese correo.';
      case 'weak-password':
        return 'La contraseña es demasiado débil.';
      case 'operation-not-allowed':
        return 'Operación no permitida. Contacta al soporte.';
      default:
        return e.message ?? 'Error desconocido de autenticación.';
    }
  }
  // ==================================================
  // 1) PARTIDOS / JORNADAS
  // ==================================================

  /// Referencia dinámica a la subcolección:
  /// {league}/Resultados/Jornadas/{jornada}/Partidos
  CollectionReference _matchesRef(String league, String jornada) {
    return _db
        .collection(league)
        .doc('Resultados')
        .collection('Jornadas')
        .doc(jornada)
        .collection('Partidos');
  }

  Future<void> createMatch(
    String league,
    String jornada,
    Map<String, dynamic> data,
  ) async {
    try {
      await _matchesRef(league, jornada).add(data);
      print('✅ Partido guardado en Firestore');
    } catch (e) {
      print('❌ Error al guardar partido: $e');
    }
  }

  Future<List<Map<String, dynamic>>> readMatches(
    String league,
    String jornada,
  ) async {
    try {
      final snap = await _matchesRef(league, jornada).get();
      return snap.docs
          .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
          .toList();
    } catch (e) {
      print('❌ Error al leer partidos: $e');
      return [];
    }
  }

  Future<void> updateMatch(
    String league,
    String jornada,
    String id,
    Map<String, dynamic> newData,
  ) async {
    try {
      await _matchesRef(league, jornada).doc(id).update(newData);
      print('✅ Partido actualizado correctamente');
    } catch (e) {
      print('❌ Error al actualizar partido: $e');
    }
  }

  Future<void> deleteMatch(String league, String jornada, String id) async {
    try {
      await _matchesRef(league, jornada).doc(id).delete();
      print('✅ Partido eliminado correctamente');
    } catch (e) {
      print('❌ Error al eliminar partido: $e');
    }
  }

  // ==================================================
  // 2) GRUPOS DE USUARIO
  // ==================================================

  Future<List<String>> getUserGroupIds(String uid) async {
    final snap = await _db
        .collection('Personas')
        .doc(uid)
        .collection('Grupos')
        .get();
    return snap.docs.map((d) => d.id).toList();
  }

  Future<List<Group>> getUserGroups(String uid) async {
    final ids = await getUserGroupIds(uid);
    final docs = await Future.wait(
      ids.map((gid) => _db.collection('Grupos').doc(gid).get()),
    );

    return docs.where((d) => d.exists).map((d) {
      final data = d.data()!;
      return Group(
        id: d.id,
        nombre: data['NombreGrupo'] as String? ?? 'Sin nombre',
      );
    }).toList();
  }

  // ==================================================
  // 3) APUESTAS & MIEMBROS
  // ==================================================

  /// Recupera alias, capitalInicial y estadísticas de apuestas
  /// ruta: MiembrosGrupos/{groupId}/Personas/{uid}
  Future<List<GroupMember>> getGroupMembersWithStats(String groupId) async {
    final memberSnap = await _db
        .collection('MiembrosGrupos')
        .doc(groupId)
        .collection('Personas')
        .get();

    List<GroupMember> result = [];

    for (var doc in memberSnap.docs) {
      final memberData = doc.data();
      final uid = doc.id;

      final betsSnap = await _db
          .collection('Apuestas')
          .doc(groupId)
          .collection('Personas')
          .doc(uid)
          .collection('Realizadas')
          .get();

      double perdidas = 0.0;
      double ganancias = 0.0;

      for (var bdoc in betsSnap.docs) {
        final b = bdoc.data();
        final acierto = b['Acierto'] as bool? ?? false;
        final cantidad = _parseDouble(b['Cantidad']);
        final cuota = _parseDouble(b['Cuota']);

        if (acierto) {
          ganancias += cantidad * cuota;
        } else {
          perdidas += cantidad;
        }
      }
      final transferSend = await _db
          .collection('Traspasos')
          .doc(groupId)
          .collection('Personas')
          .doc(uid)
          .collection('Enviadas')
          .get();

      final transferReceived = await _db
          .collection('Traspasos')
          .doc(groupId)
          .collection('Personas')
          .doc(uid)
          .collection('Recibidas')
          .get();

      double enviadas = 0.0;
      double recepcionadas = 0.0;

      for (var bdoc in transferSend.docs) {
        final b = bdoc.data();
        final cantidad = _parseDouble(b['Cantidad']);

        enviadas += cantidad;
      }
      for (var bdoc in transferReceived.docs) {
        final b = bdoc.data();
        final cantidad = _parseDouble(b['Cantidad']);
        recepcionadas += cantidad;
      }

      result.add(
        GroupMember.fromMaps(
          uid: uid,
          memberData: memberData,
          totalPerdidas: perdidas,
          totalGanancias: ganancias,
          traspasosRecibidos: recepcionadas,
          traspasosEnviados: enviadas,
        ),
      );
    }

    return result;
  }

  /// Recupera todas las apuestas realizadas de un usuario,
  /// parseando correctamente los campos y ordenándolas por fecha.
  Future<List<BetDetail>> fetchRealizedBets({
    required String groupId,
    required String uid,
  }) async {
    final snapshot = await _db
        .collection('Apuestas')
        .doc(groupId)
        .collection('Personas')
        .doc(uid)
        .collection('Realizadas')
        .orderBy('FechaApuesta', descending: true)
        .get();

    List<BetDetail> result = [];

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;

      final liga = data['Liga']?.toString() ?? '';
      final jornadaRaw = data['Jornada'];
      final jornada = jornadaRaw is num
          ? jornadaRaw.toInt()
          : int.tryParse(jornadaRaw.toString()) ?? 0;

      final matchId = data['MatchId'].toString();
      final acierto = data['Acierto'] as bool? ?? false;
      final cuota = _parseDouble(data['Cuota']);
      final cantidad = _parseDouble(data['Cantidad']);

      final fechaRaw = data['FechaApuesta'];
      final fechaApuesta = fechaRaw is Timestamp
          ? fechaRaw.toDate()
          : DateTime.tryParse(fechaRaw.toString()) ?? DateTime.now();

      // Traemos datos de local y visitante
      final matchDoc = await _matchesRef(
        liga,
        jornada.toString(),
      ).doc(matchId).get();
      final matchData = matchDoc.data() as Map<String, dynamic>? ?? {};
      final local = matchData['Local'] as String? ?? '-';
      final visitante = matchData['Visitante'] as String? ?? '-';

      result.add(
        BetDetail(
          id: doc.id,
          acierto: acierto,
          cuota: cuota,
          cantidad: cantidad,
          fechaApuesta: fechaApuesta,
          jornada: jornada,
          local: local,
          visitante: visitante,
        ),
      );
    }

    return result;
  }

  // ==================================================
  // 4) MATCH OPTIONS & APUESTAS
  // ==================================================

  Future<List<MatchOption>> getMatches(String league, String jornada) async {
    final snapshot = await _matchesRef(league, jornada).get();
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final local = data['Local'] as String? ?? '';
      final visitante = data['Visitante'] as String? ?? '';
      return MatchOption(id: doc.id, displayName: '$local VS $visitante');
    }).toList();
  }

  Future<void> upsertMatch({
    required String league,
    required String jornada,
    required Map<String, dynamic> data,
    required String local,
    required String visitante,
  }) async {
    final col = _matchesRef(league, jornada);
    final query = await col
        .where('Local', isEqualTo: local)
        .where('Visitante', isEqualTo: visitante)
        .get();

    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.update(data);
    } else {
      await col.add(data);
    }
  }

  Future<void> placeBet({
    required String groupId,
    required String userId,
    required String matchId,
    required String league,
    required String jornada,
    required double amount,
    required double cuota,
  }) async {
    final ref = _db
        .collection('Apuestas')
        .doc(groupId)
        .collection('Personas')
        .doc(userId)
        .collection('Realizadas');

    await ref.add({
      'MatchId': matchId,
      'Liga': league,
      'Jornada': jornada,
      'Cantidad': amount,
      'Cuota': cuota,
      'Acierto': false,
      'FechaApuesta': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateAciertosForGroup({
    required String league,
    required String jornada,
    required String groupId,
    required List<String> memberUids,
  }) async {
    final partidosSnap = await _matchesRef(league, jornada).get();
    final batch = _db.batch();

    for (var pdoc in partidosSnap.docs) {
      final matchId = pdoc.id;
      final resultadoFirestore = pdoc.get('Empate');

      for (var uid in memberUids) {
        final colRealizadas = _db
            .collection('Apuestas')
            .doc(groupId)
            .collection('Personas')
            .doc(uid)
            .collection('Realizadas');

        final querySnap = await colRealizadas
            .where('MatchId', isEqualTo: matchId)
            .get();

        for (var betDoc in querySnap.docs) {
          final currentAcierto = betDoc.get('Acierto');
          if (currentAcierto != resultadoFirestore) {
            batch.update(betDoc.reference, {'Acierto': resultadoFirestore});
          }
        }
      }
    }

    await batch.commit();
  }

  /// Guarda un traspaso (doc auto-id) en Enviadas y Recibidas de Firestore.
  /// Lanza Exception si hay error.
  Future<void> createTransfer({
    required String groupId,
    required String senderUid,
    required String receiverUid,
    required double amount,
    DateTime? date, // opcional, si no se pasa se usa DateTime.now()
  }) async {
    try {
      final DateTime now = date ?? DateTime.now();
      final Timestamp ts = Timestamp.fromDate(now);

      // Referencias a las subcolecciones donde se crearán documentos auto-id
      final CollectionReference senderEnviadas = _db
          .collection('Traspasos')
          .doc(groupId)
          .collection('Personas')
          .doc(senderUid)
          .collection('Enviadas');

      final CollectionReference receiverRecibidas = _db
          .collection('Traspasos')
          .doc(groupId)
          .collection('Personas')
          .doc(receiverUid)
          .collection('Recibidas');

      // Documentos con id automático
      final DocumentReference senderDocRef = senderEnviadas.doc();
      final DocumentReference receiverDocRef = receiverRecibidas.doc();

      // Datos según convención solicitada
      final Map<String, dynamic> sentData = {
        'Cantidad': amount,
        'Fecha': ts,
        'IdReceptor': receiverUid,
      };

      final Map<String, dynamic> receivedData = {
        'Cantidad': amount,
        'Fecha': ts,
        'IdEmisor': senderUid,
      };

      // Batch para atomicidad
      final WriteBatch batch = _db.batch();
      batch.set(senderDocRef, sentData);
      batch.set(receiverDocRef, receivedData);

      await batch.commit();

      // Log (opcional)
      print(
        '✅ Traspaso guardado: $amount de $senderUid a $receiverUid en grupo $groupId',
      );
    } catch (e) {
      print('❌ Error al guardar traspaso: $e');
      throw Exception('Error guardando traspaso: $e');
    }
  }
}
