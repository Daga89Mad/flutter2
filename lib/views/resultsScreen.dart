import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:plantillalogin/core/firebaseCrudService.dart'; // Ajusta la ruta si tu servicio está en otro paquete

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  // 1) Configuración de ligas
  final List<String> _opciones = ['España', 'Italia'];
  final Map<String, int> _leagueIds = {
    'España': 4335, // LaLiga
    'Italia': 4332, // Serie A
  };

  // 2) Estado UI
  String _seleccion = 'España';
  bool _cargando = false;
  String? _error;
  List<dynamic>? _events;

  // 3) Controlador para jornada manual
  final TextEditingController _roundController = TextEditingController();

  // 4) Constantes API
  static const String _apiKey = '123';
  static const String _season = '2025-2026';

  // 5) Última jornada detectada (para prellenar el campo)
  int? _lastRound;

  @override
  void initState() {
    super.initState();
    _loadLastRound();
  }

  @override
  void dispose() {
    _roundController.dispose();
    super.dispose();
  }

  /// Carga la última jornada de la temporada y la sugiere en el TextField
  Future<void> _loadLastRound() async {
    setState(() {
      _cargando = true;
      _error = null;
      _events = null;
    });

    final leagueId = _leagueIds[_seleccion]!;
    final uriSeason = Uri.parse(
      'https://www.thesportsdb.com/api/v1/json/$_apiKey/eventsseason.php'
      '?id=$leagueId&s=$_season',
    );

    try {
      final resp = await http.get(uriSeason);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final allEvents = (data['events'] as List<dynamic>?) ?? [];
      if (allEvents.isEmpty) {
        setState(() => _error = 'No hay partidos para $_season');
        return;
      }

      final rounds = allEvents
          .map((e) => int.tryParse(e['intRound']?.toString() ?? '') ?? 0)
          .where((r) => r > 0)
          .toList();

      if (rounds.isEmpty) {
        setState(() => _error = 'Datos de jornadas no disponibles');
        return;
      }

      _lastRound = rounds.reduce((a, b) => a > b ? a : b);
      _roundController.text = _lastRound.toString();
    } catch (e) {
      setState(() => _error = 'Error cargando última jornada: $e');
    } finally {
      setState(() => _cargando = false);
    }
  }

  /// Carga los partidos de la jornada especificada usando eventsround.php
  Future<void> _fetchMatchesByRound(int round) async {
    setState(() {
      _cargando = true;
      _error = null;
      _events = null;
    });

    final leagueId = _leagueIds[_seleccion]!;
    final uriRound = Uri.parse(
      'https://www.thesportsdb.com/api/v1/json/$_apiKey/eventsround.php'
      '?id=$leagueId'
      '&r=$round',
    );

    try {
      final resp = await http.get(uriRound);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final events = (data['events'] as List<dynamic>?) ?? [];

      setState(() {
        _events = events;
        if (events.isEmpty) {
          _error = 'Jornada $round sin partidos registrados';
        }
      });
    } catch (e) {
      setState(() => _error = 'Error cargando jornada $round: $e');
    } finally {
      setState(() => _cargando = false);
    }
  }

  /// Guarda o actualiza en Firestore todos los partidos de _events
  Future<void> _saveToFirestore() async {
    if (_events == null || _events!.isEmpty) return;

    final leagueCollection = _seleccion == 'España' ? 'LaLiga' : 'SerieA';
    final jornada = _roundController.text.trim();
    final service = FirebaseCrudService();

    for (var ev in _events!) {
      final home = ev['strHomeTeam'] as String? ?? '';
      final away = ev['strAwayTeam'] as String? ?? '';
      final hScore = ev['intHomeScore']?.toString() ?? '';
      final aScore = ev['intAwayScore']?.toString() ?? '';

      final empate = hScore.isNotEmpty && aScore.isNotEmpty && hScore == aScore;
      final victoriaLocal =
          hScore.isNotEmpty &&
          aScore.isNotEmpty &&
          int.parse(hScore) > int.parse(aScore);
      final victoriaVisitante =
          hScore.isNotEmpty &&
          aScore.isNotEmpty &&
          int.parse(aScore) > int.parse(hScore);

      final data = {
        'Empate': empate,
        'VictoriaLocal': victoriaLocal,
        'VictoriaVisitante': victoriaVisitante,
        'GolesLocal': hScore,
        'GolesVisitante': aScore,
        'Local': home,
        'Visitante': away,
        'Jornada': jornada,
      };

      // Usamos el upsert en lugar de createMatch
      await service.upsertMatch(
        league: leagueCollection,
        jornada: jornada,
        data: data,
        local: home,
        visitante: away,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Datos guardados/actualizados en Firestore'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partidos por Jornada')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Liga'),
              value: _seleccion,
              items: _opciones
                  .map((op) => DropdownMenuItem(value: op, child: Text(op)))
                  .toList(),
              onChanged: (val) {
                if (val == null) return;
                setState(() => _seleccion = val);
                _loadLastRound();
              },
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _roundController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Jornada',
                hintText: 'Número de jornada',
              ),
            ),

            const SizedBox(height: 12),

            ElevatedButton(
              onPressed: _cargando
                  ? null
                  : () {
                      final input = _roundController.text.trim();
                      final round = int.tryParse(input);
                      if (round == null || round < 1) {
                        setState(() => _error = 'Introduce jornada válida');
                        return;
                      }
                      _fetchMatchesByRound(round);
                    },
              child: Text(
                _cargando
                    ? 'Cargando...'
                    : 'Cargar jornada ${_roundController.text}',
              ),
            ),

            const SizedBox(height: 12),

            ElevatedButton(
              onPressed: (_events == null || _cargando)
                  ? null
                  : _saveToFirestore,
              child: const Text('Guardar datos'),
            ),

            const SizedBox(height: 24),

            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _cargando
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : (_events == null || _events!.isEmpty)
                    ? const Center(child: Text('Sin datos'))
                    : ListView.builder(
                        itemCount: _events!.length,
                        itemBuilder: (ctx, i) {
                          final ev = _events![i];
                          final home = ev['strHomeTeam'] as String? ?? '';
                          final away = ev['strAwayTeam'] as String? ?? '';
                          final hScore = ev['intHomeScore']?.toString() ?? '–';
                          final aScore = ev['intAwayScore']?.toString() ?? '–';
                          final date = ev['dateEvent'] ?? '';
                          final time = ev['strTime'] ?? '';

                          return ListTile(
                            title: Text('$home  $hScore–$aScore  $away'),
                            subtitle: Text('$date  $time'),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
