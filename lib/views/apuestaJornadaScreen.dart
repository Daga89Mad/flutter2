import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plantillalogin/core/firebaseCrudService.dart';
import 'package:plantillalogin/core/roundBetting.dart';
import 'package:plantillalogin/core/roundBettingStore.dart';

class ApuestaJornadaScreen extends StatefulWidget {
  const ApuestaJornadaScreen({super.key});
  @override
  State<ApuestaJornadaScreen> createState() => _ApuestaJornadaState();
}

class _ApuestaJornadaState extends State<ApuestaJornadaScreen> {
  late String _season;
  late final List<String> _seasons;
  int _round = 1;
  bool _loading = true;
  bool _saving = false;
  bool _dialogOpen = false;
  String? _error;
  String? _selectedId;
  String? _uid;
  List<RoundFixture> _fixtures = [];
  RoundRehearsal _rehearsal = RoundRehearsal(bets: [], kickoffs: {});
  RoundBettingStore? _store;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  Timer? _clock;
  int _generation = 0;
  final _odds = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final year = now.month >= 7 ? now.year : now.year - 1;
    _seasons = List.generate(5, (i) => '${year - i}-${year - i + 1}');
    _season = _seasons.first;
    _load();
    _clock = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _clock?.cancel();
    _odds.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _matches {
    final root = FirebaseFirestore.instance
        .collection('LaLiga')
        .doc('Resultados');
    if (_season == FirebaseCrudService.legacySeason) {
      return root.collection('Jornadas').doc('$_round').collection('Partidos');
    }
    return root
        .collection('Temporadas')
        .doc(_season)
        .collection('Jornadas')
        .doc('$_round')
        .collection('Partidos');
  }

  int? _score(dynamic value) {
    final score = int.tryParse('${value ?? ''}');
    return score != null && score >= 0 ? score : null;
  }

  RoundFixture _fixture(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final raw = d['InicioUTC'];
    final kickoff = raw is Timestamp
        ? raw.toDate()
        : raw is String
        ? DateTime.tryParse(raw)
        : null;
    final status = '${d['Estado'] ?? ''}'.toLowerCase();
    // Un marcador 0-0 o Empate=true por sí solos no confirman el final.
    final finished =
        d['Finalizado'] == true ||
        const [
          'ft',
          'match finished',
          'full time',
          'finalizado',
        ].contains(status);
    return RoundFixture(
      id: doc.id,
      home: '${d['Local'] ?? ''}',
      away: '${d['Visitante'] ?? ''}',
      kickoff: kickoff,
      finished: finished,
      homeGoals: _score(d['GolesLocal']),
      awayGoals: _score(d['GolesVisitante']),
      unavailable: const [
        'postponed',
        'cancelled',
        'canceled',
        'aplazado',
        'cancelado',
        'pst',
        'canc',
      ].contains(status),
    );
  }

  List<RoundFixture> get _effectiveFixtures => _fixtures.map((m) {
    final override = _rehearsal.kickoffs[m.id];
    return override == null ? m : m.withKickoff(override);
  }).toList();

  RoundPlan get _plan => RoundBetting.plan(
    fixtures: _effectiveFixtures,
    bets: _rehearsal.bets,
    now: DateTime.now(),
  );

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _fixtures = [];
      _store = null;
      _selectedId = null;
      _odds.clear();
    });
    await _subscription?.cancel();
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null)
        throw StateError('Inicia sesión para preparar apuestas.');
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (!mounted || generation != _generation) return;
      final store = RoundBettingStore(prefs, uid, _season, _round);
      final rehearsal = store.read();
      _store = store;
      _uid = uid;
      _rehearsal = rehearsal;
      _subscription = _matches.snapshots().listen(
        (snap) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _fixtures = snap.docs.map(_fixture).toList();
            _loading = false;
            _error = null;
          });
        },
        onError: (Object error) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _error = 'No se pudieron leer los partidos: $error';
            _loading = false;
          });
        },
      );
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  String _money(int cents) => '${(cents / 100).toStringAsFixed(2)} €';
  String _date(DateTime? date) {
    if (date == null) return 'Sin hora de inicio';
    final d = date.toLocal();
    String two(int n) => '$n'.padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _editKickoff(RoundFixture fixture) async {
    final original = (fixture.kickoff ?? DateTime.now()).toLocal();
    final day = await showDatePicker(
      context: context,
      initialDate: original,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(original),
    );
    if (time == null || !mounted) return;
    final next = RoundRehearsal(
      bets: _rehearsal.bets,
      kickoffs: {
        ..._rehearsal.kickoffs,
        fixture.id: DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ).toUtc(),
      },
    );
    setState(() => _saving = true);
    try {
      await _store!.save(next);
      if (mounted)
        setState(() {
          _rehearsal = next;
          _selectedId = null;
          _odds.clear();
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _prepare() async {
    if (_saving || _dialogOpen || _error != null) return;
    final plan = _plan;
    final selectedId =
        _selectedId ??
        (plan.candidates.length == 1 ? plan.candidates.single.id : null);
    final explicitlySelected = _selectedId != null;
    final selected = plan.candidates
        .where((m) => m.id == selectedId)
        .firstOrNull;
    final odds = double.tryParse(_odds.text.trim().replaceAll(',', '.'));
    if (selected == null ||
        odds == null ||
        !odds.isFinite ||
        odds < RoundBetting.minimumOdds) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Elige un partido e introduce una cuota de al menos 2,80.',
          ),
        ),
      );
      return;
    }
    final generation = _generation;
    final expires = DateTime.now().add(const Duration(seconds: 60));
    setState(() => _dialogOpen = true);
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar apuesta simulada'),
        content: Text(
          '${selected.label}\n${_date(selected.kickoff)}\n'
          'Selección: empate · A favor\nImporte: ${_money(plan.cents)}\n'
          'Cuota introducida: ${odds.toStringAsFixed(2)}\n'
          'Beneficio si aciertas: ${((plan.cents / 100) * (odds - 1)).toStringAsFixed(2)} € '
          'antes de comisiones.\n\nAutorización válida durante 60 segundos.\n'
          'Este OK solo registra una simulación. No envía dinero a Betfair.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK · simular apuesta'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _dialogOpen = false;
      _saving = approved == true;
    });
    if (approved != true) return;
    try {
      if (generation != _generation || !DateTime.now().isBefore(expires)) {
        throw StateError(
          'La preparación ha caducado. Prepara y confirma otra vez.',
        );
      }
      // Relectura del servidor tras el OK. Un error nunca se interpreta como permiso.
      final fresh = await _matches.get(const GetOptions(source: Source.server));
      if (!mounted || generation != _generation) return;
      _fixtures = fresh.docs.map(_fixture).toList();
      final current = _plan;
      final stillSelected = current.candidates
          .where((m) => m.id == selected.id)
          .firstOrNull;
      if (!DateTime.now().isBefore(expires) ||
          !current.canPrepare ||
          current.cents != plan.cents ||
          stillSelected == null ||
          (current.candidates.length > 1 && !explicitlySelected) ||
          stillSelected.kickoff != selected.kickoff ||
          FirebaseAuth.instance.currentUser?.uid != _uid) {
        throw StateError(
          'Han cambiado los partidos o el importe. Revisa y vuelve a confirmar.',
        );
      }
      final next = RoundRehearsal(
        kickoffs: _rehearsal.kickoffs,
        bets: [
          ..._rehearsal.bets,
          RehearsalBet(
            matchId: selected.id,
            label: selected.label,
            cents: current.cents,
            odds: odds,
            approvedAt: DateTime.now(),
          ),
        ],
      );
      await _store!.save(next);
      if (!mounted) return;
      setState(() {
        _rehearsal = next;
        _selectedId = null;
        _odds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Simulación registrada. Ninguna apuesta real enviada.'),
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final busy = _loading || _saving || _dialogOpen;
    final candidates = plan.candidates;
    // La elección de simultáneos nunca se hace de forma automática.
    final selectedId =
        _selectedId ?? (candidates.length == 1 ? candidates.single.id : null);
    final selectedValid = candidates.any((m) => m.id == selectedId);
    final byId = {for (final m in _fixtures) m.id: m};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apuesta a jornada'),
        actions: [
          IconButton(
            onPressed: busy ? null : _load,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'SIMULACIÓN · Betfair sin conectar\n'
                'Cada apuesta requiere tu OK. No se envía dinero real. '
                'El historial se guarda solo en este dispositivo.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _season,
                  decoration: const InputDecoration(
                    labelText: 'Temporada · LaLiga',
                  ),
                  items: _seasons
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: busy
                      ? null
                      : (s) {
                          if (s != null) {
                            _season = s;
                            _load();
                          }
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _round,
                  decoration: const InputDecoration(labelText: 'Jornada'),
                  items: List.generate(
                    38,
                    (i) =>
                        DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                  ),
                  onChanged: busy
                      ? null
                      : (r) {
                          if (r != null) {
                            _round = r;
                            _load();
                          }
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '1 € → 2 € → 4 €… máximo 256 €. Cuota mínima 2,80.\n'
            'Cada jornada reinicia en 1 €. Un empate final en cualquier partido detiene la jornada.',
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!),
            ),
          if (!_loading && _error == null) ...[
            const SizedBox(height: 16),
            Text(plan.message, style: Theme.of(context).textTheme.titleMedium),
            if (plan.canPrepare) ...[
              Text('Próximo importe: ${_money(plan.cents)}'),
              ...candidates.map(
                (m) => Card(
                  child: ListTile(
                    leading: Icon(
                      selectedId == m.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    title: Text(m.label),
                    subtitle: Text(_date(m.kickoff)),
                    selected: selectedId == m.id,
                    onTap: busy
                        ? null
                        : () => setState(() {
                            _selectedId = m.id;
                            _odds.clear();
                          }),
                  ),
                ),
              ),
              TextField(
                controller: _odds,
                enabled: !busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cuota del empate para simular',
                  helperText: 'Introducción manual. No es una cuota verificada de Betfair.',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy || !selectedValid ? null : _prepare,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Preparar apuesta'),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Partidos de la jornada · hora local del dispositivo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_fixtures.isEmpty)
              const Text('Usa «Cargar resultados» para importar esta jornada.'),
            ..._effectiveFixtures.map(
              (m) => ListTile(
                title: Text(m.label),
                subtitle: Text(
                  '${_date(m.kickoff)}\n${m.hasResult
                      ? 'Final: ${m.homeGoals}–${m.awayGoals}'
                      : m.unavailable
                      ? 'Aplazado o cancelado'
                      : 'Sin resultado final confirmado'}',
                ),
                trailing: m.hasResult
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.edit_calendar),
                        tooltip: 'Ajustar horario solo para simular',
                        onPressed: busy ? null : () => _editKickoff(m),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Historial de simulación de esta jornada',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_rehearsal.bets.isEmpty)
              const Text('Todavía no has confirmado ninguna apuesta simulada.'),
            ..._rehearsal.bets.map((b) {
              final m = byId[b.matchId];
              final result = m == null || !m.hasResult
                  ? 'Pendiente de resultado final'
                  : m.draw
                  ? 'Acertada (simulación)'
                  : 'Fallada (simulación)';
              return ListTile(
                title: Text(b.label),
                subtitle: Text(
                  '${_money(b.cents)} · cuota ${b.odds.toStringAsFixed(2)}\n$result',
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
