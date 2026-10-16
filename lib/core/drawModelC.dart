import 'dart:math' as math;
import 'package:plantillalogin/core/goalDrawModel.dart';

/// Dixon-Coles experimental. rho=-0.08 is a provisional assumption, NOT fitted.
/// Keep independent version identifiers until backtests validate a learned rho.
class DrawModelC {
  static const version = 'dixon-coles-provisional-v0';
  static const rho = -0.08;
  static double _pmf(int k,double lambda) {
    double fact=1;
    for(var i=2;i<=k;i++) fact*=i;
    return math.exp(-lambda)*math.pow(lambda,k)/fact;
  }
  static double predict({required TeamGoalStats home,required TeamGoalStats away,
      double homeStrength=0,double awayStrength=0}) {
    final base=GoalDrawModel.predict(home:home,away:away,
      homeStrength:homeStrength,awayStrength:awayStrength);
    final x=base.goalsHome,y=base.goalsAway;
    double draw=0,total=0;
    for(var h=0;h<=12;h++) {
      for(var a=0;a<=12;a++) {
        var adjust=1.0;
        if(h==0 && a==0) adjust=1-x*y*rho;
        if(h==0 && a==1) adjust=1+x*rho;
        if(h==1 && a==0) adjust=1+y*rho;
        if(h==1 && a==1) adjust=1-rho;
        final mass=_pmf(h,x)*_pmf(a,y)*adjust;
        total+=mass;
        if(h==a) draw+=mass;
      }
    }
    return (draw/total).clamp(.001,.999).toDouble();
  }
}
