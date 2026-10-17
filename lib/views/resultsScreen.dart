import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:plantillalogin/core/firebaseCrudService.dart'; // Ajusta la ruta si tu servicio está en otro paquete
import 'package:firebase_auth/firebase_auth.dart';
import 'package:plantillalogin/core/sportsDbFixture.dart';

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

  // Temporadas disponibles. La primera es la "legacy" (datos ya cargados).
  final List<String> _seasons = ['2025-2026', '2026-2027'];
  late String _selectedSeason;

  // 2) Estado UI
  String _seleccion = 'España';
  bool _cargando = false;
  String? _error;
  List<dynamic>? _events;

  // 3) Controlador para jornada manual
  final TextEditingController _roundController = TextEditingController();

  // 4) Constantes API
  static const String _apiKey = '123';

  // 5) Última jornada detectada (para prellenar el campo)
  int? _lastRound;

  @override
  void initState() {
    super.initState();
    _selectedSeason = _currentSeason();
    _loadLastRound();
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
    _roundController.dispose();
    super.dispose();
  }

  // Los errores del proveedor externo no deben bloquear la entrada manual.
  Future<http.Response> _getWithRetry(Uri uri) async {
    http.Response? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        last = await http.get(uri).timeout(const Duration(seconds: 20));
        if (last.statusCode == 200) return last;
        if (last.statusCode < 500 || attempt == 1) return last;
      } catch (_) {
        if (attempt == 1) rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return last!;
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
      '?id=$leagueId&s=$_selectedSeason',
    );

    try {
      final resp = await _getWithRetry(uriSeason);
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final allEvents = (data['events'] as List<dynamic>?) ?? [];
      if (allEvents.isEmpty) {
        setState(() => _error = 'No hay partidos para $_selectedSeason');
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
      // La detección automática es opcional: dejar disponible la jornada manual.
      if (mounted) setState(() => _error =
        'No se pudo detectar la última jornada (proveedor: $e). '
        'Puedes introducir una jornada manualmente y pulsar Cargar jornada.');
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
      '&r=$round'
      '&s=$_selectedSeason',
    );

    try {
      final resp = await _getWithRetry(uriRound);
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
      if (mounted) setState(() => _error =
        'No se pudo consultar la jornada $round ($e). '
        'El proveedor externo puede estar temporalmente caído; vuelve a intentarlo.');
    } finally {
      setState(() => _cargando = false);
    }
  }

  /// Guarda o actualiza en Firestore todos los partidos de _events
  Future<void> _saveToFirestore() async {
    if (_events == null || _events!.isEmpty) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    final leagueCollection = _seleccion == 'España' ? 'LaLiga' : 'SerieA';
    final jornada = _roundController.text.trim();
    final service = FirebaseCrudService();

    try {
      // 1) Upsert de todos los partidos en la temporada seleccionada
      for (var ev in _events!) {
        final home = ev['strHomeTeam'] as String? ?? '';
        final away = ev['strAwayTeam'] as String? ?? '';
        final hScore = ev['intHomeScore']?.toString() ?? '';
        final aScore = ev['intAwayScore']?.toString() ?? '';

        final empate =
            hScore.isNotEmpty && aScore.isNotEmpty && hScore == aScore;
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
          'Temporada': _selectedSeason,
          'Estado': ev['strStatus']?.toString() ?? '',
          'Finalizado': sportsDbFinished(ev as Map),
          if (sportsDbKickoff(ev) != null)
            'InicioUTC': Timestamp.fromDate(sportsDbKickoff(ev)!),
        };

        await service.upsertMatch(
          league: leagueCollection,
          temporada: _selectedSeason,
          jornada: jornada,
          data: data,
          local: home,
          visitante: away,
        );
      }

      // 2) Obtener usuario actual
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() => _error = 'No hay usuario autenticado.');
        return;
      }
      final currentUid = currentUser.uid;

      // 3) Obtener IDs de grupos a los que pertenece el usuario
      final groupIds = await service.getUserGroupIds(currentUid);

      // 4) Para cada grupo: obtener miembros y actualizar aciertos para todos
      for (final groupId in groupIds) {
        // Intentamos obtener miembros con el helper del servicio
        List<String> memberUids = [];

        try {
          final membersWithStats = await service.getGroupMembersWithStats(
            groupId,
          );
          // Asumimos que GroupMember tiene una propiedad `uid`.
          memberUids = membersWithStats
              .map((m) {
                try {
                  return (m as dynamic).uid as String;
                } catch (_) {
                  return null;
                }
              })
              .whereType<String>()
              .toList();
        } catch (e) {
          // Si falla el helper, intentamos leer directamente la colección MiembrosGrupos
          try {
            final snap = await FirebaseFirestore.instance
                .collection('MiembrosGrupos')
                .doc(groupId)
                .collection('Personas')
                .get();
            memberUids = snap.docs.map((d) => d.id).toList();
          } catch (e2) {
            // Si tampoco funciona, saltamos este grupo y lo registramos
            print('No se pudieron obtener miembros del grupo $groupId: $e2');
            continue;
          }
        }

        if (memberUids.isEmpty) {
          print(
            'Grupo $groupId no tiene miembros o no se pudieron obtener UIDs.',
          );
          continue;
        }

        // Llamada que actualiza los aciertos para todos los miembros del grupo,
        // usando la temporada seleccionada.
        await service.updateAciertosForGroup(
          league: leagueCollection,
          temporada: _selectedSeason,
          jornada: jornada,
          groupId: groupId,
          memberUids: memberUids,
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Datos guardados/actualizados en Firestore'),
        ),
      );
    } catch (e, st) {
      print('Error en _saveToFirestore: $e\n$st');
      setState(() => _error = 'Error guardando datos: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    } finally {
      setState(() => _cargando = false);
    }
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
              decoration: const InputDecoration(labelText: 'Temporada'),
              initialValue: _selectedSeason,
              items: _seasons
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (val) {
                if (val == null) return;
                setState(() => _selectedSeason = val);
                _loadLastRound();
              },
            ),

            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Liga'),
              initialValue: _seleccion,
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
