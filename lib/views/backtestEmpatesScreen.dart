import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:plantillalogin/core/goalDrawModel.dart';
import 'package:plantillalogin/core/drawModelC.dart';
import 'package:plantillalogin/core/drawModelD.dart';

/// Backtest exploratorio, nunca se escriben apuestas ni pronósticos.
/// En cada jornada solo se usan marcadores de jornadas anteriores.
/// No hay información fiable de fecha para partidos aplazados: se ignoran
/// cronologías reales dentro de una jornada y se usa el número de jornada.
class BacktestEmpatesScreen extends StatefulWidget {
  final String league;
  final String season;
  const BacktestEmpatesScreen({super.key,required this.league,required this.season});
  @override
  State<BacktestEmpatesScreen> createState()=>_BacktestState();
}
class _DrawStats {int played=0,draws=0,streak=0,points=0,homeGames=0,awayGames=0,homeGoals=0,awayGoals=0;}
class _Forecast {
 final int round;final String home,away;
 final double a,d,c;final bool draw;
 const _Forecast(this.round,this.home,this.away,this.a,this.d,this.c,this.draw);
 double prob(String model)=>model=='D'?d:model=='C'?c:a;
}
class _BacktestState extends State<BacktestEmpatesScreen> {
 bool loading=false;
 late String selectedLeague;
 String selectedModel='A';
 double threshold=31;
 String? error;
 int? maxRound;
 List<_Forecast> samples=[];
 int? _score(dynamic raw)=>int.tryParse('${raw??''}');
 Future<void> _calculate() async {
   if(loading)return;
   setState(() {loading=true;error=null;samples=[];});
   try {
     final rounds=<int,List<Map<String,dynamic>>>{};
     for(var j=1;j<=38;j++){
       final snap=await FirebaseFirestore.instance.collection(selectedLeague)
         .doc('Resultados').collection('Temporadas').doc(widget.season)
         .collection('Jornadas').doc('$j').collection('Partidos').get();
       rounds[j]=snap.docs.map((d)=>d.data()).toList();
     }
     final team=<String,_DrawStats>{};
     final goals=<String,TeamGoalStats>{};
     final output=<_Forecast>[];
     const prior=.27,k=12.0;
     double logit(double p)=>math.log(p/(1-p));
     for(var j=1;j<=38;j++){
       final games=rounds[j]!;
       // Predict from accumulated history BEFORE incorporating this round.
       for(final m in games){
         final hg=_score(m['GolesLocal']),ag=_score(m['GolesVisitante']);
         if(hg==null||ag==null)continue; // no real result available yet
         final home='${m['Local']??''}'.trim();
         final away='${m['Visitante']??''}'.trim();
         if(home.isEmpty||away.isEmpty)continue;
         final h=team[home]??_DrawStats(),a=team[away]??_DrawStats();
         final ph=(h.draws+k*prior)/(h.played+k);
         final pa=(a.draws+k*prior)/(a.played+k);
         final z=logit(prior)+.5*(logit(ph)-logit(prior))+
             .5*(logit(pa)-logit(prior));
         final modelA=1/(1+math.exp(-z));
         final ppg=h.played>=5&&a.played>=5
           ? ((h.points/h.played)-(a.points/a.played)).abs():null;
         final scoring=h.played>=5&&a.played>=5&&h.homeGames>=2&&a.awayGames>=2
           ? h.homeGoals/h.homeGames+a.awayGoals/a.awayGames:null;
         final modelD=DrawModelD.predict(pointsPerGameDifference:ppg,
           combinedVenueScoringAverage:scoring,
           eitherTeamEightWithoutDraw:h.streak>=8||a.streak>=8);
         final modelC=DrawModelC.predict(
           home:goals[home]??TeamGoalStats(),away:goals[away]??TeamGoalStats());
         output.add(_Forecast(j,home,away,modelA,modelD,modelC,hg==ag));
       }
       // Now learn results, only for the NEXT round.
       for(final m in games){
         final hg=_score(m['GolesLocal']),ag=_score(m['GolesVisitante']);
         if(hg==null||ag==null)continue;
         final home='${m['Local']??''}'.trim(),away='${m['Visitante']??''}'.trim();
         if(home.isEmpty||away.isEmpty)continue;
         for(final name in [home,away]){
           final x=team.putIfAbsent(name,()=>_DrawStats());
           final local=name==home;
           final scored=local?hg:ag,conceded=local?ag:hg;
           x.played++;
           if(hg==ag){x.draws++;x.points++;x.streak=0;}
           else{x.streak++;if(scored>conceded)x.points+=3;}
           if(local){x.homeGames++;x.homeGoals+=scored;}
           else{x.awayGames++;x.awayGoals+=scored;}
         }
         (goals[home]??=TeamGoalStats()).add(home:true,scored:hg,conceded:ag);
         (goals[away]??=TeamGoalStats()).add(home:false,scored:ag,conceded:hg);
       }
     }
     if(mounted)setState(()=>samples=output);
   }catch(e){if(mounted)setState(()=>error='$e');}
   finally{if(mounted)setState(()=>loading=false);}
 }
 @override void initState(){super.initState();selectedLeague=widget.league;_calculate();}
 double _brier(String model)=>samples.isEmpty?0:samples.fold<double>(0,(sum,p){
   final prob=p.prob(model);return sum+math.pow(prob-(p.draw?1:0),2);
 })/samples.length;
 int _topDraws(String model,int count){
   final sorted=[...samples]..sort((x,y)=>y.prob(model).compareTo(x.prob(model)));
   return sorted.take(count).where((x)=>x.draw).length;
 }
  Widget _thresholdReport() {
    final cut=threshold/100;
    Widget rowFor(String model) {
      final selected=samples.where((p)=>p.prob(model)>cut).toList();
      final wins=selected.where((p)=>p.draw).length;
      final losses=selected.length-wins;
      final failure=selected.isEmpty?'—':'${(100*losses/selected.length).toStringAsFixed(1)} %';
      final actual=selected.isEmpty?'—':'${(100*wins/selected.length).toStringAsFixed(1)} %';
      final expected=selected.isEmpty?'—':'${(100*selected.fold<double>(0,(sum,p)=>sum+p.prob(model))/selected.length).toStringAsFixed(1)} %';
      return Padding(padding:const EdgeInsets.symmetric(vertical:7),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Modelo $model',style:const TextStyle(fontWeight:FontWeight.bold)),
          Text('Seleccionados: ${selected.length} · Empates: $wins · Fallos: $losses'),
          Text('Fallos: $failure · Empates reales: $actual · Predicción media: $expected'),
        ],
      ));
    }
    return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Falsas alarmas · Probabilidad mayor del ${threshold.toStringAsFixed(0)} %',
          style:const TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        DropdownButtonFormField<double>(
          value:threshold,
          decoration:const InputDecoration(labelText:'Umbral mínimo (estrictamente mayor)'),
          items:const [25.0,28.0,30.0,31.0,32.0,33.0,35.0,40.0]
            .map((v)=>DropdownMenuItem<double>(value:v,child:Text('${v.toStringAsFixed(0)} %')))
            .toList(),
          onChanged:(v){if(v!=null)setState(()=>threshold=v);},
        ),
        rowFor('A'),const Divider(height:8),rowFor('D'),
        const Divider(height:8),rowFor('C'),
        const Text('Solo partidos con resultado. Un 32,7 % repetido al principio puede proceder de valores predeterminados del Modelo D. La tasa de fallos no mide por sí sola la calidad de probabilidades.',
          style:TextStyle(fontSize:12)),
      ],
    )));
  }
 @override Widget build(BuildContext context){
   final rounds=samples.map((e)=>e.round).toSet().toList()..sort();
   final count=math.min(20,samples.length);
   return Scaffold(appBar:AppBar(title:const Text('Backtest histórico')),
     body:Column(children:[
       Padding(padding:const EdgeInsets.all(12),child:Column(children:[
         DropdownButtonFormField<String>(
           value:selectedLeague,
           decoration:const InputDecoration(labelText:'Liga'),
           items:const [
             DropdownMenuItem(value:'LaLiga',child:Text('España · LaLiga')),
             DropdownMenuItem(value:'SerieA',child:Text('Italia · Serie A')),
           ],
           onChanged:loading?null:(v){if(v!=null&&v!=selectedLeague){
             setState(()=>selectedLeague=v);_calculate();
           }},
         ),
         const SizedBox(height:8),
         DropdownButtonFormField<String>(
           value:selectedModel,decoration:const InputDecoration(labelText:'Ordenar cada jornada por'),
           items:const [
             DropdownMenuItem(value:'A',child:Text('Modelo A')),
             DropdownMenuItem(value:'D',child:Text('Modelo D')),
             DropdownMenuItem(value:'C',child:Text('Modelo C (provisional)')),
           ],
           onChanged:(v){if(v!=null)setState(()=>selectedModel=v);},
         ),
       ])),
       if(loading)const LinearProgressIndicator(),
       if(error!=null)Text('Error leyendo Firebase: $error'),
       if(!loading&&error==null)Expanded(child:ListView(
         padding:const EdgeInsets.all(12),children:[
           Text('${widget.season} · ${samples.length} partidos'),
           Text('Brier A: ${_brier("A").toStringAsFixed(4)} · D: ${_brier("D").toStringAsFixed(4)} · C: ${_brier("C").toStringAsFixed(4)}'),
           Text('Top $count: A ${_topDraws("A",count)} · D ${_topDraws("D",count)} · C ${_topDraws("C",count)} empates'),
           _thresholdReport(),
           const Padding(padding:EdgeInsets.symmetric(vertical:10),child:Text(
             'Backtest retrospectivo por jornada. Los aplazamientos pueden alterar la cronología real. Modelo C con parámetros provisionales.')),
           ...rounds.map((r){
             final games=samples.where((e)=>e.round==r).toList()
               ..sort((x,y)=>y.prob(selectedModel).compareTo(x.prob(selectedModel)));
             return Card(child:ExpansionTile(
               initiallyExpanded:r==rounds.last,
               title:Text('Jornada $r'),
               subtitle:Text('${games.length} partidos · ${games.where((m)=>m.draw).length} empates'),
               children:games.map((p)=>ListTile(
                 title:Text('${p.home} – ${p.away}'),
                 subtitle:Text('A ${(p.a*100).toStringAsFixed(1)} % · D ${(p.d*100).toStringAsFixed(1)} % · C ${(p.c*100).toStringAsFixed(1)} %'),
                 trailing:Icon(p.draw?Icons.check_circle:Icons.cancel,
                   color:p.draw?Colors.green:Colors.red),
               )).toList(),
             ));
           }),
         ],
       )),
     ]),
   );
 }
}
