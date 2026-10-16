# Modelo D — validación inicial

Entrenamiento: 760 partidos de LaLiga y Serie A 2024/25. Evaluación independiente: 760 partidos 2025/26.

| Modelo | Brier | Log-loss | Empates Top 20 | AUC |
|---|---:|---:|---:|---:|
| Base constante | 0.189101 | 0.565961 | 5 | 0.5000 |
| A | 0.188103 | 0.562734 | 4 | 0.5562 |
| B | 0.188281 | 0.563227 | 6 | 0.5318 |
| D | 0.187081 | 0.560377 | 7 | 0.5726 |
| Mercado sin margen | 0.185415 | 0.555525 | 5 | 0.5824 |

Variables: diferencia de puntos por partido; suma de promedios de goles local en casa y visitante fuera; racha 8+ en algún equipo. Los promedios requieren al menos cinco partidos previos, los específicos por localía al menos dos. Imputación mediana e indicadores de valores faltantes, estandarización y regresión logística C=0.2.

Advertencia: selección exploratoria de variables después de consultar patrones históricos: riesgo de sesgo de selección. Una temporada de entrenamiento y otra de evaluación son insuficientes para demostrar estabilidad. No sustituir todavía el Modelo B; conservar pronósticos existentes. El archivo Dart es una función pura aislada, NO está conectado a la interfaz o Firestore. Se requiere validación cronológica adicional, integración de puntos y goles por localía, reglas nuevas para el nuevo campo, y comprobación de compilación antes de usarlo.
