import 'dart:math';

import 'apuestaJornadaRondaRealScreen.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:plantillalogin/core/roundAuthorization.dart';
import 'package:plantillalogin/core/roundBetting.dart';

/// Piloto de UNA orden. No reutiliza ni convierte autorizaciones de simulación.
class ApuestaJornadaRealScreen extends StatefulWidget {
  final String scope;
  final Future<List<RoundFixture>> Function() refresh;
  const ApuestaJornadaRealScreen({
    super.key,
    required this.scope,
    required this.refresh,
  });
  @override
  State<ApuestaJornadaRealScreen> createState() => _RealState();
}

class _RealState extends State<ApuestaJornadaRealScreen> {
  final market = TextEditingController(), event = TextEditingController();
  List<RoundFixture> fixtures = [];
  String? selected, error;
  bool busy = false, confirmed = false, fromNow = false;
  DocumentReference<Map<String, dynamic>> get command => FirebaseFirestore
      .instance
      .collection('PuenteJornadaReal')
      .doc(FirebaseAuth.instance.currentUser!.uid);
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    market.dispose();
    event.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.refresh();
      if (mounted)
        setState(() {
          fixtures = value;
          selected = null;
          confirmed = false;
        });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<RoundFixture> candidates(List<RoundFixture> data) {
    final now = DateTime.now();
    if (data.length != 10 ||
        data.any(
          (m) =>
              !m.hasResult &&
              !m.unavailable &&
              (m.kickoff == null || !m.kickoff!.isAfter(now)),
        ))
      return [];
    final groups = RoundAuthorization.groups(
      data
          .where(
            (m) => !excludedRoundTeam(m.home) && !excludedRoundTeam(m.away),
          )
          .toList(),
      now,
    );
    return groups.isEmpty
        ? []
        : groups.first
              .where(
                (m) => m.kickoff!.isAfter(now.add(const Duration(seconds: 60))),
              )
              .toList();
  }

  Future<void> authorize() async {
    if (busy || !confirmed || selected == null) return;
    setState(() => busy = true);
    try {
      final fresh = await widget.refresh();
      final chosen = candidates(fresh)
          .where((m) => m.id == selected)
          .firstOrNull;
      if (chosen == null || (!fromNow && fresh.any((m) => m.draw)))
        throw StateError(
          'Actualiza: falta un partido futuro válido o la jornada ya tiene un empate.',
        );
      if (!RegExp(r'^1\.[0-9]{6,12}$').hasMatch(market.text.trim()) ||
          !RegExp(r'^[1-9][0-9]{3,15}$').hasMatch(event.text.trim()))
        throw StateError('Introduce MarketId y EventId exactos de Betfair.');
      final excluded = fromNow
          ? fresh.where((m) => m.hasResult).map((m) => m.id).toSet()
          : <String>{};
      final snapshot = RoundAuthorization.fingerprint(fresh);
      final marketId = market.text.trim(), eventId = event.text.trim();
      final ownerUid = FirebaseAuth.instance.currentUser?.uid;
      if (ownerUid == null) throw StateError('Inicia sesión de nuevo.');
      final target = command;
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Autorizar 1 € REAL'),
          content: SingleChildScrollView(
            child: Text(
              '${widget.scope}\n${chosen.label}\n${chosen.kickoff!.toLocal()}\n\nBACK al EMPATE · 1 €\nCuota mínima 2,80 · máxima 20\nPresupuesto total de esta prueba: 1 €\nMarketId: $marketId\nEventId: $eventId\n\n${fromNow ? 'Se excluyen los partidos ya finalizados:\n${fresh.where((m) => excluded.contains(m.id)).map((m) => '${m.label}: ${m.homeGoals}-${m.awayGoals}').join('\n')}\n\n' : ''}Este OK permite publicar una orden para BF Bot Manager en modo REAL. No habrá progresión ni una segunda orden automática. Enviado no equivale a ejecutado. Después del envío, la cancelación debe comprobarse en BF Bot Manager.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('OK · autorizar 1 € REAL'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (FirebaseAuth.instance.currentUser?.uid != ownerUid)
        throw StateError('Cambió la cuenta durante el OK.');
      final verified = await widget.refresh();
      final newBaseline = fromNow
          ? verified.where((m) => m.hasResult).map((m) => m.id).toSet()
          : <String>{};
      if (RoundAuthorization.fingerprint(verified) != snapshot ||
          newBaseline.length != excluded.length ||
          !newBaseline.containsAll(excluded) ||
          !candidates(verified).any((m) => m.id == chosen.id) ||
          (!fromNow && verified.any((m) => m.draw)))
        throw StateError(
          'Cambió el calendario o un resultado. Revisa y da un nuevo OK.',
        );
      final id = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final db = FirebaseFirestore.instance;
      final sim = db.collection('PuenteJornada').doc(ownerUid);
      await db.runTransaction((tx) async {
        final existing = await tx.get(target);
        final prior = await tx.get(sim);
        final state = await tx.get(sim.collection('Estado').doc('actual'));
        if (existing.exists)
          throw StateError(
            'Ya existe la prueba real de esta cuenta. No se permite otra orden hasta reconciliar la primera.',
          );
        if (prior.data()?['action'] == 'authorize' &&
            !(state.data()?['requestId'] == prior.data()?['requestId'] &&
                ['stopped', 'revoked'].contains(state.data()?['status'])))
          throw StateError(
            'Revoca primero el ensayo de simulación y espera la confirmación del PC.',
          );
        tx.set(target, {
          'schema': 1,
          'mode': 'live-pilot',
          'requestId': id,
          'action': 'authorize',
          'scope': widget.scope,
          'matchId': chosen.id,
          'home': chosen.home,
          'away': chosen.away,
          'kickoff': Timestamp.fromDate(chosen.kickoff!.toUtc()),
          'approvedAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(
            chosen.kickoff!.subtract(const Duration(seconds: 60)).toUtc(),
          ),
          'updatedAt': FieldValue.serverTimestamp(),
          'currency': 'EUR',
          'stakeCents': 100,
          'budgetCents': 100,
          'minPrice': 2.8,
          'maxPrice': 20,
          'betType': 'BACK',
          'selectionId': '58805',
          'marketId': marketId,
          'eventId': eventId,
          'marketConfirmed': true,
          'schedule': snapshot,
          'fromNow': fromNow,
          'baselineFinishedIds': excluded.toList(),
        });
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
    appBar: AppBar(title: const Text('Prueba REAL · máximo 1 €')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton(
          onPressed: busy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ApuestaJornadaRondaRealScreen(
                      scope: widget.scope,
                      refresh: widget.refresh,
                    ),
                  ),
                ),
          child: const Text('Ronda REAL · máximo por apuesta 128 € · total 255 €'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Una sola orden BACK al empate. No activa la martingala real ni convierte los ensayos anteriores.',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: command.snapshots(),
          builder: (context, snap) {
            if (snap.hasError)
              return Text(
                'No se pudo consultar la autorización real: ${snap.error}',
              );
            if (!snap.hasData) return const LinearProgressIndicator();
            final data = snap.data!.data();
            if (data != null)
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OK REAL guardado: ${data['home']} — ${data['away']} · 1 €',
                  ),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: command
                        .collection('Estado')
                        .doc('actual')
                        .snapshots(),
                    builder: (context, state) {
                      if (state.hasError)
                        return Text('No se pudo leer el PC: ${state.error}');
                      final d = state.data?.data();
                      return Text(
                        d?['requestId'] == data['requestId']
                            ? 'PC: ${d?['message']}\nÚltima señal: ${d?['lastSeenAt']}'
                            : 'Esperando confirmación del PC. Todavía no hay confirmación de envío.',
                      );
                    },
                  ),
                  TextButton(
                    onPressed: busy ? null : revoke,
                    child: const Text('Revocar envío pendiente'),
                  ),
                  const Text(
                    'Si ya se envió o importó: pausa la estrategia y revisa/cancela las apuestas pendientes en BF Bot Manager. La app no confirma una cancelación en Betfair.',
                  ),
                ],
              );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.scope),
                SwitchListTile(
                  title: const Text(
                    'Empezar desde ahora · excluir finales anteriores',
                  ),
                  value: fromNow,
                  onChanged: busy ? null : (v) => setState(() => fromNow = v),
                ),
                if (candidates(fixtures).isEmpty)
                  const Text(
                    'Espera los finales de los partidos iniciados o actualiza el calendario.',
                  ),
                ...candidates(fixtures).map(
                  (m) => RadioListTile<String>(
                    title: Text(m.label),
                    subtitle: Text('${m.kickoff!.toLocal()}'),
                    value: m.id,
                    groupValue: selected,
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            selected = v;
                            confirmed = false;
                          }),
                  ),
                ),
                TextField(
                  controller: market,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText:
                        'MarketId Betfair · mercado de resultado del partido',
                  ),
                  onChanged: (_) => setState(() => confirmed = false),
                ),
                TextField(
                  controller: event,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'EventId Betfair',
                  ),
                  onChanged: (_) => setState(() => confirmed = false),
                ),
                CheckboxListTile(
                  value: confirmed,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => confirmed = v == true),
                  title: const Text(
                    'He comprobado en Betfair que los IDs son de este partido, mercado Match Odds, selección empate, y que mi cuenta está en euros.',
                  ),
                ),
                FilledButton(
                  onPressed: busy || !confirmed || selected == null
                      ? null
                      : authorize,
                  child: const Text('Revisar OK REAL · 1 €'),
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
