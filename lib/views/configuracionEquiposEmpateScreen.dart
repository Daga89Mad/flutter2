import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Clasificación opcional compartida por usuarios autenticados.
class ConfiguracionEquiposEmpateScreen extends StatefulWidget {
  final String league;
  final String season;
  const ConfiguracionEquiposEmpateScreen({super.key,required this.league,required this.season});
  @override
  State<ConfiguracionEquiposEmpateScreen> createState()=>_ConfigState();
}
class _ConfigState extends State<ConfiguracionEquiposEmpateScreen> {
  bool loading=true; String? error;
  List<String> teams=[];
  Map<String,double> values={};
  CollectionReference<Map<String,dynamic>> get _col =>
    FirebaseFirestore.instance.collection('ConfiguracionEmpates')
      .doc(widget.league).collection('Equipos');
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    try {
      final all=<String>{};
      for(var r=1;r<=38;r++){
        final q=await FirebaseFirestore.instance.collection(widget.league)
          .doc('Resultados').collection('Temporadas').doc(widget.season)
          .collection('Jornadas').doc('$r').collection('Partidos').get();
        for(final d in q.docs){
          for(final field in ['Local','Visitante']){
            final name=d.data()[field]?.toString().trim()??'';
            if(name.isNotEmpty) all.add(name);
          }
        }
      }
      teams=all.toList()..sort();
      final docs=await _col.get();
      for(final d in docs.docs){
        final val=d.data()['Fuerza'];
        if(val is num) values[d.id]=val.toDouble();
      }
    }catch(e){error='No se ha podido cargar: $e';}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> _save(String team,double strength)async{
    try {
      await _col.doc(team).set({'Fuerza':strength,'ActualizadoEn':FieldValue.serverTimestamp()});
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Clasificación guardada para futuros pronósticos')));
    }catch(e){if(mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text('No se pudo guardar: $e')));}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Fuerza de equipos')),
    body:loading?const Center(child:CircularProgressIndicator()):
      error!=null?Center(child:Text(error!)):
      ListView(children:[
        const Padding(padding:EdgeInsets.all(16),child:Text(
          'Ajuste experimental: débil (-1), normal (0) o fuerte (+1). '
          'Solo afecta a pronósticos generados después de guardar.')),
        ...teams.map((team)=>ListTile(
          title:Text(team),
          trailing:DropdownButton<double>(
            value:values[team]??0,
            items:const [
              DropdownMenuItem(value:-1,child:Text('Débil')),
              DropdownMenuItem(value:0,child:Text('Normal')),
              DropdownMenuItem(value:1,child:Text('Fuerte'))
            ],
            onChanged:(v){if(v==null)return;setState(()=>values[team]=v);_save(team,v);},
          ),
        )),
      ]),
  );
}
