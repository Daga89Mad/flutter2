# Apuesta a jornada: autorización de jornada completa

## Alcance de esta fase

El menú abre `ApuestaJornadaScreen`, que lee LaLiga del Firestore existente,
incluyendo la ruta legacy de 2025-2026. Esta versión **solo simula**: no envía
órdenes a una casa, no consulta cuotas/saldo reales y no tiene credenciales.
El historial y el consentimiento se guardan localmente por usuario, temporada
y jornada. No se sincronizan entre dispositivos y no son contabilidad real.

El usuario ha elegido **un OK por jornada**, sustituyendo el OK por apuesta.
Ese consentimiento no se hereda a la jornada siguiente ni autoriza apuestas
fuera de los partidos, importe máximo y presupuesto mostrados.

## Flujo implementado

1. Cargar los diez partidos con sus horarios; sin calendario completo se bloquea
   la autorización. Para documentos antiguos, reimportar o completar horarios de
   ensayo. No se permite autorizar con partidos iniciados sin final confirmado.
2. Elegir exactamente un partido de cada grupo de horarios solapados. Los grupos
   con varias opciones nunca se eligen automáticamente. Los intervalos de 120
   minutos se usan solo para agrupar posibles solapes, no como prueba de final.
   Se agrupan transitivamente: si A solapa B y B solapa C, se elige uno del grupo.
3. Revisar presupuesto total, cuota mínima 2,80, máximo 256 € por apuesta y todas
   las elecciones. El presupuesto editable va de 1 a 511 €. Su valor inicial
   de 511 € corresponde a nueve derrotas de 1, 2, 4, ..., 256 €; se muestra antes
   del OK y no representa un depósito ni una recomendación de banca.
4. Introducir una cuota ficticia para el ensayo. Se aplica a toda esta sesión
   simulada; no procede de Betfair ni bet365 y no sirve para valorar rentabilidad.
5. Pulsar «OK · autorizar jornada». La revisión debe terminar en 60 segundos.
   Se relee el calendario del servidor y se revalidan empates/elecciones antes
   de guardar el consentimiento. No se coloca ninguna apuesta real.
6. Con la pantalla abierta, el ensayo evalúa la secuencia cada diez segundos y
   cuando Firestore cambia. Solo simula durante los cinco minutos previos al
   inicio del partido elegido, con relectura de servidor justo antes de guardar.
   No exige más OK dentro de esa jornada. Solo una apuesta puede estar pendiente.
7. Duplicar el importe únicamente tras una derrota final confirmada de una
   apuesta de la serie. Parar ante cualquier empate final de la jornada, incluso
   si no se apostó ese partido. No aumentar el siguiente importe si superaría
   el presupuesto acumulado ni el límite de 256 €.
8. «Detener jornada y revocar OK» elimina el consentimiento y conserva el
   historial. Un cambio de calendario, caducidad, empate o límite también revoca
   la autorización. Para volver a autorizar debe revisarse todo de nuevo.
9. La siguiente jornada comienza en 1 € sin arrastrar pérdidas ni autorización.

No hay trabajador en segundo plano: cerrar o cambiar la pantalla interrumpe el
ensayo. Al abrirla de nuevo se revalida la autorización guardada, sin simular
retroactivamente encuentros ya iniciados. Una apuesta simulada pendiente se
conserva y bloquea la siguiente hasta disponer de resultado final.
Mientras haya una autorización guardada, debe revocarse antes de cambiar jornada.

## Datos y resultados

El importador existente guarda `InicioUTC` (Timestamp), `Estado` y `Finalizado`.
Solo se interpreta un marcador cuando hay estado final explícito y ambos goles.
Un 0-0 en directo, `Empate: true` o el mero paso de 120 minutos no bastan.
Los resultados solo cambian si se reimportan o un proceso actualiza Firestore:
la suscripción no consulta por sí misma al proveedor deportivo.

Las reglas compartidas de `firestore.rules`, versión 2, permiten estos campos en
las rutas de resultados mediante su bloque general para usuarios autenticados.
Esto no acredita cuáles están desplegadas actualmente en Firebase ni convierte
esos datos editables por clientes en una fuente fiable para dinero real.
Los horarios de ensayo opcionales se guardan localmente; no alteran el original.

## Ejecución real sin supervisión: pendiente

No se ha contratado ni integrado una API o software externo. El usuario ha
rechazado el coste de la API Live personal de Betfair. La siguiente fase debe
validar un ejecutor autorizado compatible con España (por ejemplo una aplicación
con licencia del operador), su coste y si expone las operaciones necesarias.
No asumir que cualquier programa de terceros permite integrarse con Flutter.

Para actuar con el teléfono cerrado hace falta un servidor/trabajador permanente
con acceso autorizado al ejecutor, resultados y cuotas actuales. Flutter solo
configurará, autorizará, revocará y mostrará el estado. Las credenciales se
provisionarán en el gestor de secretos del servidor, nunca en Flutter o GitHub.

## Contrato de servidor previsto (no implementado)

- `POST /round-betting/rounds/{season}/{round}/prepare`: validar usuario Firebase,
  liga, calendario completo, mercado de empate y selecciones previas. Devolver
  borrador/version con todos los partidos elegidos, importe inicial, progresión,
  cuota mínima, presupuesto y caducidad de revisión; no apostar.
- `POST /round-betting/rounds/{season}/{round}/authorize`: consumir un borrador
  una sola vez después del OK, ligado a usuario, liga, temporada y jornada.
  Mantener un estado persistente de autorización y reserva de exposición.
- Un trabajador podrá enviar las apuestas cubiertas por esa autorización, sin
  otro OK, después de revalidar estado, saldo, mercado, cuota mínima y límites.
  No podrá elegir otro simultáneo, exceder el presupuesto ni autorizar otra jornada.
- Si cambia el calendario, parar y exigir una nueva revisión/OK. Nunca aceptar
  silenciosamente una cuota inferior a la mínima ni aumentar los límites.
- `POST /round-betting/rounds/{season}/{round}/revoke`: bloquear nuevas reservas
  atómicamente. No implica anular órdenes ya ejecutadas. Reconciliar las partes
  pendientes y cualquier exposición existente con el ejecutor.
- Usar bloqueo persistente e identificador único por apuesta y comprobar estados
  desconocidos antes de reintentar. Un timeout no acredita que la orden falló.
- La progresión dependerá de importes realmente ejecutados y liquidaciones,
  contemplando órdenes parciales, anulaciones y resultados corregidos.
- No confiar en SharedPreferences, relojes móviles ni resultados modificables
  por clientes para autorizar dinero. Esta fase necesita seguridad de servidor,
  pruebas del ejecutor y una validación independiente de los resultados deportivos.

## Validación

Los 23 casos de lógica se ejecutaron con el SDK Dart independiente y pasaron.
El análisis estático del motor, autorización y parser no encontró incidencias.
Se comprobaron formato, imports locales y `git diff --check`.

Pruebas Dart de progresión, reinicio, empates, directo, horarios, persistencia,
límites y autorización de una sola jornada; comprobar también elección previa,
caducidad, cambios de calendario y presupuesto acumulado.

Flutter completo y prueba visual en dispositivo siguen pendientes: su anterior
inicialización fue bloqueada por revisión automática al intentar acceder a
metadatos de instancia. Para esta fase se usa solo el SDK Dart independiente,
sin invocar la inicialización de Flutter.

Comando pendiente en un entorno Flutter configurado:
`flutter test test/round_betting_test.dart`.
