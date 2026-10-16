import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:plantillalogin/core/goalDrawModel.dart';

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
class _DrawStats {int played=0,draws=0;}
class _Forecast {
 final int round;final String home,away;
 final double a,b;final bool draw;
 const _Forecast(this.round,this.home,this.away,this.a,this.b,this.draw);
}
class _BacktestState extends State<BacktestEmpatesScreen> {
 bool loading=false;
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
       final snap=await FirebaseFirestore.instance.collection(widget.league)
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
         final modelB=GoalDrawModel.predict(
           home:goals[home]??TeamGoalStats(),
           away:goals[away]??TeamGoalStats(),
         ).probability;
         output.add(_Forecast(j,home,away,modelA,modelB,hg==ag));
       }
       // Now learn results, only for the NEXT round.
       for(final m in games){
         final hg=_score(m['GolesLocal']),ag=_score(m['GolesVisitante']);
         if(hg==null||ag==null)continue;
         final home='${m['Local']??''}'.trim(),away='${m['Visitante']??''}'.trim();
         if(home.isEmpty||away.isEmpty)continue;
         for(final name in [home,away]){
           final x=team.putIfAbsent(name,()=>_DrawStats());
           x.played++;
           if(hg==ag)x.draws++;
         }
         (goals[home]??=TeamGoalStats()).add(home:true,scored:hg,conceded:ag);
         (goals[away]??=TeamGoalStats()).add(home:false,scored:ag,conceded:hg);
       }
     }
     if(mounted)setState(()=>samples=output);
   }catch(e){if(mounted)setState(()=>error='$e');}
   finally{if(mounted)setState(()=>loading=false);}
 }
 @override void initState(){super.initState();_calculate();}
 double _brier(bool a)=>samples.isEmpty?0:samples.fold<double>(0,(sum,p){
   final prob=a?p.a:p.b;return sum+math.pow(prob-(p.draw?1:0),2);
 })/samples.length;
 int _topDraws(bool a,int count){
   final sorted=[...samples]..sort((x,y)=>(a?y.a:y.b).compareTo(a?x.a:x.b));
   return sorted.take(count).where((x)=>x.draw).length;
 }
 @override Widget build(BuildContext context){
   final sorted=[...samples]..sort((x,y)=>y.a.compareTo(x.a));
   final count=math.min(20,samples.length);
   return Scaffold(appBar:AppBar(title:const Text('Backtest histórico')),
     body:loading?const Center(child:CircularProgressIndicator()):
      error!=null?Center(child:Text('Error leyendo Firebase: $error')):
       ListView(padding:const EdgeInsets.all(12),children:[
         Text('${widget.league} · ${widget.season}',style:Theme.of(context).textTheme.titleLarge),
         const SizedBox(height:8),
         const Text('Simulación retrospectiva. Cada jornada usa solo los resultados de jornadas anteriores. No son pronósticos registrados antes del partido.'),
         const SizedBox(height:12),
         Text('Partidos con marcador: ${samples.length} · Empates: ${samples.where((p)=>p.draw).length}'),
         Text('Brier A: ${_brier(true).toStringAsFixed(4)} · Brier B: ${_brier(false).toStringAsFixed(4)}'),
         Text('Top $count por A: ${_topDraws(true,count)} empates · Top $count por B: ${_topDraws(false,count)} empates'),
         const Divider(),
         const Text('Partidos ordenados por probabilidad del Modelo A'),
         ...sorted.map((p)=>Card(child:ListTile(
           title:Text('J${p.round} · ${p.home} – ${p.away}'),
           subtitle:Text('A ${(p.a*100).toStringAsFixed(1)} % · B ${(p.b*100).toStringAsFixed(1)} %'),
           trailing:Icon(p.draw?Icons.check_circle:Icons.cancel,
             color:p.draw?Colors.green:Colors.red),
         ))),
       ]),
   );
 }
}
