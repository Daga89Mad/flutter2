// lib/screens/transferScreen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../models/group_member.dart';
import '../core/firebaseCrudService.dart';

class TransferScreen extends StatefulWidget {
  final List<GroupMember> members;
  final String groupId;
  final String senderUid;

  const TransferScreen({
    super.key,
    required this.members,
    required this.groupId,
    required this.senderUid,
  });

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  String? _selectedReceiverId;
  bool _isSaving = false;

  // Servicio
  final FirebaseCrudService _service = FirebaseCrudService();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _saveTransfer() async {
    if (!_formKey.currentState!.validate()) return;

    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Introduce una cantidad válida')),
      );
      return;
    }

    final receiverUid = _selectedReceiverId;
    if (receiverUid == null || receiverUid.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un receptor')));
      return;
    }

    if (receiverUid == widget.senderUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes enviarte a ti mismo')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _service.createTransfer(
        groupId: widget.groupId,
        senderUid: widget.senderUid,
        receiverUid: receiverUid,
        amount: amount,
        date: DateTime.now(),
      );

      // Parar spinner antes de navegar para evitar estados inconsistentes
      if (mounted) {
        setState(() => _isSaving = false);
        // Pequeña espera para que el botón actualice su estado visualmente
        await Future.delayed(const Duration(milliseconds: 100));
        Navigator.of(
          context,
        ).pop({'amount': amount, 'receiverId': receiverUid});
      } else {
        // Si el widget ya no está montado, solo logueamos
        debugPrint(
          '[_saveTransfer] widget desmontado antes de pop, no se puede navegar',
        );
      }
    } catch (e, st) {
      debugPrint('[_saveTransfer] error: $e\n$st');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error guardando traspaso: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Realizar Traspaso')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Campo cantidad
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cantidad',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty)
                    return 'Introduce una cantidad';
                  final v = double.tryParse(value.trim().replaceAll(',', '.'));
                  if (v == null || v <= 0)
                    return 'Introduce una cantidad válida mayor que 0';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Desplegable receptor
              DropdownButtonFormField<String>(
                value: _selectedReceiverId,
                decoration: const InputDecoration(
                  labelText: 'Receptor',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                items: widget.members.map((m) {
                  return DropdownMenuItem<String>(
                    value: m.uid,
                    child: Text(m.alias.isNotEmpty ? m.alias : m.uid),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedReceiverId = val),
                validator: (value) {
                  if (value == null || value.isEmpty)
                    return 'Selecciona un receptor';
                  return null;
                },
              ),

              const Spacer(),

              // Botón guardar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveTransfer,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Guardando...' : 'Guardar traspaso'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
