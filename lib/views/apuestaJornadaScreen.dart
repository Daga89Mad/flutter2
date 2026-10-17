import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:plantillalogin/core/firebaseCrudService.dart';
import 'package:plantillalogin/core/roundBetting.dart';
import 'package:plantillalogin/core/roundBettingStore.dart';
import 'package:plantillalogin/core/roundAuthorization.dart';

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
  final Map<String, String> _choices = {};
  String? _status;
  String? _uid;
  List<RoundFixture> _fixtures = [];
  RoundRehearsal _rehearsal = RoundRehearsal(bets: [], kickoffs: {});
  RoundBettingStore? _store;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  Timer? _clock;
  int _generation = 0;
  final _odds = TextEditingController();
  final _budget = TextEditingController(text: '511');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final year = now.month >= 7 ? now.year : now.year - 1;
    _seasons = List.generate(5, (i) => '${year - i}-${year - i + 1}');
    _season = _seasons.first;
    _load();
    _clock = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() {});
        unawaited(_advance());
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _clock?.cancel();
    _odds.dispose();
    _budget.dispose();
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
      _choices.clear();
      _status = null;
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
      if (rehearsal.authorization != null) {
        _budget.text = (rehearsal.authorization!.budgetCents / 100)
            .toStringAsFixed(2);
        _odds.text = rehearsal.authorization!.rehearsalOdds.toStringAsFixed(2);
      }
      _subscription = _matches.snapshots().listen(
        (snap) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _fixtures = snap.docs.map(_fixture).toList();
            _loading = false;
            _error = null;
          });
          unawaited(_advance());
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
          _choices.clear();
          _odds.clear();
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _scope => 'LaLiga/$_season/$_round';

  Set<String> _selectedFor(List<List<RoundFixture>> groups) => {
    for (final group in groups)
      if (group.length == 1)
        group.single.id
      else if (_choices[group.first.id] != null)
        _choices[group.first.id]!,
  };

  Future<void> _approveRound() async {
    if (_saving || _dialogOpen || _loading || _error != null || _store == null)
      return;
    final groups = RoundAuthorization.groups(
      _effectiveFixtures,
      DateTime.now(),
    );
    final odds = double.tryParse(_odds.text.trim().replaceAll(',', '.'));
    final budget = double.tryParse(_budget.text.trim().replaceAll(',', '.'));
    if (odds == null ||
        budget == null ||
        !budget.isFinite ||
        budget < 1 ||
        budget > 511) {
      _notify(
        'Introduce un presupuesto de 1 a 511 € y una cuota de ensayo de al menos 2,80.',
      );
      return;
    }
    late RoundAuthorization draft;
    try {
      draft = RoundAuthorization.issue(
        scope: _scope,
        fixtures: _effectiveFixtures,
        selectedIds: _selectedFor(groups),
        budgetCents: (budget * 100).round(),
        rehearsalOdds: odds,
        now: DateTime.now(),
      );
      final spent = _rehearsal.bets.fold<int>(0, (sum, b) => sum + b.cents);
      if (draft.budgetCents <= spent)
        throw StateError(
          'El presupuesto debe cubrir lo ya simulado y la siguiente apuesta.',
        );
    } catch (e) {
      _notify('$e');
      return;
    }
    final generation = _generation;
    final expires = DateTime.now().add(const Duration(seconds: 60));
    setState(() => _dialogOpen = true);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Autorizar jornada $_round · simulación'),
        scrollable: true,
        content: Text(
          'LaLiga · $_season · jornada $_round\n'
          'Inicio: 1 €. Duplicar tras derrota final. Máximo por apuesta: 256 €.\n'
          'Presupuesto total de la jornada: ${_money(draft.budgetCents)}.\n'
          'Cuota mínima: 2,80. Cuota ficticia del ensayo: ${odds.toStringAsFixed(2)}.\n\n'
          '${_effectiveFixtures.where((m) => draft.selectedIds.contains(m.id)).map((m) => '${m.label} · ${_date(m.kickoff)}').join('\n')}\n\n'
          'Este OK permite simular las apuestas elegidas sin más confirmaciones '
          'durante esta jornada. Se detiene al confirmar cualquier empate, '
          'alcanzar el presupuesto o el límite. La próxima jornada necesita otro OK.\n\n'
          'No se enviará dinero real. El ensayo solo avanza con esta pantalla abierta '
          'y resultados actualizados en Firestore. Puedes detenerlo en cualquier momento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('OK · autorizar jornada'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _dialogOpen = false;
      _saving = confirmed == true;
    });
    if (confirmed != true) return;
    try {
      final fresh = await _matches.get(const GetOptions(source: Source.server));
      if (!mounted || generation != _generation) return;
      _fixtures = fresh.docs.map(_fixture).toList();
      if (!DateTime.now().isBefore(expires) ||
          FirebaseAuth.instance.currentUser?.uid != _uid ||
          draft.schedule !=
              RoundAuthorization.fingerprint(_effectiveFixtures)) {
        throw StateError(
          'La preparación caducó o cambió el calendario. Revisa y confirma otra vez.',
        );
      }
      // Revalida también horarios, empates y las elecciones tras la lectura fresca.
      final authorization = RoundAuthorization.issue(
        scope: _scope,
        fixtures: _effectiveFixtures,
        selectedIds: draft.selectedIds,
        budgetCents: draft.budgetCents,
        rehearsalOdds: draft.rehearsalOdds,
        now: DateTime.now(),
      );
      final next = RoundRehearsal(
        bets: _rehearsal.bets,
        kickoffs: _rehearsal.kickoffs,
        authorization: authorization,
      );
      await _store!.save(next);
      if (mounted)
        setState(() {
          _rehearsal = next;
          _status = 'Jornada autorizada para simulación.';
        });
    } catch (e) {
      if (mounted) _notify('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) unawaited(_advance());
  }

  void _notify(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _revoke(String message) async {
    final next = RoundRehearsal(
      bets: _rehearsal.bets,
      kickoffs: _rehearsal.kickoffs,
    );
    await _store!.save(next);
    if (mounted)
      setState(() {
        _rehearsal = next;
        _status = message;
      });
  }

  Future<void> _stop([
    String message = 'Autorización revocada. No se simularán más apuestas.',
  ]) async {
    if (_saving || _store == null) return;
    setState(() => _saving = true);
    try {
      await _revoke(message);
    } catch (e) {
      if (mounted) _notify('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _advance() async {
    final authorization = _rehearsal.authorization;
    if (!mounted ||
        _loading ||
        _saving ||
        _dialogOpen ||
        _error != null ||
        authorization == null ||
        _store == null ||
        FirebaseAuth.instance.currentUser?.uid != _uid)
      return;
    final generation = _generation;
    // El plan local evita lecturas de servidor cada diez segundos si no hay una apuesta próxima.
    final preview = authorization.next(
      currentScope: _scope,
      fixtures: _effectiveFixtures,
      bets: _rehearsal.bets,
      now: DateTime.now(),
    );
    if (!preview.canPrepare) {
      if (preview.stopped) {
        await _stop(preview.message);
        return;
      }
      if (mounted) setState(() => _status = preview.message);
      return;
    }
    setState(() => _saving = true);
    try {
      final fresh = await _matches.get(const GetOptions(source: Source.server));
      if (!mounted || generation != _generation) return;
      _fixtures = fresh.docs.map(_fixture).toList();
      if (FirebaseAuth.instance.currentUser?.uid != _uid) return;
      final plan = authorization.next(
        currentScope: _scope,
        fixtures: _effectiveFixtures,
        bets: _rehearsal.bets,
        now: DateTime.now(),
      );
      if (!plan.canPrepare) {
        if (plan.stopped) {
          await _revoke(plan.message);
        } else {
          setState(() => _status = plan.message);
        }
        return;
      }
      final fixture = plan.candidates.single;
      final next = RoundRehearsal(
        kickoffs: _rehearsal.kickoffs,
        authorization: authorization,
        bets: [
          ..._rehearsal.bets,
          RehearsalBet(
            matchId: fixture.id,
            label: fixture.label,
            cents: plan.cents,
            odds: authorization.rehearsalOdds,
            approvedAt: DateTime.now(),
          ),
        ],
      );
      await _store!.save(next);
      if (mounted)
        setState(() {
          _rehearsal = next;
          _status =
              'Simulada automáticamente: ${fixture.label} · ${_money(plan.cents)}. Ninguna orden real enviada.';
        });
    } catch (e) {
      if (mounted) setState(() => _status = 'Ensayo en espera: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final authorization = _rehearsal.authorization;
    final groups = RoundAuthorization.groups(
      _effectiveFixtures,
      DateTime.now(),
    );
    final busy = _loading || _saving || _dialogOpen;
    final locked = busy || authorization != null;
    final byId = {for (final m in _fixtures) m.id: m};
    final spent = _rehearsal.bets.fold<int>(0, (sum, b) => sum + b.cents);
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
                'SIMULACIÓN · Un OK por jornada\n'
                'Después del OK se simula la secuencia elegida sin más confirmaciones. '
                'No se envía dinero real. Mantén esta pantalla abierta y los resultados actualizados. '
                'La ejecución con la app cerrada requiere un servicio externo todavía sin conectar.',
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
                  onChanged: locked
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
                  onChanged: locked
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
            'Cada jornada empieza en 1 € y necesita su propio OK. Un empate final en cualquier partido detiene la jornada.',
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
            Text(
              _status ?? plan.message,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Total simulado en esta jornada: ${_money(spent)}'),
            if (authorization != null) ...[
              Text(
                'Límite autorizado: ${_money(authorization.budgetCents)} · válido hasta ${_date(authorization.expiresAt)}',
              ),
              ..._effectiveFixtures
                  .where((m) => authorization.selectedIds.contains(m.id))
                  .map(
                    (m) => ListTile(
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(m.label),
                      subtitle: Text(_date(m.kickoff)),
                    ),
                  ),
              OutlinedButton.icon(
                onPressed: busy ? null : _stop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Detener jornada y revocar OK'),
              ),
            ] else ...[
              Text(
                'Elige un partido por grupo antes de autorizar',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...groups.indexed.map(
                (entry) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grupo ${entry.$1 + 1}${entry.$2.length > 1 ? ' · horarios solapados' : ''}',
                        ),
                        ...entry.$2.map((m) {
                          final selected =
                              entry.$2.length == 1 ||
                              _choices[entry.$2.first.id] == m.id;
                          return ListTile(
                            leading: Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                            ),
                            title: Text(m.label),
                            subtitle: Text(_date(m.kickoff)),
                            selected: selected,
                            onTap: locked
                                ? null
                                : () => setState(
                                    () => _choices[entry.$2.first.id] = m.id,
                                  ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              TextField(
                controller: _budget,
                enabled: !locked,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Presupuesto máximo de la jornada (€)',
                  helperText: 'Incluye todas las apuestas de esta jornada. Nueve derrotas de 1 a 256 € suman 511 €.',
                ),
              ),
              TextField(
                controller: _odds,
                enabled: !locked,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cuota ficticia para todo el ensayo',
                  helperText: 'Manual, mínimo 2,80. No es una cuota obtenida de una casa de apuestas.',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy || plan.stopped || groups.isEmpty
                    ? null
                    : _approveRound,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Revisar y autorizar jornada'),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Partidos · hora local del dispositivo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_fixtures.isEmpty)
              const Text(
                'Usa «Cargar resultados» para importar los diez partidos de esta jornada.',
              ),
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
                        onPressed: locked ? null : () => _editKickoff(m),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Historial de simulación de esta jornada',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_rehearsal.bets.isEmpty)
              const Text('Todavía no se ha simulado ninguna apuesta.'),
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
                  '${_money(b.cents)} · cuota ficticia ${b.odds.toStringAsFixed(2)}\n$result',
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
