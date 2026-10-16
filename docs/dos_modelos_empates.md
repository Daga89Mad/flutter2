# Fase 1: dos modelos de empate

- Modelo A: beta-logit previo; se conserva el campo `Probabilidad`.
- Modelo B: Poisson de goles locales/visitantes, con suavizado de 6 partidos y ajustes de fuerza experimentales.
- Campos nuevos para **pronósticos nuevos**: `ProbabilidadGoles`, `GolesEsperadosLocal`, `GolesEsperadosVisitante`, `FuerzaLocal`, `FuerzaVisitante`, `ModeloGoles`.
- Los registros antiguos se muestran con "Sin datos" en Modelo B: **nunca se reescriben**.
- Pantalla de fuerzas solo para cuentas con Firebase Auth custom claim `admin: true`. Este claim debe asignarlo un backend de confianza usando Admin SDK, nunca desde Flutter.
- Configuración en `ConfiguracionEmpates/{liga}/Equipos/{nombreExactoEquipo}`, con `Fuerza: -1, 0, 1`.
- Las etiquetas manuales desplazan ligeramente la relación de goles esperados, sin crear una penalización directa fija al empate.

## Firestore: CAMBIOS REQUERIDOS ANTES DE UTILIZAR

Las reglas previas de `PronosticosEmpates` usan `hasOnly` y `hasAll`: hay que añadir los **seis campos nuevos** a ambas listas, y validar en `datosPronosticoValidos`:

```javascript
&& d.ProbabilidadGoles is number
&& d.ProbabilidadGoles > 0
&& d.ProbabilidadGoles < 1
&& d.GolesEsperadosLocal is number
&& d.GolesEsperadosVisitante is number
&& d.FuerzaLocal is number
&& d.FuerzaVisitante is number
&& d.FuerzaLocal >= -1
&& d.FuerzaLocal <= 1
&& d.FuerzaVisitante >= -1
&& d.FuerzaVisitante <= 1
&& d.ModeloGoles == 'poisson-localia-v1'
```

Añadir match específico antes del comodín:

```javascript
match /ConfiguracionEmpates/{liga}/Equipos/{equipo} {
  allow read: if request.auth != null;
  allow create, update: if request.auth != null
    && request.auth.token.admin == true
    && liga in ['LaLiga', 'SerieA']
    && request.resource.data.keys().hasOnly(['Fuerza','ActualizadoEn'])
    && request.resource.data.keys().hasAll(['Fuerza','ActualizadoEn'])
    && request.resource.data.Fuerza in [-1,0,1]
    && request.resource.data.ActualizadoEn == request.time;
  allow delete: if false;
}
```

Y **excluir `ConfiguracionEmpates` de la regla comodín**, o esta protección sería inútil:

```javascript
&& !(collection in ['Apuestas', 'Traspasos', 'PronosticosEmpates', 'ConfiguracionEmpates'])
```

**Limitación de seguridad:** las predicciones se generan por el cliente y un usuario autenticado con permisos de creación aún podría proponer probabilidades arbitrarias. Para auditoría seria deben generarse en un backend confiable. No se debe tratar el campo de fuerza como una señal predictiva validada.

## Pruebas recomendadas

1. `flutter analyze` y compilación Android/iOS.
2. Administrador con claim: leer y guardar clasificaciones; usuario normal: no poder guardar.
3. Crear una jornada futura y comprobar A y B; revisar que Firestore autoriza los nuevos campos.
4. Confirmar que una jornada ya pronosticada no cambia tras modificar fuerzas.
5. Cargar resultados y comprobar checks verdes y cruces rojas, incluso tras jornadas aplazadas.
6. Validar modelo B fuera de muestra (Brier score y calibración) antes de usarlo como señal de apuesta.

**Nota:** los valores de goles base (1.40 local y 1.10 visitante) y el factor de fuerza 0.12 son hiperparámetros de arranque; deben calibrarse en datos históricos. No se presentan como pronósticos validados.
