import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:plantillalogin/core/firebaseCrudService.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();
  final _capitalCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirebaseCrudService _service = FirebaseCrudService();

  bool _showForm = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _aliasCtrl.dispose();
    _capitalCtrl.dispose();
    super.dispose();
  }

  Future<void> _onCreatePressed() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final String groupName = _nameCtrl.text.trim();
    final String groupCode = _codeCtrl.text.trim();
    final String alias = _aliasCtrl.text.trim();
    final String capitalRaw = _capitalCtrl.text.trim();

    final double? capital = double.tryParse(capitalRaw.replaceAll(',', '.'));
    if (capital == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Capital inicial inválido')));
      setState(() => _isLoading = false);
      return;
    }

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      await _service.createGroupAndAddMember(
        groupName: groupName,
        groupCode: groupCode,
        adminUid: uid,
        memberUid: uid,
        alias: alias,
        initialCapital: capital,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grupo creado correctamente')),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creando grupo: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear grupo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () => setState(() => _showForm = !_showForm),
              child: Text(
                _showForm ? 'Ocultar formulario' : 'Crear grupo nuevo',
              ),
            ),
            const SizedBox(height: 16),
            if (_showForm)
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nombre de grupo',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _codeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Código grupo',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _aliasCtrl,
                          decoration: const InputDecoration(labelText: 'Álias'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _capitalCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Capital Inicial',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'Requerido';
                            final parsed = double.tryParse(
                              v.trim().replaceAll(',', '.'),
                            );
                            return parsed == null ? 'Número inválido' : null;
                          },
                        ),
                        const SizedBox(height: 20),
                        _isLoading
                            ? const CircularProgressIndicator()
                            : SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _onCreatePressed,
                                  child: const Text('Crear'),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
