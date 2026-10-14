// lib/views/betScreen.dart

import 'package:flutter/material.dart';
import 'package:plantillalogin/core/firebaseCrudService.dart';
import 'package:plantillalogin/core/numberUtils.dart';
import 'package:plantillalogin/models/last_bet_match.dart';
import 'package:plantillalogin/models/last_bet_team.dart';
import 'package:plantillalogin/models/match_option.dart';

class BetScreen extends StatefulWidget {
  final String groupId;
  final String uid;

  const BetScreen({super.key, required this.groupId, required this.uid});

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

  /// true mientras se calcula la apuesta automática
  bool _loadingAuto = false;

  /// Número de partidos apostados que se muestran en la apuesta automática
  static const int _lastMatchesLimit = 5;

  @override
  void initState() {
    super.initState();
    _selectedSeason = _currentSeason();
    // Mostramos el popup de apuesta automática al abrir la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLastMatchesDialog();
    });
  }

  /// Calcula la temporada actual por fecha (la liga arranca en verano).
  /// Agosto de 2026 -> "2026-2027".
  String _currentSeason() {
    final now = DateTime.now();
    final y = now.year;
    final season = now.month >= 7 ? '$y-${y + 1}' : '${y - 1}-$y';
    return _seasons.contains(season) ? season : _seasons.last;
  }

  @override
  void dispose() {
    _jornadaController.dispose();
    _cantidadController.dispose();
    _cuotaController.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadMatches() async {
    final liga = _selectedLeague;
    final jornada = _jornadaController.text.trim();
    if (liga == null || jornada.isEmpty) return;

    setState(() => _matches = []);
    try {
      final list = await _service.getMatches(liga, _selectedSeason, jornada);
      if (!mounted) return;
      setState(() {
        _matches = list;
        _selectedMatchId = list.isNotEmpty ? list.first.id : null;
      });
    } catch (e) {
      _showSnack('Error cargando partidos: $e');
    }
  }

  // ==================================================
  // POPUP "APUESTA AUTOMÁTICA"
  // ==================================================

  /// Convierte los últimos partidos apostados en una lista de equipos
  /// (local y visitante de cada partido), cada uno con su jornada.
  List<LastBetTeam> _teamsFromMatches(List<LastBetMatch> matches) {
    final List<LastBetTeam> teams = [];
    final Set<String> seen = {};

    for (final m in matches) {
      for (final team in [m.local, m.visitante]) {
        if (team.isEmpty) continue;
        final t = LastBetTeam(
          team: team,
          league: m.league,
          temporada: m.temporada,
          jornada: m.jornada,
          amount: m.amount,
          matchId: m.matchId,
        );
        if (seen.add(t.key)) teams.add(t);
      }
    }
    return teams;
  }

  Future<void> _showLastMatchesDialog() async {
    List<LastBetTeam> teams = [];
    try {
      final lastMatches = await _service.fetchLastBetMatches(
        groupId: widget.groupId,
        uid: widget.uid,
        limit: _lastMatchesLimit,
      );
      teams = _teamsFromMatches(lastMatches);
    } catch (_) {
      // Si falla la carga, mostramos el popup vacío para poder cerrar.
    }

    if (!mounted) return;

    // Si hay varias ligas mostramos también la liga para distinguir equipos
    final multiLeague = teams.map((t) => t.league).toSet().length > 1;
    final multiSeason = teams.map((t) => t.temporada).toSet().length > 1;

    LastBetTeam? selected = teams.isNotEmpty ? teams.first : null;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Apuesta automática'),
              content: teams.isEmpty
                  ? const Text('No tienes apuestas anteriores en este grupo.')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Selecciona un equipo de tus últimos partidos '
                          'apostados:',
                        ),
                        const SizedBox(height: 12),
                        DropdownButton<LastBetTeam>(
                          isExpanded: true,
                          value: selected,
                          items: teams
                              .map(
                                (t) => DropdownMenuItem<LastBetTeam>(
                                  value: t,
                                  child: Text(
                                    [
                                      t.displayName,
                                      if (multiLeague) t.league,
                                      if (multiSeason) t.temporada,
                                    ].join('  ·  '),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setDialogState(() => selected = v),
                        ),
                        if (selected != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Apostado en J${selected!.jornada}: '
                            '${formatDecimal(selected!.amount)}  →  '
                            'Nueva cantidad: '
                            '${formatDecimal(roundTo(selected!.amount * 2))}',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ],
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

  /// Rellena el formulario a partir del equipo seleccionado:
  /// - Liga y temporada del partido original
  /// - Jornada = última jornada en la que se apostó a ese equipo + 1
  ///   (no la jornada seleccionada + 1)
  /// - Partido de ese equipo en la nueva jornada
  /// - Cantidad = cantidad apostada en la jornada seleccionada x 2
  /// - Cuota siempre en blanco
  Future<void> _applyLastBet(LastBetTeam t) async {
    final newAmount = roundTo(t.amount * 2);

    setState(() {
      _loadingAuto = true;
      _selectedSeason = _seasons.contains(t.temporada)
          ? t.temporada
          : _selectedSeason;
      _selectedLeague = _leagues.contains(t.league)
          ? t.league
          : _selectedLeague;
      _cantidadController.text = formatDecimal(newAmount);
      _cuotaController.clear(); // Cuota siempre en blanco
      _jornadaController.clear();
      _matches = [];
      _selectedMatchId = null;
    });

    try {
      // Última jornada en la que se apostó a este equipo
      final lastJornada = await _service.findLastBetJornadaForTeam(
        groupId: widget.groupId,
        uid: widget.uid,
        league: t.league,
        temporada: t.temporada,
        team: t.team,
        fromJornada: t.jornada,
      );
      final nextJornada = (lastJornada + 1).toString();

      final list = await _service.getMatches(
        t.league,
        t.temporada,
        nextJornada,
      );
      final matchId = await _service.findMatchIdForTeam(
        league: t.league,
        temporada: t.temporada,
        jornada: nextJornada,
        team: t.team,
      );

      if (!mounted) return;

      setState(() {
        _jornadaController.text = nextJornada;
        _matches = list;
        _selectedMatchId = matchId ?? (list.isNotEmpty ? list.first.id : null);
      });

      if (matchId == null) {
        _showSnack(
          'No se encontró partido de ${t.team} en la jornada $nextJornada '
          '(${t.temporada}). '
          'Revisa que la jornada esté cargada.',
        );
      }
    } catch (e) {
      _showSnack('Error cargando jornada: $e');
    } finally {
      if (mounted) setState(() => _loadingAuto = false);
    }
  }

  // ==================================================

  Future<void> _saveBet() async {
    if (_selectedLeague == null ||
        _selectedMatchId == null ||
        _jornadaController.text.trim().isEmpty ||
        _cantidadController.text.trim().isEmpty ||
        _cuotaController.text.trim().isEmpty) {
      _showSnack('Rellena todos los campos');
      return;
    }

    final cantidad = parseDecimal(_cantidadController.text);
    final cuota = parseDecimal(_cuotaController.text);
    if (cantidad == null || cuota == null) {
      _showSnack('Cantidad y cuota deben ser números (ej: 10.50)');
      return;
    }
    if (cantidad <= 0 || cuota <= 0) {
      _showSnack('Cantidad y cuota deben ser mayores que 0');
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
        amount: roundTo(cantidad, 2),
        cuota: roundTo(cuota, 3),
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
        // No bloqueamos la UX si la actualización de aciertos falla
        debugPrint('Error actualizando aciertos para el usuario: $e');
      }

      if (!mounted) return;

      // 1) Mostramos SnackBar de confirmación
      final snackBarController = ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apuesta guardada correctamente')),
      );

      // 2) Esperamos a que el SnackBar desaparezca
      await snackBarController.closed;

      // 3) Cerramos la pantalla devolviendo 'true'
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _showSnack('Error guardando apuesta: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realizar Apuesta'),
        actions: [
          IconButton(
            tooltip: 'Apuesta automática',
            icon: const Icon(Icons.history),
            onPressed: _loadingAuto ? null : _showLastMatchesDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_loadingAuto) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
              ],

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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [DecimalTextInputFormatter(decimalDigits: 2)],
                decoration: const InputDecoration(hintText: '0.00'),
              ),
              const SizedBox(height: 16),

              const Text('Cuota:'),
              TextField(
                controller: _cuotaController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [DecimalTextInputFormatter(decimalDigits: 3)],
                decoration: const InputDecoration(hintText: '0.00'),
              ),
              const SizedBox(height: 24),

              Center(
                child: ElevatedButton.icon(
                  onPressed: _loadingAuto ? null : _saveBet,
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
