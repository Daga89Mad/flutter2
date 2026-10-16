import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:plantillalogin/core/goalDrawModel.dart';
import 'package:plantillalogin/core/drawModelC.dart';
import 'package:plantillalogin/core/drawModelD.dart';
import 'package:plantillalogin/views/backtestEmpatesScreen.dart';
import 'package:plantillalogin/views/configuracionEquiposEmpateScreen.dart';

/// Investigación independiente: no modifica apuestas ni resultados.
/// Las predicciones se congelan antes de conocerse ningún resultado de la jornada.
class ProbabilidadExperimentalScreen extends StatefulWidget {
  const ProbabilidadExperimentalScreen({super.key});
  @override
  State<ProbabilidadExperimentalScreen> createState() => _ProbabilidadExperimentalState();
}
class _TeamStats {
  int games = 0, draws = 0, streak = 0, points = 0;
  int homeGames = 0, homeGoals = 0, awayGames = 0, awayGoals = 0;
  void add({required bool draw, required bool home, required int scored, required int conceded}) {
    games++;
    if(draw){draws++;streak=0;points++;}
    else {streak++;if(scored>conceded)points+=3;}
    if(home){homeGames++;homeGoals+=scored;}
    else {awayGames++;awayGoals+=scored;}
  }
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
  double? get modelC => (data['ProbabilidadC'] as num?)?.toDouble();
  double? get modelD => (data['ProbabilidadD'] as num?)?.toDouble();
}
class _ProbabilidadExperimentalState extends State<ProbabilidadExperimentalScreen> {
  final _db = FirebaseFirestore.instance;
  String league = 'LaLiga';
  late final String season;
  int round = 1;
  bool loading = false;
  String? error;
  List<_Prediction> predictions = [];
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final year = now.month >= 7 ? now.year : now.year - 1;
    season = '$year-${year + 1}';
    _load();
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
            final hg = _score(m['GolesLocal'])!;
            final ag = _score(m['GolesVisitante'])!;
            (stats[home] ??= _TeamStats()).add(draw:draw,home:true,scored:hg,conceded:ag);
            (stats[away] ??= _TeamStats()).add(draw:draw,home:false,scored:ag,conceded:hg);
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
          final ppgDiff = a.games >= 5 && b.games >= 5
              ? ((a.points/a.games)-(b.points/b.games)).abs() : null;
          final combinedGoals = a.games >= 5 && b.games >= 5 &&
                  a.homeGames >= 2 && b.awayGames >= 2
              ? (a.homeGoals/a.homeGames)+(b.awayGoals/b.awayGames) : null;
          final modelD = DrawModelD.predict(
            pointsPerGameDifference:ppgDiff,
            combinedVenueScoringAverage:combinedGoals,
            eitherTeamEightWithoutDraw:a.streak>=8 || b.streak>=8);
          final modelC = DrawModelC.predict(
            home:goalStats[home] ?? TeamGoalStats(),
            away:goalStats[away] ?? TeamGoalStats(),
            homeStrength:strengths[home]??0,awayStrength:strengths[away]??0);
          batch.set(_saved(round).doc(doc.id), {
            'Local': home, 'Visitante': away, 'MatchId': doc.id,
            'Liga': league, 'Temporada': season, 'Jornada': round,
            'Probabilidad': probability,
            'ProbabilidadC': modelC, 'ModeloC': DrawModelC.version,
            'ProbabilidadD': modelD, 'ModeloD': DrawModelD.version,
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
      IconButton(
        icon: const Icon(Icons.query_stats),
        tooltip: 'Comparar jornadas anteriores',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BacktestEmpatesScreen(league: league, season: season),
        )),
      ),

      IconButton(icon:const Icon(Icons.admin_panel_settings),
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
              subtitle: Text('A: ${(p.probability*100).toStringAsFixed(1)} % · D: ${p.modelD==null ? '—' : '${(p.modelD!*100).toStringAsFixed(1)} %'} · C: ${p.modelC==null ? '—' : '${(p.modelC!*100).toStringAsFixed(1)} %'}'),
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

  String _percent(num? value) =>
      value == null ? 'Sin datos' : '${(value * 100).toStringAsFixed(1)} %';

  Widget _item(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
      const SizedBox(width: 8),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 9),
            ...children,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final d = p.data;
    final b = p.goalProbability;
    final result = p.reviewed
        ? (p.hit ? 'Empate acertado' : 'No hubo empate')
        : 'Partido pendiente';
    final statusColor = p.reviewed
        ? (p.hit ? Colors.green : Colors.red)
        : Colors.blueGrey;

    return Scaffold(
      appBar: AppBar(title: const Text('Análisis del empate')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              Text('${p.home}  vs  ${p.away}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(p.reviewed
                    ? (p.hit ? Icons.check_circle : Icons.cancel)
                    : Icons.schedule, color: statusColor),
                const SizedBox(width: 8),
                Text(result, style: TextStyle(color: statusColor,
                    fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
        ),
        _section(context, 'Probabilidades de empate', [
          _item('A · Empates históricos', _percent(p.probability)),
          _item('D · Factores del partido', _percent(p.modelD)),
          _item('C · Dixon-Coles (provisional)', _percent(p.modelC)),
          _item('Cuota teórica A', (1/p.probability).toStringAsFixed(2)),
          if(p.modelD!=null) _item('Cuota teórica D', (1/p.modelD!).toStringAsFixed(2)),
          if(p.modelC!=null) _item('Cuota teórica C', (1/p.modelC!).toStringAsFixed(2)),
          if(p.modelD==null || p.modelC==null)
            const Text('Los modelos nuevos no existían cuando se guardó este pronóstico.'),
        ]),
        _section(context, 'Historial antes del partido', [
          Text(p.home, style: const TextStyle(fontWeight: FontWeight.bold)),
          _item('Empates / encuentros',
              '${d['EmpatesLocal']} / ${d['PartidosLocal']}'),
          _item('Partidos seguidos sin empatar', '${d['RachaLocal']}'),
          _item('Tendencia estimada', _percent(d['ProbabilidadLocal'] as num?)),
          const Divider(),
          Text(p.away, style: const TextStyle(fontWeight: FontWeight.bold)),
          _item('Empates / encuentros',
              '${d['EmpatesVisitante']} / ${d['PartidosVisitante']}'),
          _item('Partidos seguidos sin empatar', '${d['RachaVisitante']}'),
          _item('Tendencia estimada',
              _percent(d['ProbabilidadVisitante'] as num?)),
        ]),
        _section(context, 'Versiones y método', [
          _item('Modelo A', '${d['Modelo']??'beta-logit-v1'}'),
          _item('Modelo D', '${d['ModeloD']??'Sin datos'}'),
          _item('Modelo C', '${d['ModeloC']??'Sin datos'}'),
          const Text('D usa diferencia de puntos, goles y rachas. C ajusta marcadores de pocos goles; sus parámetros son todavía provisionales. Las versiones identifican exactamente qué fórmula generó cada pronóstico.'),
        ]),
      ]),
    );
  }
}
