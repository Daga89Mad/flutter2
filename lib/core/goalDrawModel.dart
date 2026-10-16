import 'dart:math' as math;

/// Modelo experimental Poisson: goles marcados/recibidos, localía y fuerza.
/// No utiliza resultados futuros. Ajustes deliberadamente conservadores.
class TeamGoalStats {
  int homeGames=0, awayGames=0;
  int scoredHome=0, concededHome=0, scoredAway=0, concededAway=0;
  void add({required bool home, required int scored, required int conceded}) {
    if(home) {homeGames++; scoredHome+=scored; concededHome+=conceded;}
    else {awayGames++; scoredAway+=scored; concededAway+=conceded;}
  }
}
class GoalPrediction {
  final double probability, goalsHome, goalsAway;
  const GoalPrediction(this.probability,this.goalsHome,this.goalsAway);
}
class GoalDrawModel {
  static const double priorGames=6;
  static double _avg(int goals,int matches,double fallback) =>
      (goals + priorGames*fallback)/(matches+priorGames);
  static double _poisson(int k,double lambda) {
    var fact=1.0;
    for(var i=2;i<=k;i++) {fact*=i;}
    return math.exp(-lambda)*math.pow(lambda,k)/fact;
  }
  static GoalPrediction predict({
    required TeamGoalStats home,required TeamGoalStats away,
    double homeStrength=0, double awayStrength=0,
    double leagueHomeGoals=1.40,double leagueAwayGoals=1.10,
  }) {
    final homeAttack=_avg(home.scoredHome,home.homeGames,leagueHomeGoals)/leagueHomeGoals;
    final awayDefense=_avg(away.concededAway,away.awayGames,leagueHomeGoals)/leagueHomeGoals;
    final awayAttack=_avg(away.scoredAway,away.awayGames,leagueAwayGoals)/leagueAwayGoals;
    final homeDefense=_avg(home.concededHome,home.homeGames,leagueAwayGoals)/leagueAwayGoals;
    // Fuerza opcional en escala -1..1. No asume que fuertes nunca empatan:
    // desplaza goles esperados en sentidos opuestos según la diferencia.
    final delta=(homeStrength-awayStrength).clamp(-2.0,2.0);
    final h=(leagueHomeGoals*homeAttack*awayDefense*math.exp(.12*delta)).clamp(.15,4.5);
    final a=(leagueAwayGoals*awayAttack*homeDefense*math.exp(-.12*delta)).clamp(.15,4.5);
    var p=0.0;
    for(var k=0;k<=12;k++) {p+=_poisson(k,h)*_poisson(k,a);}
    return GoalPrediction(p.clamp(.01,.85),h,a);
  }
}
