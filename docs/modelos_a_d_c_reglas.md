# Migración para modelos A, D y C

No fusionar antes de configurar reglas y probar Flutter. La rama cambia el listado y detalle de probabilidad y agrupa el backtest por jornada ascendente; dentro de cada jornada se puede ordenar por A, D o C.

## Firestore
Pronósticos nuevos guardan cuatro campos nuevos:
- `ProbabilidadC`: double 0..1
- `ModeloC`: `dixon-coles-provisional-v0`
- `ProbabilidadD`: double 0..1
- `ModeloD`: `logistica-multivariable-v0`

En las reglas existentes:
1. Añadir los cuatro campos a la lista permitida `hasOnly` de `datosPronosticoValidos`. **No añadirlos al listado base obligatorio**, para preservar compatibilidad con pronósticos A y B antiguos.
2. Validar nuevos campos solo si aparecen, exigiendo que aparezcan los cuatro a la vez:

```javascript
function modelosCDValidos(d) {
  let nombres = ['ProbabilidadC','ModeloC','ProbabilidadD','ModeloD'];
  return !d.keys().hasAny(nombres) || (
    d.keys().hasAll(nombres)
    && d.ProbabilidadC is number
    && d.ProbabilidadC > 0 && d.ProbabilidadC < 1
    && d.ModeloC == 'dixon-coles-provisional-v0'
    && d.ProbabilidadD is number
    && d.ProbabilidadD > 0 && d.ProbabilidadD < 1
    && d.ModeloD == 'logistica-multivariable-v0'
  );
}
```

3. Añadir `&& modelosCDValidos(d)` al final de `datosPronosticoValidos`. Estos son cambios de creación solamente: las evaluaciones viejas no requieren actualizar campos.
4. Eliminar del UI *no implica borrar* el campo antiguo `ProbabilidadGoles`, que se sigue guardando internamente y permanece validado con las reglas anteriores.

## Limitaciones
- C usa rho=-0.08 **provisional, no entrenado**. No interpretar su porcentaje como validado.
- D importa parámetros estimados en 2024/25 y probados solo en 2025/26, con riesgo de sobreajuste.
- El backtest usa orden numérico de jornada, no fecha real: partidos aplazados pueden crear filtraciones cronológicas.
- Históricos anteriores se mantienen sin C/D, sin inferir predicciones que nunca existieron.
- Los porcentajes no prueban una estrategia de apuestas rentable.
- Deben ejecutarse flutter analyze, pruebas de emulador y reglas de Firebase antes de fusionar.
