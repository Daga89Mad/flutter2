// lib/views/betListScreen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/firebaseCrudService.dart';
import '../core/numberUtils.dart';
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

  /// Solo se puede editar/borrar si las apuestas son del usuario logueado
  bool get _isOwner => FirebaseAuth.instance.currentUser?.uid == widget.uid;

  @override
  void initState() {
    super.initState();
    _loadBets();
  }

  void _loadBets() {
    _betsFuture = _crud.fetchRealizedBets(
      groupId: widget.groupId,
      uid: widget.uid,
    );
  }

  void _reload() {
    setState(_loadBets);
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text)));
  }

  // ==================================================
  // EDITAR
  // ==================================================

  Future<void> _editBet(BetDetail bet) async {
    final result = await showDialog<({double amount, double cuota})>(
      context: context,
      builder: (_) => _EditBetDialog(bet: bet),
    );
    if (result == null) return;

    try {
      await _crud.updateBet(
        groupId: widget.groupId,
        uid: widget.uid,
        betId: bet.id,
        amount: result.amount,
        cuota: result.cuota,
      );
      _showSnack('Apuesta modificada');
      _reload();
    } catch (e) {
      _showSnack('Error modificando apuesta: $e');
    }
  }

  // ==================================================
  // BORRAR
  // ==================================================

  Future<void> _deleteBet(BetDetail bet) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar apuesta'),
        content: Text(
          '¿Seguro que quieres borrar la apuesta de '
          '${bet.local} vs ${bet.visitante} (J${bet.jornada}) '
          'por ${bet.cantidad.toStringAsFixed(2)}?\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(96, 40),
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _crud.deleteBet(
        groupId: widget.groupId,
        uid: widget.uid,
        betId: bet.id,
      );
      _showSnack('Apuesta borrada');
      _reload();
    } catch (e) {
      _showSnack('Error borrando apuesta: $e');
    }
  }

  // ==================================================

  Widget? _buildActions(BetDetail bet) {
    if (!_isOwner) return null;
    return PopupMenuButton<String>(
      tooltip: 'Opciones',
      onSelected: (value) {
        if (value == 'edit') _editBet(bet);
        if (value == 'delete') _deleteBet(bet);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit),
            title: Text('Modificar'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text('Borrar'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
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
                  trailing: _buildActions(bet),
                  onLongPress: _isOwner ? () => _editBet(bet) : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Diálogo para modificar cantidad y cuota de una apuesta.
/// Es un StatefulWidget para que los controllers se liberen correctamente
/// cuando el diálogo se cierra.
class _EditBetDialog extends StatefulWidget {
  final BetDetail bet;

  const _EditBetDialog({required this.bet});

  @override
  State<_EditBetDialog> createState() => _EditBetDialogState();
}

class _EditBetDialogState extends State<_EditBetDialog> {
  late final TextEditingController _cantidadController;
  late final TextEditingController _cuotaController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cantidadController = TextEditingController(
      text: formatDecimal(widget.bet.cantidad, 2),
    );
    // La cuota admite 3 decimales: solo los mostramos si hacen falta
    final cuota = widget.bet.cuota;
    _cuotaController = TextEditingController(
      text: formatDecimal(cuota, roundTo(cuota, 2) == cuota ? 2 : 3),
    );
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _cuotaController.dispose();
    super.dispose();
  }

  void _save() {
    final cantidad = parseDecimal(_cantidadController.text);
    final cuota = parseDecimal(_cuotaController.text);

    if (cantidad == null || cuota == null) {
      setState(() => _error = 'Cantidad y cuota deben ser números (ej: 10.50)');
      return;
    }
    if (cantidad <= 0 || cuota <= 0) {
      setState(() => _error = 'Cantidad y cuota deben ser mayores que 0');
      return;
    }

    Navigator.of(
      context,
    ).pop((amount: roundTo(cantidad, 2), cuota: roundTo(cuota, 3)));
  }

  @override
  Widget build(BuildContext context) {
    final bet = widget.bet;
    return AlertDialog(
      title: const Text('Modificar apuesta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${bet.local} vs ${bet.visitante}  ·  J${bet.jornada}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cantidadController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [DecimalTextInputFormatter(decimalDigits: 2)],
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                hintText: '0.00',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cuotaController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [DecimalTextInputFormatter(decimalDigits: 3)],
              decoration: const InputDecoration(
                labelText: 'Cuota',
                hintText: '0.00',
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(96, 40)),
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
