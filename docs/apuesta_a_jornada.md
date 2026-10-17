# Apuesta a jornada: autorización de jornada completa

## Alcance de esta fase

El menú abre `ApuestaJornadaScreen`, que lee LaLiga del Firestore existente,
incluyendo la ruta legacy de 2025-2026. Esta versión **solo simula**: no envía
órdenes a una casa, no consulta cuotas/saldo reales y no tiene credenciales.
El historial local se conserva por usuario, temporada y jornada. En modo PC,
el OK y el estado del ensayo también se sincronizan en un canal privado de
Firestore. No son contabilidad real. Instalación: [Windows](../windows_bridge/README.md).

El usuario ha elegido **un OK por jornada**, sustituyendo el OK por apuesta.
Ese consentimiento no se hereda a la jornada siguiente ni autoriza apuestas
fuera de los partidos, importe máximo y presupuesto mostrados.

## Usuarios autorizados

El menú y la pantalla comprueban `AccesoApuestaJornada/{uid}` y solo permiten
acceder cuando existe el documento con `activo: true`. Sin permiso, durante la
comprobación o ante un error, el botón no aparece. La lista se administra desde
la consola Firebase: documento con ID igual al UID de Authentication y campo
booleano `activo: true`. `activo: false` o borrar el documento retira el acceso.
No se usa el correo como identificador.

Primer UID: `DBbLkTOEvqMTUP4zMAn7ap8iLFZ2`. Al iniciar sesión con ese UID en
la app actualizada, se crea su permiso y la marca `_inicializacion` en una sola
transacción. Las reglas permiten esta alta una única vez y únicamente a ese UID.
La marca evita que borrar posteriormente el permiso reactive el acceso. Los
clientes no pueden añadir más usuarios ni modificar permisos; se hace desde la
consola o un proceso administrativo con IAM.

**La colección se creará al ejecutar esa inicialización, después de publicar
las reglas. No se ha creado desde este entorno ni se han desplegado reglas en
producción.** El repositorio por sí solo no modifica Firebase. El puente también
exige pertenecer a la lista para leer comandos o registrar actividad; sigue
permitida una revocación válida de comandos propios tras perder el permiso.

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

Hay dos formas de ejecutar el ensayo. En modo local hay que mantener la pantalla
abierta y actualizar los resultados. En modo PC, el programa Python de
`windows_bridge` recibe el OK desde Firestore, consulta los resultados y guarda
su progreso en SQLite incluso con el móvil cerrado. Windows debe estar despierto
y conectado. No se apuesta retroactivamente sobre partidos ya iniciados.

El canal es `PuenteJornada/{uid}` y su respuesta `Estado/actual`. Se usa Firebase
Auth con la cuenta de la app y REST; no hay Admin SDK ni claves privadas. Una
lectura con versión y una escritura condicionada mantienen un lease entre PCs.
La clave de cada ensayo y su secuencia tienen restricciones UNIQUE en SQLite.
El PC relee el comando antes de registrar una nueva apuesta ficticia y publica
su última señal, estado, resultados e historial. Un fallo de red no autoriza
una apuesta real ni activa un ejecutor alternativo.

La revocación se guarda en el servidor y el PC confirma cuando la recibe. El
estado del móvil no acredita recepción hasta observar esa respuesta. No existe
atomicidad entre el último GET y la escritura SQLite: puede registrarse un ensayo
si la revocación coincide con esos instantes. Este canal no debe reutilizarse para
dinero real sin un protocolo de reserva y reconciliación con el ejecutor.

## Datos y resultados

El importador existente guarda `InicioUTC` (Timestamp), `Estado` y `Finalizado`.
Solo se interpreta un marcador cuando hay estado final explícito y ambos goles.
Un 0-0 en directo, `Empate: true` o el mero paso de 120 minutos no bastan.
En modo local los resultados solo cambian al actualizar Firestore. En modo PC,
TheSportsDB se consulta directamente con una caché máxima de un minuto; el estado
se devuelve al móvil sin modificar los documentos globales de resultados. Los
equipos deben coincidir exactamente y los diez encuentros deben estar disponibles.
Sin datos actuales se bloquean nuevos ensayos; no se usa una respuesta caducada.

Las reglas compartidas de `firestore.rules`, versión 2, permiten estos campos en
las rutas de resultados mediante su bloque general para usuarios autenticados.
Esto no acredita cuáles están desplegadas actualmente en Firebase ni convierte
esos datos editables por clientes en una fuente fiable para dinero real.
Los horarios de ensayo opcionales se guardan localmente; no alteran el original.

## Ejecución real sin supervisión: pendiente

El enlace móvil-PC funciona únicamente en simulación. La cuenta Betfair del
usuario todavía no está vinculada a este programa. BF Bot Manager es el ejecutor
previsto, pendiente de instalar/configurar y verificar su contrato de importación
y su retorno de ejecuciones y liquidaciones. No se generan órdenes reales ni un
CSV con un esquema supuesto. La activación de una API Live personal no es
requisito de esta fase.

Antes de habilitar dinero real se necesitan identificadores exactos de mercado y
selección, cuotas y saldo actuales, importes ejecutados, estados parciales,
rechazos, liquidaciones y reconciliación tras desconexiones. El presupuesto y la
revocación deben coordinarse con el ejecutor. Las reglas actuales permiten al dueño
escribir su propio canal de ensayo: no sustituyen un backend de órdenes reales.

## Validación

- 23 pruebas del motor/autorización Dart superadas con el SDK independiente y
  el paquete `test`; análisis estático de esos módulos sin incidencias.
- Pruebas Python de progresión, fallos de red, reinicios, traslado entre PCs,
  revocación, proveedor y límites. Ejecución: ver README de Windows.
- 35 comprobaciones de reglas superadas contra un emulador local Firestore:
  dueño, aislamiento entre cuentas, anónimos, revocación, modo e inmutabilidad.
- Formato Dart y `git diff --check` comprobados.

Faltan la compilación completa de Flutter, prueba visual en dispositivo y prueba
real del enlace con Windows/Firebase. No se ha instalado software en el PC del
usuario, publicado reglas en producción ni conectado ninguna cuenta Betfair.
La inicialización anterior de Flutter fue bloqueada por revisión automática al
intentar acceder a metadatos de instancia. Se han usado pruebas del SDK Dart
independiente sin volver a invocar esa inicialización.

En un entorno Flutter ya configurado: `flutter test test/round_betting_test.dart`.
