// lib/views/createGroupScreen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();
  final _capitalCtrl = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _aliasCtrl.dispose();
    _capitalCtrl.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final alias = _aliasCtrl.text.trim();
    final capital = double.tryParse(
      _capitalCtrl.text.trim().replaceAll(',', '.'),
    );

    if (capital == null || capital < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introduce un capital inicial válido')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay usuario autenticado')),
      );
      return;
    }

    setState(() => _loading = true);

    final db = FirebaseFirestore.instance;

    try {
      // 1) Comprobar que no exista ya un grupo con ese nombre
      //    (JoinGroupScreen busca por NombreGrupo, así que conviene que sea único)
      final existing = await db
          .collection('Grupos')
          .where('NombreGrupo', isEqualTo: name)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya existe un grupo con ese nombre')),
        );
        return;
      }

      // 2) Documento del grupo con id automático
      final groupRef = db.collection('Grupos').doc();
      final groupId = groupRef.id;

      // 3) Referencias de pertenencia (mismas rutas que en JoinGroupScreen)
      final memberRef = db
          .collection('MiembrosGrupos')
          .doc(groupId)
          .collection('Personas')
          .doc(uid);

      final personRef = db.collection('Personas').doc(uid);
      final personGroupRef = personRef.collection('Grupos').doc(groupId);

      // 4) Asegurar que exista Personas/{uid}
      final personSnap = await personRef.get();

      // 5) Escritura atómica con batch
      final batch = db.batch();

      batch.set(groupRef, {
        'NombreGrupo': name,
        'CodigoGrupo': code,
        'CreadorUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!personSnap.exists) {
        batch.set(personRef, {'createdAt': FieldValue.serverTimestamp()});
      }

      // El creador queda automáticamente como miembro del grupo
      batch.set(memberRef, {
        'Alias': alias,
        'CapitalInicial': capital,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      batch.set(personGroupRef, {
        'NombreGrupo': name,
        'AliasUsuario': alias,
        'CapitalInicial': capital,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (!mounted) return;
      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grupo "$name" creado correctamente')),
      );

      // Devolvemos true por si la pantalla anterior quiere refrescar
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creando grupo: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear grupo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Nombre del grupo
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre del grupo',
                  prefixIcon: Icon(Icons.group),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Introduce un nombre'
                    : null,
              ),
              const SizedBox(height: 12),

              // Código del grupo
              TextFormField(
                controller: _codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código del grupo',
                  helperText: 'Los demás lo necesitarán para unirse',
                  prefixIcon: Icon(Icons.vpn_key),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Introduce un código'
                    : null,
              ),
              const SizedBox(height: 12),

              // Alias del creador
              TextFormField(
                controller: _aliasCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tu alias en el grupo',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Introduce un alias'
                    : null,
              ),
              const SizedBox(height: 12),

              // Capital inicial
              TextFormField(
                controller: _capitalCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Capital inicial',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Introduce el capital';
                  }
                  final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
                  if (parsed == null || parsed < 0) return 'Capital no válido';
                  return null;
                },
              ),
              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _loading ? null : _createGroup,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_circle),
                label: Text(_loading ? 'Creando...' : 'Crear grupo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
