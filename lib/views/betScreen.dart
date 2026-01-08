// lib/screens/bet_screen.dart

import 'package:flutter/material.dart';
import 'package:plantillalogin/models/match_option.dart';
import '../core/firebaseCrudService.dart';

class BetScreen extends StatefulWidget {
  final String groupId;
  final String uid;

  const BetScreen({Key? key, required this.groupId, required this.uid})
    : super(key: key);

  @override
  _BetScreenState createState() => _BetScreenState();
}

class _BetScreenState extends State<BetScreen> {
  final _service = FirebaseCrudService();

  final List<String> _leagues = ['LaLiga', 'SerieA', 'Liga Profesional'];
  String? _selectedLeague;
  String? _selectedMatchId;

  final _jornadaController = TextEditingController();
  final _cantidadController = TextEditingController();
  final _cuotaController = TextEditingController();

  List<MatchOption> _matches = [];

  @override
  void dispose() {
    _jornadaController.dispose();
    _cantidadController.dispose();
    _cuotaController.dispose();
    super.dispose();
  }

  Future<void> _loadMatches() async {
    final liga = _selectedLeague;
    final jornada = _jornadaController.text.trim();
    if (liga == null || jornada.isEmpty) return;

    setState(() => _matches = []);
    try {
      final list = await _service.getMatches(liga, jornada);
      setState(() {
        _matches = list;
        _selectedMatchId = list.isNotEmpty ? list.first.id : null;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando partidos: $e')));
    }
  }

  Future<void> _saveBet() async {
    if (_selectedLeague == null ||
        _selectedMatchId == null ||
        _jornadaController.text.trim().isEmpty ||
        _cantidadController.text.trim().isEmpty ||
        _cuotaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rellena todos los campos')));
      return;
    }

    double cantidad;
    double cuota;
    try {
      cantidad = double.parse(_cantidadController.text.trim());
      cuota = double.parse(_cuotaController.text.trim());
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cantidad y cuota deben ser números')),
      );
      return;
    }

    try {
      await _service.placeBet(
        groupId: widget.groupId,
        userId: widget.uid,
        matchId: _selectedMatchId!,
        league: _selectedLeague!,
        jornada: _jornadaController.text.trim(),
        amount: cantidad,
        cuota: cuota,
      );

      // 1) Mostramos SnackBar de confirmación
      final snackBarController = ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apuesta guardada correctamente')),
      );

      // 2) Esperamos a que el SnackBar desaparezca (opcional)
      await snackBarController.closed;

      // 3) Cerramos la pantalla devolviendo 'true'
      Navigator.of(context).pop(true);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error guardando apuesta: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Realizar Apuesta')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Liga:'),
              DropdownButton<String>(
                isExpanded: true,
                hint: const Text('Selecciona liga'),
                value: _selectedLeague,
                items: _leagues
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedLeague = val;
                    _matches = [];
                    _selectedMatchId = null;
                  });
                },
              ),
              const SizedBox(height: 16),

              const Text('Jornada:'),
              TextField(
                controller: _jornadaController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  hintText: 'Introduce jornada',
                ),
                onSubmitted: (_) => _loadMatches(),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadMatches,
                child: const Text('Cargar Partidos'),
              ),
              const SizedBox(height: 16),

              const Text('Partido:'),
              DropdownButton<String>(
                isExpanded: true,
                hint: const Text('Selecciona partido'),
                value: _selectedMatchId,
                items: _matches.map((m) {
                  return DropdownMenuItem(
                    value: m.id,
                    child: Text(m.displayName),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedMatchId = val),
              ),
              const SizedBox(height: 16),

              const Text('Cantidad:'),
              TextField(
                controller: _cantidadController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: '0.00'),
              ),
              const SizedBox(height: 16),

              const Text('Cuota:'),
              TextField(
                controller: _cuotaController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: '0.00'),
              ),
              const SizedBox(height: 24),

              Center(
                child: ElevatedButton.icon(
                  onPressed: _saveBet,
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar Apuesta'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
