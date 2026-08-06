// lib/screens/bet_screen.dart

import 'package:flutter/material.dart';
import 'package:plantillalogin/models/match_option.dart';
import 'package:plantillalogin/models/last_bet_match.dart';
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

  // Temporadas disponibles. La primera es la "legacy" (datos ya cargados).
  final List<String> _seasons = ['2025-2026', '2026-2027'];
  late String _selectedSeason;

  String? _selectedLeague;
  String? _selectedMatchId;

  final _jornadaController = TextEditingController();
  final _cantidadController = TextEditingController();
  final _cuotaController = TextEditingController();

  List<MatchOption> _matches = [];

  @override
  void initState() {
    super.initState();
    _selectedSeason = _currentSeason();
    // Mostramos el popup de "Últimos equipos" al abrir la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLastMatchesDialog();
    });
  }

  /// Calcula la temporada actual por fecha (la liga arranca en verano).
  /// Agosto de 2026 -> "2026-2027".
  String _currentSeason() {
    final now = DateTime.now();
    final y = now.year;
    return now.month >= 7 ? '$y-${y + 1}' : '${y - 1}-$y';
  }

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
      final list = await _service.getMatches(liga, _selectedSeason, jornada);
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

  double? parseNumber(String text) {
    final cleaned = text.trim().replaceAll('.', '').replaceAll(',', '.');
    // Si usas separador de miles como '.', lo eliminamos; luego convertimos la coma decimal a punto.
    return double.tryParse(cleaned);
  }

  // ==================================================
  // POPUP "ÚLTIMOS EQUIPOS"
  // ==================================================

  Future<void> _showLastMatchesDialog() async {
    List<LastBetMatch> lastMatches = [];
    try {
      lastMatches = await _service.fetchLastBetMatches(
        groupId: widget.groupId,
        uid: widget.uid,
      );
    } catch (_) {
      // Si falla la carga, mostramos el popup vacío para poder cerrar.
    }

    if (!mounted) return;

    LastBetMatch? selected = lastMatches.isNotEmpty ? lastMatches.first : null;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Últimos equipos'),
              content: lastMatches.isEmpty
                  ? const Text('No tienes apuestas anteriores en este grupo.')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Selecciona uno de tus últimos partidos apostados:',
                        ),
                        const SizedBox(height: 12),
                        DropdownButton<LastBetMatch>(
                          isExpanded: true,
                          value: selected,
                          items: lastMatches
                              .map(
                                (m) => DropdownMenuItem<LastBetMatch>(
                                  value: m,
                                  child: Text(
                                    '${m.local} vs ${m.visitante}  ·  ${m.league}  ·  ${m.temporada}  ·  J${m.jornada}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setDialogState(() => selected = v),
                        ),
                      ],
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cerrar'),
                ),
                ElevatedButton(
                  // Evitamos el minimumSize infinito del tema global
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(96, 40),
                  ),
                  onPressed: selected == null
                      ? null
                      : () {
                          final chosen = selected!;
                          Navigator.of(ctx).pop();
                          _applyLastBet(chosen);
                        },
                  child: const Text('Cargar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Rellena el formulario a partir de un partido anterior:
  /// - Misma temporada y liga que la apuesta original
  /// - Jornada+1
  /// - Partido del equipo local en la nueva jornada
  /// - Cantidad multiplicada por 2
  /// - Cuota siempre en blanco
  Future<void> _applyLastBet(LastBetMatch m) async {
    final nextJornada = (m.jornada + 1).toString();

    setState(() {
      _selectedSeason = _seasons.contains(m.temporada)
          ? m.temporada
          : _selectedSeason;
      _selectedLeague = _leagues.contains(m.league)
          ? m.league
          : _selectedLeague;
      _jornadaController.text = nextJornada;
      _cantidadController.text = (m.amount * 2).toStringAsFixed(2);
      _cuotaController.clear(); // Cuota siempre en blanco
      _matches = [];
      _selectedMatchId = null;
    });

    try {
      final list = await _service.getMatches(
        m.league,
        m.temporada,
        nextJornada,
      );
      // Usamos el equipo LOCAL como ancla para buscar en la nueva jornada
      final matchId = await _service.findMatchIdForTeam(
        league: m.league,
        temporada: m.temporada,
        jornada: nextJornada,
        team: m.local,
      );

      if (!mounted) return;

      setState(() {
        _matches = list;
        _selectedMatchId = matchId ?? (list.isNotEmpty ? list.first.id : null);
      });

      if (matchId == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se encontró partido de ${m.local} en la jornada $nextJornada '
              '(${m.temporada}). Revisa que la jornada esté cargada.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando jornada: $e')));
    }
  }

  // ==================================================

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

    final cantidad = parseNumber(_cantidadController.text);
    final cuota = parseNumber(_cuotaController.text);
    if (cantidad == null || cuota == null) {
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
        temporada: _selectedSeason,
        jornada: _jornadaController.text.trim(),
        amount: cantidad,
        cuota: cuota,
      );

      // Si el resultado del partido ya está guardado en la BD, actualizamos
      // únicamente las apuestas del usuario que acaba de apostar.
      try {
        await _service.updateAciertosForUser(
          league: _selectedLeague!,
          temporada: _selectedSeason,
          jornada: _jornadaController.text.trim(),
          groupId: widget.groupId,
          userId: widget.uid,
        );
      } catch (e) {
        // No queremos bloquear la UX si la actualización de aciertos falla;
        // registramos el error y seguimos.
        print('Error actualizando aciertos para el usuario: $e');
      }

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
      appBar: AppBar(
        title: const Text('Realizar Apuesta'),
        actions: [
          IconButton(
            tooltip: 'Últimos equipos',
            icon: const Icon(Icons.history),
            onPressed: _showLastMatchesDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Temporada:'),
              DropdownButton<String>(
                isExpanded: true,
                value: _selectedSeason,
                items: _seasons
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _selectedSeason = val;
                    _matches = [];
                    _selectedMatchId = null;
                  });
                },
              ),
              const SizedBox(height: 16),

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
