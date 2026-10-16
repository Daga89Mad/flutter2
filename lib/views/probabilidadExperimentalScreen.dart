import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:plantillalogin/core/goalDrawModel.dart';
import 'package:plantillalogin/views/configuracionEquiposEmpateScreen.dart';

/// Investigación independiente: no modifica apuestas ni resultados.
/// Las predicciones se congelan antes de conocerse ningún resultado de la jornada.
class ProbabilidadExperimentalScreen extends StatefulWidget {
  const ProbabilidadExperimentalScreen({super.key});
  @override
  State<ProbabilidadExperimentalScreen> createState() => _ProbabilidadExperimentalState();
}
class _TeamStats {
  int games = 0, draws = 0, streak = 0;
  void add(bool draw) { games++; if (draw) { draws++; streak = 0; } else { streak++; } }
}
class _Prediction {
  final Map<String, dynamic> data;
  _Prediction(this.data);
  String get home => '${data['Local']}';
  String get away => '${data['Visitante']}';
  double get probability => (data['Probabilidad'] as num).toDouble();
  bool get reviewed => data['Revisado'] == true;
  bool get hit => data['Acertado'] == true;
  double? get goalProbability => (data['ProbabilidadGoles'] as num?)?.toDouble();
}
class _ProbabilidadExperimentalState extends State<ProbabilidadExperimentalScreen> {
  final _db = FirebaseFirestore.instance;
  String league = 'LaLiga';
  late final String season;
  int round = 1;
  bool loading = false;
  String? error;
  List<_Prediction> predictions = [];
  bool isAdmin = false;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final year = now.month >= 7 ? now.year : now.year - 1;
    season = '$year-${year + 1}';
    _checkAdmin();
    _load();
  }
  Future<void> _checkAdmin() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult();
    if (mounted) setState(() => isAdmin = token?.claims?['admin'] == true);
  }
  CollectionReference<Map<String, dynamic>> _matches(int r) =>
      _db.collection(league).doc('Resultados').collection('Temporadas')
          .doc(season).collection('Jornadas').doc('$r').collection('Partidos');
  CollectionReference<Map<String, dynamic>> _saved(int r) =>
      _db.collection('PronosticosEmpates').doc(league).collection('Temporadas')
          .doc(season).collection('Jornadas').doc('$r').collection('Partidos');
  int? _score(dynamic raw) => int.tryParse('${raw ?? ''}');
  bool _finished(Map<String, dynamic> m) =>
      _score(m['GolesLocal']) != null && _score(m['GolesVisitante']) != null;

  Future<void> _reviewEarlier() async {
    for (var r = 1; r <= round; r++) {
      final recorded = await _saved(r).get();
      if (recorded.docs.isEmpty) continue;
      final results = await _matches(r).get();
      final actual = {for (final d in results.docs) d.id: d.data()};
      final batch = _db.batch();
      var changed = 0;
      for (final p in recorded.docs) {
        final match = actual[p.id];
        if (match == null || !_finished(match)) continue;
        final hit = _score(match['GolesLocal']) == _score(match['GolesVisitante']);
        if (p.data()['Revisado'] == true && p.data()['Acertado'] == hit) continue;
        batch.update(p.reference, {
          'Revisado': true, 'Acertado': hit,
          'RevisadoEn': FieldValue.serverTimestamp(),
        });
        changed++;
      }
      if (changed > 0) await batch.commit();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { loading = true; error = null; predictions = []; });
    try {
      await _reviewEarlier();
      final fixture = await _matches(round).get();
      if (fixture.docs.isEmpty) {
        if (mounted) setState(() => error = 'No hay partidos cargados para esta jornada.');
        return;
      }
      final already = await _saved(round).get();
      if (already.docs.isEmpty) {
        if (fixture.docs.any((m) => _finished(m.data()))) {
          if (mounted) setState(() => error =
              'Esta jornada ya tiene resultados. No se generan pronósticos retrospectivos.');
          return;
        }
        final stats = <String, _TeamStats>{};
        final goalStats = <String, TeamGoalStats>{};
        for (var r = 1; r < round; r++) {
          final old = await _matches(r).get();
          for (final match in old.docs) {
            final m = match.data();
            if (!_finished(m)) continue;
            final home = '${m['Local'] ?? ''}'.trim();
            final away = '${m['Visitante'] ?? ''}'.trim();
            if (home.isEmpty || away.isEmpty) continue;
            final draw = _score(m['GolesLocal']) == _score(m['GolesVisitante']);
            (stats[home] ??= _TeamStats()).add(draw);
            (stats[away] ??= _TeamStats()).add(draw);
            final hg = _score(m['GolesLocal'])!;
            final ag = _score(m['GolesVisitante'])!;
            (goalStats[home] ??= TeamGoalStats()).add(home:true,scored:hg,conceded:ag);
            (goalStats[away] ??= TeamGoalStats()).add(home:false,scored:ag,conceded:hg);
          }
        }
        final strengthDocs = await _db.collection('ConfiguracionEmpates')
          .doc(league).collection('Equipos').get();
        final strengths = <String,double>{
          for(final d in strengthDocs.docs)
            if(d.data()['Fuerza'] is num) d.id:(d.data()['Fuerza'] as num).toDouble()
        };
        const baseline = .27, strength = 12.0;
        double logit(double p) => math.log(p / (1 - p));
        final batch = _db.batch();
        for (final doc in fixture.docs) {
          final m = doc.data();
          final home = '${m['Local'] ?? ''}'.trim();
          final away = '${m['Visitante'] ?? ''}'.trim();
          if (home.isEmpty || away.isEmpty) continue;
          final a = stats[home] ?? _TeamStats();
          final b = stats[away] ?? _TeamStats();
          final pa = (a.draws + strength * baseline) / (a.games + strength);
          final pb = (b.draws + strength * baseline) / (b.games + strength);
          final logOdds = logit(baseline) +
              .5 * (logit(pa) - logit(baseline)) +
              .5 * (logit(pb) - logit(baseline));
          final probability = 1 / (1 + math.exp(-logOdds));
          final goalPrediction = GoalDrawModel.predict(
            home:goalStats[home] ?? TeamGoalStats(),
            away:goalStats[away] ?? TeamGoalStats(),
            homeStrength:strengths[home] ?? 0,
            awayStrength:strengths[away] ?? 0,
          );
          batch.set(_saved(round).doc(doc.id), {
            'Local': home, 'Visitante': away, 'MatchId': doc.id,
            'Liga': league, 'Temporada': season, 'Jornada': round,
            'Probabilidad': probability,
            'ProbabilidadGoles': goalPrediction.probability,
            'GolesEsperadosLocal': goalPrediction.goalsHome,
            'GolesEsperadosVisitante': goalPrediction.goalsAway,
            'FuerzaLocal': strengths[home] ?? 0,
            'FuerzaVisitante': strengths[away] ?? 0,
            'ModeloGoles': 'poisson-localia-v1',
            'ProbabilidadLocal': pa,
            'ProbabilidadVisitante': pb,
            'EmpatesLocal': a.draws, 'PartidosLocal': a.games,
            'RachaLocal': a.streak, 'EmpatesVisitante': b.draws,
            'PartidosVisitante': b.games, 'RachaVisitante': b.streak,
            'Revisado': false, 'Acertado': null,
            'Modelo': 'beta-logit-v1', 'GeneradoEn': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      final recorded = await _saved(round).get();
      final items = recorded.docs.map((d) => _Prediction(d.data())).toList()
        ..sort((a, b) => b.probability.compareTo(a.probability));
      if (mounted) setState(() => predictions = items);
    } catch (e) {
      if (mounted) setState(() => error = 'Error de Firestore: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Probabilidad experimental'), actions: [
      if(isAdmin) IconButton(icon:const Icon(Icons.admin_panel_settings),
        tooltip:'Clasificar equipos', onPressed:()=>Navigator.of(context).push(
          MaterialPageRoute(builder:(_)=>ConfiguracionEquiposEmpateScreen(league:league,season:season)))),
    ]),
    body: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            value: league,
            decoration: const InputDecoration(labelText: 'Liga'),
            items: const ['LaLiga','SerieA'].map((s) => DropdownMenuItem(
                value: s, child: Text(s == 'LaLiga' ? 'LaLiga' : 'Serie A'))).toList(),
            onChanged: loading ? null : (v) { if (v != null) { setState(() => league = v); _load(); } },
          )),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<int>(
            value: round,
            decoration: const InputDecoration(labelText: 'Jornada'),
            items: List.generate(38, (i) => DropdownMenuItem(
                value: i + 1, child: Text('${i + 1}'))),
            onChanged: loading ? null : (v) { if (v != null) { setState(() => round = v); _load(); } },
          )),
        ]),
        Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('Temporada $season · Estimación sin calibrar')),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Padding(
          padding: const EdgeInsets.all(12), child: Text(error!)),
        Expanded(child: ListView.builder(
          itemCount: predictions.length,
          itemBuilder: (context, i) {
            final p = predictions[i];
            return Card(child: ListTile(
              title: Text('${p.home} – ${p.away}'),
              subtitle: Text('Modelo A: ${(p.probability * 100).toStringAsFixed(1)} %  ·  Modelo B: ${p.goalProbability == null ? 'Sin datos' : '${(p.goalProbability! * 100).toStringAsFixed(1)} %'}'),
              trailing: p.reviewed ? Icon(p.hit ? Icons.check_circle : Icons.cancel,
                color: p.hit ? Colors.green : Colors.red) : const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _PredictionDetail(p))),
            ));
          },
        )),
      ]),
    ),
  );
}

class _PredictionDetail extends StatelessWidget {
  final _Prediction prediction;
  const _PredictionDetail(this.prediction);
  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final d = p.data;
    Widget metric(String label, Object? value) => ListTile(
      title: Text(label), trailing: Text('$value'));
    return Scaffold(
      appBar: AppBar(title: const Text('Análisis del empate')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${p.home} - ${p.away}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text('${(p.probability * 100).toStringAsFixed(1)} % de empate (experimental)',
          style: Theme.of(context).textTheme.headlineSmall),
        metric('Cuota teórica de equilibrio A', (1 / p.probability).toStringAsFixed(2)),
        metric('Modelo B · Poisson', p.goalProbability == null ? 'Sin datos' : '${(p.goalProbability! * 100).toStringAsFixed(1)} %'),
        if(p.goalProbability != null) metric('Cuota de equilibrio B', (1/p.goalProbability!).toStringAsFixed(2)),
        if(d['GolesEsperadosLocal'] is num) metric('Goles esperados local', (d['GolesEsperadosLocal'] as num).toStringAsFixed(2)),
        if(d['GolesEsperadosVisitante'] is num) metric('Goles esperados visitante', (d['GolesEsperadosVisitante'] as num).toStringAsFixed(2)),
        const Divider(),
        Text(p.home, style: Theme.of(context).textTheme.titleMedium),
        metric('Empates / partidos anteriores',
          '${d['EmpatesLocal']} / ${d['PartidosLocal']}'),
        metric('Racha previa sin empatar', d['RachaLocal']),
        metric('Probabilidad individual',
          '${((d['ProbabilidadLocal'] as num) * 100).toStringAsFixed(1)} %'),
        const Divider(),
        Text(p.away, style: Theme.of(context).textTheme.titleMedium),
        metric('Empates / partidos anteriores',
          '${d['EmpatesVisitante']} / ${d['PartidosVisitante']}'),
        metric('Racha previa sin empatar', d['RachaVisitante']),
        metric('Probabilidad individual',
          '${((d['ProbabilidadVisitante'] as num) * 100).toStringAsFixed(1)} %'),
        const Divider(),
        metric('Modelo', d['Modelo']),
        metric('Evaluación', p.reviewed
            ? (p.hit ? 'Acierto ✓' : 'Fallo ✕') : 'Pendiente'),
        const Text('Pronóstico orientativo. No presupone que una racha de fallos aumente la probabilidad.'),
      ]),
    );
  }
}
