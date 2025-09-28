// lib/screens/join_group_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({Key? key}) : super(key: key);

  @override
  _JoinGroupScreenState createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();
  final _capitalCtrl = TextEditingController();

  bool _loading = false;
  bool _found = false;
  bool _codeInvalid = false;

  String? _groupId;
  String? _groupName;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _aliasCtrl.dispose();
    _capitalCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchGroup() async {
    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (name.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rellena nombre y código')));
      return;
    }

    setState(() {
      _loading = true;
      _found = false;
      _codeInvalid = false;
    });

    try {
      final query = await FirebaseFirestore.instance
          .collection('Grupos')
          .where('NombreGrupo', isEqualTo: name)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Grupo no encontrado')));
      } else {
        final doc = query.docs.first;
        final data = doc.data();
        final realCode = (data['CodigoGrupo'] ?? '').toString();

        if (realCode != code) {
          setState(() => _codeInvalid = true);
        } else {
          setState(() {
            _found = true;
            _groupId = doc.id;
            _groupName = data['NombreGrupo'] as String? ?? name;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error buscando grupo: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _joinGroup() async {
    if (!_found || _groupId == null) return;

    final alias = _aliasCtrl.text.trim();
    final capital = double.tryParse(_capitalCtrl.text.trim());
    if (alias.isEmpty || capital == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alias o capital inválidos')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final groupId = _groupId!;

    final personRef = FirebaseFirestore.instance
        .collection('Personas')
        .doc(uid);
    final personGroupRef = personRef.collection('Grupos').doc(groupId);
    final memberRef = FirebaseFirestore.instance
        .collection('MiembrosGrupos')
        .doc(groupId)
        .collection('Personas')
        .doc(uid);

    try {
      // 1) Asegurarnos de que el doc Personas/{uid} exista
      final personSnap = await personRef.get();
      if (!personSnap.exists) {
        await personRef.set({
          'createdAt': FieldValue.serverTimestamp(),
          // otros campos de usuario, si los necesitas
        });
      }

      // 2) Leer ambos snapshots
      final memberSnap = await memberRef.get();
      final pgSnap = await personGroupRef.get();

      // 3) Si ya existe en ambos, salir
      if (memberSnap.exists && pgSnap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya perteneces a este grupo')),
        );
        return;
      }

      // 4) Preparar un batch para crear donde falte
      final batch = FirebaseFirestore.instance.batch();

      if (!memberSnap.exists) {
        batch.set(memberRef, {
          'Alias': alias,
          'CapitalInicial': capital,
          'joinedAt': FieldValue.serverTimestamp(),
        });
      }

      if (!pgSnap.exists) {
        batch.set(personGroupRef, {
          'NombreGrupo': _groupName,
          'AliasUsuario': alias,
          'CapitalInicial': capital,
          'joinedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('¡Te has unido al grupo!')));
      Navigator.of(context).pop(true);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al unirse: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar y Unirse a Grupo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Nombre de grupo
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre grupo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Código de grupo
            TextField(
              controller: _codeCtrl,
              decoration: InputDecoration(
                labelText: 'Código',
                border: const OutlineInputBorder(),
                errorText: _codeInvalid ? 'Código erróneo' : null,
              ),
            ),
            const SizedBox(height: 16),

            // Botón buscar
            ElevatedButton.icon(
              onPressed: _loading ? null : _searchGroup,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: const Text('Buscar grupo'),
            ),

            // Formulario de unirse si se encontró el grupo
            if (_found) ...[
              const SizedBox(height: 24),
              Text(
                'Grupo encontrado:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _groupName!,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),

              TextField(
                controller: _aliasCtrl,
                decoration: const InputDecoration(
                  labelText: 'Alias',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _capitalCtrl,
                decoration: const InputDecoration(
                  labelText: 'Capital inicial',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: _joinGroup,
                icon: const Icon(Icons.group_add),
                label: const Text('Unirse'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
