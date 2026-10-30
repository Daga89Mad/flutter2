import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:plantillalogin/core/roundAuthorization.dart';
import 'package:plantillalogin/core/roundBetting.dart';
import 'package:plantillalogin/core/liveRoundRestart.dart';

bool excludedRoundTeam(String name) {
  var text = name.toLowerCase();
  const accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  accents.forEach((a, b) => text = text.replaceAll(a, b));
  text = text.replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();
  return const {
    'real madrid',
    'real madrid cf',
    'real madrid c f',
    'real madrid club de futbol',
    'barcelona',
    'fc barcelona',
    'f c barcelona',
    'barca',
    'barca fc',
    'barcelona fc',
    'atletico de madrid',
    'atletico madrid',
    'club atletico de madrid',
    'club atletico madrid',
    'atletico de madrid sad',
    'atletico madrid sad',
  }.contains(text);
}

class ApuestaJornadaRondaRealScreen extends StatefulWidget {
  final String scope;
  final Future<List<RoundFixture>> Function() refresh;
  const ApuestaJornadaRondaRealScreen({
    super.key,
    required this.scope,
    required this.refresh,
  });
  @override
  State<ApuestaJornadaRondaRealScreen> createState() => _RoundRealState();
}

class _RoundRealState extends State<ApuestaJornadaRondaRealScreen> {
  List<RoundFixture> fixtures = [];
  final selected = <String>{};
  final markets = <String, TextEditingController>{},
      events = <String, TextEditingController>{};
  bool busy = false, confirmed = false;
  String? error;
  String? replacingRequestId;
  DocumentReference<Map<String, dynamic>> get command => FirebaseFirestore
      .instance
      .collection('PuenteJornadaRonda128Real')
      .doc(FirebaseAuth.instance.currentUser!.uid);

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    for (final c in [...markets.values, ...events.values]) {
      c.dispose();
    }
    super.dispose();
  }

  bool eligible(RoundFixture m) =>
      !excludedRoundTeam(m.home) && !excludedRoundTeam(m.away);
  List<RoundFixture> future(List<RoundFixture> data) =>
      data
          .where(
            (m) =>
                eligible(m) &&
                !m.hasResult &&
                !m.unavailable &&
                m.kickoff != null &&
                m.kickoff!.isAfter(
                  DateTime.now().add(const Duration(seconds: 60)),
                ),
          )
          .toList()
        ..sort((a, b) => a.kickoff!.compareTo(b.kickoff!));

  Future<void> reload() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.refresh();
      if (!mounted) return;
      setState(() {
        fixtures = data;
        selected.clear();
        confirmed = false;
        for (final m in data) {
          markets.putIfAbsent(m.id, TextEditingController.new);
          events.putIfAbsent(m.id, TextEditingController.new);
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<RoundFixture> validate(List<RoundFixture> data) {
    if (data.length != 10 || data.map((m) => m.id).toSet().length != 10) {
      throw StateError('Se necesitan los diez partidos fiables de la jornada.');
    }
    if (data.any(
      (m) =>
          eligible(m) &&
          !m.hasResult &&
          !m.unavailable &&
          (m.kickoff == null || !m.kickoff!.isAfter(DateTime.now())),
    )) {
      throw StateError(
        'Espera al final confirmado de los encuentros iniciados.',
      );
    }
    final legs = future(data).where((m) => selected.contains(m.id)).toList();
    if (legs.isEmpty || legs.length != selected.length || legs.length > 8) {
      throw StateError('Elige entre uno y ocho partidos futuros.');
    }
    for (var i = 0; i < legs.length; i++) {
      final m = legs[i];
      if (i > 0 &&
          m.kickoff!.difference(legs[i - 1].kickoff!) <
              const Duration(minutes: 120)) {
        throw StateError(
          'Hay partidos solapados: elige uno por grupo horario.',
        );
      }
      if (!RegExp(r'^1\.[0-9]{6,12}$').hasMatch(markets[m.id]!.text.trim()) ||
          !RegExp(r'^[1-9][0-9]{3,15}$').hasMatch(events[m.id]!.text.trim())) {
        throw StateError('Revisa MarketId y EventId de ${m.label}.');
      }
    }
    if (legs.last.kickoff!.difference(DateTime.now()) >
        const Duration(days: 4)) {
      throw StateError(
        'Esta prueba permite un horizonte máximo de cuatro días.',
      );
    }
    if (legs.map((m) => markets[m.id]!.text.trim()).toSet().length !=
            legs.length ||
        legs.map((m) => events[m.id]!.text.trim()).toSet().length !=
            legs.length) {
      throw StateError('Los identificadores de Betfair no pueden repetirse.');
    }
    return legs;
  }

  Future<void> authorize() async {
    if (busy || !confirmed) return;
    setState(() {
      busy = true;
      error = null;
    });
    var stage = 'actualizar calendario antes del resumen';
    try {
      final fresh = await widget.refresh();
      final legs = validate(fresh);
      final schedule = RoundAuthorization.fingerprint(fresh);
      final baseline = fresh.where((m) => m.hasResult).map((m) => m.id).toSet();
      final payload = jsonEncode(
        legs
            .map(
              (m) => [
                m.id,
                m.home,
                m.away,
                m.kickoff!.toUtc().toIso8601String(),
                markets[m.id]!.text.trim(),
                events[m.id]!.text.trim(),
              ],
            )
            .toList(),
      );
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Inicia sesión de nuevo.');
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            'Autorizar ronda REAL · máximo por apuesta 128 € · total 255 €',
          ),
          content: SingleChildScrollView(
            child: Text(
              '${widget.scope}\n\n${legs.asMap().entries.map((e) => '${1 << e.key} € · ${e.value.label}\n${e.value.kickoff!.toLocal()}\nMarketId ${markets[e.value.id]!.text.trim()} · EventId ${events[e.value.id]!.text.trim()}').join('\n\n')}\n\n'
              'BACK al empate · cuotas 2,80–20. Máximo ocho apuestas: 1 → 2 → 4 → 8 → 16 → 32 → 64 → 128 €. '
              'Máximo por apuesta: 128 €. Pérdida acumulada máxima: 255 €. Se para al aparecer un nuevo empate final o al ganar. '
              'Sólo se duplica tras una derrota completamente liquidada. Si no llega la liquidación a tiempo, se detiene. '
              'Se excluyen Real Madrid, Barcelona y Atlético de Madrid. Los finales ya existentes quedan fuera del nuevo inicio. '
              'El lunes continúa la misma jornada y el mismo presupuesto. Este OK es independiente del piloto de 1 €.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK · autorizar hasta 255 € REALES'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (FirebaseAuth.instance.currentUser?.uid != uid)
        throw StateError('Cambió la cuenta.');
      stage = 'actualizar calendario después del OK';
      final checked = await widget.refresh();
      validate(checked);
      final newBaseline = checked
          .where((m) => m.hasResult)
          .map((m) => m.id)
          .toSet();
      if (RoundAuthorization.fingerprint(checked) != schedule ||
          newBaseline.length != baseline.length ||
          !newBaseline.containsAll(baseline))
        throw StateError(
          'Cambió la jornada durante el OK. Actualiza y revisa.',
        );
      final id = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final target = command;
      final sim = FirebaseFirestore.instance
          .collection('PuenteJornada')
          .doc(uid);
      stage = 'iniciar transacción de autorización';
      await FirebaseFirestore.instance.runTransaction((tx) async {
        Future<DocumentSnapshot<Map<String, dynamic>>> read(
          DocumentReference<Map<String, dynamic>> ref,
        ) async {
          stage = 'leer ${ref.path}';
          return tx.get(ref);
        }

        final previous = await read(target), simulation = await read(sim);
        final simState = await read(sim.collection('Estado').doc('actual'));
        final oldRef = FirebaseFirestore.instance
            .collection('PuenteJornadaRondaReal')
            .doc(uid);
        final oldRound = await read(oldRef);
        final oldState = await read(oldRef.collection('Estado').doc('actual'));
        if (oldRound.exists &&
            oldRound.data()?['action'] != 'revoke' &&
            oldState.data()?['terminal'] != true) {
          throw StateError(
            'Revoca primero los siguientes envíos de la ronda anterior de 15 €.',
          );
        }
        final previousState = await read(
          target.collection('Estado').doc('actual'),
        );
        DocumentReference<Map<String, dynamic>>? archive;
        if (previous.exists) {
          final old = previous.data()!, state = previousState.data();
          if (replacingRequestId != old['requestId'] ||
              !canReplaceUnusedLiveRound(old, state)) {
            throw StateError(
              'Sólo puede sustituirse una ronda terminada sin ninguna orden reservada.',
            );
          }
          // No hace falta leer un archivo inexistente. La regla create-only
          // comprueba su unicidad al guardar el lote atómico.
          archive = target
              .collection('Archivo')
              .doc(old['requestId'] as String);
        } else if (replacingRequestId != null) {
          throw StateError('La ronda anterior cambió. Actualiza la pantalla.');
        }
        if (simulation.data()?['action'] == 'authorize' &&
            !(simState.data()?['requestId'] ==
                    simulation.data()?['requestId'] &&
                ['stopped', 'revoked'].contains(simState.data()?['status']))) {
          throw StateError(
            'Revoca primero el ensayo de simulación y espera la confirmación del PC.',
          );
        }
        stage = previous.exists
            ? 'guardar nuevo OK y archivo de la ronda anterior'
            : 'guardar primer OK de ronda';
        if (previous.exists) {
          tx.set(archive!, {
            'authorization': previous.data(),
            'state': previousState.data(),
            'archivedAt': FieldValue.serverTimestamp(),
          });
        }
        tx.set(target, {
          'schema': 1,
          'mode': 'live-round-128-v1',
          'requestId': id,
          'action': 'authorize',
          'scope': widget.scope,
          'approvedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(
            legs.last.kickoff!.subtract(const Duration(seconds: 60)).toUtc(),
          ),
          'currency': 'EUR',
          'budgetCents': 25500,
          'maxStakeCents': 12800,
          'maxBets': 8,
          'minPrice': 2.8,
          'maxPrice': 20,
          'excludeBigThree': true,
          'marketConfirmed': true,
          'fromNow': true,
          'schedule': schedule,
          'legs': payload,
          'baselineFinishedIds': baseline.toList(),
        });
      });
      if (mounted) setState(() => replacingRequestId = null);
    } on FirebaseException catch (e) {
      final project = FirebaseFirestore.instance.app.options.projectId;
      if (mounted) {
        setState(
          () => error =
              'No se completó la autorización. Etapa: $stage.\n'
              'Proyecto: $project · Código: ${e.code}.\n'
              '${e.message ?? "Firestore rechazó la operación."}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> prepareRemaining(Map<String, dynamic> previous) async {
    await reload();
    if (!mounted || error != null) return;
    try {
      // Conserva sólo identificadores del mismo partido y de la misma jornada.
      if (previous['scope'] == widget.scope) {
        final rows = jsonDecode(previous['legs'] as String) as List;
        for (final row in rows) {
          final r = row as List;
          if (r.length == 6 &&
              fixtures.any(
                (m) => m.id == r[0] && m.home == r[1] && m.away == r[2],
              )) {
            markets[r[0]]?.text = r[4] as String;
            events[r[0]]?.text = r[5] as String;
          }
        }
      }
      setState(() {
        replacingRequestId = previous['requestId'] as String;
        confirmed = false;
      });
    } catch (e) {
      setState(() => error = 'No se pudieron recuperar los IDs anteriores: $e');
    }
  }

  Future<void> revokePrevious() async {
    setState(() => busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('PuenteJornadaRondaReal')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({
            'action': 'revoke',
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke() async {
    setState(() => busy = true);
    try {
      await command.update({
        'action': 'revoke',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Ronda REAL · máximo por apuesta 128 € · total 255 €'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '1 → 2 → 4 → 8 → 16 → 32 → 64 → 128 € · hasta ocho apuestas. Sin Real Madrid, Barcelona ni Atlético de Madrid.',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'Elige un partido por grupo horario. Si son simultáneos, elige cuál antes del OK. El presupuesto continúa el lunes. Diagnóstico 0.7.4.',
        ),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('PuenteJornadaRondaReal')
              .doc(FirebaseAuth.instance.currentUser!.uid)
              .snapshots(),
          builder: (context, previous) {
            if (previous.hasError)
              return Text(
                'No se pudo consultar la ronda anterior: ${previous.error}',
              );
            final old = previous.data?.data();
            if (old == null || old['action'] == 'revoke')
              return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Existe una autorización anterior de 15 €. El nuevo límite requiere un OK separado. Revocar impide siguientes envíos; no cancela apuestas ya importadas.',
                ),
                TextButton(
                  onPressed: busy ? null : revokePrevious,
                  child: const Text(
                    'Revocar siguientes envíos de la ronda anterior de 15 €',
                  ),
                ),
              ],
            );
          },
        ),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: command.snapshots(),
          builder: (context, snap) {
            if (snap.hasError)
              return Text('No se pudo leer la ronda: ${snap.error}');
            if (!snap.hasData) return const LinearProgressIndicator();
            final d = snap.data!.data();
            if (d != null && replacingRequestId == null)
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Autorización guardada · ${d['scope']} · máximo por apuesta 128 € · total 255 €',
                  ),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: command
                        .collection('Estado')
                        .doc('actual')
                        .snapshots(),
                    builder: (context, state) {
                      if (state.hasError)
                        return Text('No se pudo leer el PC: ${state.error}');
                      final s = state.data?.data();
                      if (s == null || s['requestId'] != d['requestId'])
                        return const Text('Esperando confirmación del PC.');
                      final orders = (s['orders'] as List<dynamic>?) ?? [];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${s['message']}\nÚltima señal: ${s['lastSeenAt']}',
                          ),
                          if (canReplaceUnusedLiveRound(d, s))
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => prepareRemaining(d),
                              child: const Text(
                                'Preparar nueva ronda desde 1 € · partidos restantes',
                              ),
                            ),
                          ...orders.map(
                            (o) => ListTile(
                              title: Text(
                                '${o['matchId']} · ${(o['cents'] as num) / 100} €',
                              ),
                              subtitle: Text(
                                '${o['status']} · BetId ${o['betId'] ?? 'sin confirmar'}\n'
                                'Cuota ${o['odds'] ?? '—'} · Resultado € ${o['profitLossCents'] == null ? 'pendiente' : (o['profitLossCents'] as num) / 100}',
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  TextButton(
                    onPressed: busy ? null : revoke,
                    child: const Text('Revocar siguientes envíos'),
                  ),
                  const Text(
                    'Revocar o detener Windows no cancela apuestas ya importadas. Revisa lo pendiente en BF Bot Manager.',
                  ),
                ],
              );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (replacingRequestId != null) ...[
                  const Text(
                    'La ronda anterior no reservó apuestas. Se conservará en el historial al confirmar el nuevo OK. Empiezas desde 1 €.',
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => replacingRequestId = null),
                    child: const Text('Cancelar preparación'),
                  ),
                ],
                Text(widget.scope),
                if (future(fixtures).isEmpty)
                  const Text(
                    'No hay partidos futuros elegibles. Actualiza el calendario.',
                  ),
                ...future(fixtures).map(
                  (m) => Column(
                    children: [
                      CheckboxListTile(
                        value: selected.contains(m.id),
                        title: Text(m.label),
                        subtitle: Text('${m.kickoff!.toLocal()}'),
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                if (v == true && selected.length < 8) {
                                  selected.add(m.id);
                                } else {
                                  selected.remove(m.id);
                                }
                                confirmed = false;
                              }),
                      ),
                      if (selected.contains(m.id)) ...[
                        TextField(
                          controller: markets[m.id],
                          enabled: !busy,
                          decoration: const InputDecoration(
                            labelText: 'MarketId Betfair · Match Odds',
                          ),
                          onChanged: (_) => setState(() => confirmed = false),
                        ),
                        TextField(
                          controller: events[m.id],
                          enabled: !busy,
                          decoration: const InputDecoration(
                            labelText: 'EventId Betfair',
                          ),
                          onChanged: (_) => setState(() => confirmed = false),
                        ),
                      ],
                    ],
                  ),
                ),
                CheckboxListTile(
                  value: confirmed,
                  title: const Text(
                    'He comprobado los IDs de cada partido y mercado Match Odds, selección empate, y la cuenta en euros.',
                  ),
                  onChanged: busy
                      ? null
                      : (v) => setState(() => confirmed = v == true),
                ),
                FilledButton(
                  onPressed: busy || !confirmed || selected.isEmpty
                      ? null
                      : authorize,
                  child: const Text(
                    'Revisar OK REAL · máximo por apuesta 128 € · total 255 €',
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : reload,
                  child: const Text('Actualizar partidos'),
                ),
              ],
            );
          },
        ),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
      ],
    ),
  );
}
