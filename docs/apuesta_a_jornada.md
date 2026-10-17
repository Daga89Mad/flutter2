# Apuesta a jornada: primera versión

## Qué funciona

El menú abre `ApuestaJornadaScreen`. Lee LaLiga del Firestore existente,
incluyendo la ruta legacy de 2025-2026. La temporada y jornada se eligen en pantalla.
No crea colecciones ni modifica el historial de apuestas de los grupos.

Cada jornada tiene su propio historial local de simulación por usuario:
1, 2, 4, 8, 16, 32, 64, 128 y 256 euros; cuota mínima 2,80.
Solo las derrotas finales de apuestas confirmadas aumentan el escalón.
Un empate final en cualquier encuentro detiene la jornada. La siguiente
empieza en un euro, independientemente de las pérdidas o del límite anterior.

El intervalo de 120 minutos sirve únicamente para ofrecer encuentros que pueden
solaparse; nunca se usa como prueba de que un partido haya terminado. Los partidos
iniciados sin final confirmado bloquean nuevas preparaciones. Si el proveedor
falla o falta un horario, se bloquea la preparación en lugar de asumir un resultado.

Si hay opciones simultáneas/solapadas, no se selecciona ninguna automáticamente.
Elegir un partido no confirma nada. «Preparar apuesta» muestra partido, horario,
empate a favor, importe, cuota manual y beneficio antes de comisiones.
«OK · simular apuesta» es necesario en cada apuesta, no autoriza toda la jornada.
La preparación caduca a los 60 segundos. Tras el OK se releen los partidos desde
el servidor y se comprueba que el encuentro, horario y escalón siguen siendo válidos.

Esta versión **no envía órdenes a Betfair**, no consulta su saldo/cuotas y no tiene
credenciales. Las cuotas introducidas son de ensayo. Los registros locales no son
una contabilidad de dinero real ni se sincronizan entre móviles. Se conservan al
cerrar la pantalla o reiniciar la app; desinstalar/borrar datos puede eliminarlos.
No hay un botón que convierta el ensayo en órdenes reales.

## Datos de los partidos

El importador existente añade:

- `InicioUTC`: Timestamp de Firestore, desde `strTimestamp` o `dateEvent` + `strTime` UTC.
- `Estado`: estado original del proveedor.
- `Finalizado`: true solo ante un estado final explícito.

La pantalla exige final explícito y ambos goles antes de interpretar el marcador.
Ni `Empate: true` ni `0-0` por sí solos bastan. Para documentos antiguos, volver a
importar la jornada; revisar cualquier lista `hasOnly` de las reglas desplegadas
antes de admitir estos tres campos nuevos. Las reglas actuales no están en este repo.
Puede ajustarse un horario local solo para el ensayo; nunca modifica el partido original.
Los resultados se actualizan al reimportarlos o cuando otro proceso actualiza Firestore.
La suscripción existe mientras la pantalla está abierta: no hay un servicio en segundo plano.

## Lo necesario para ejecutar apuestas reales

1. Cuenta propia de Betfair **Exchange** España verificada, saldo y App Key habilitada
   para el uso correspondiente. La clave Delayed tampoco es una cuenta ficticia.
2. Backend HTTPS (por ejemplo Cloud Run/Functions o un servicio existente) con
   verificación del Firebase ID token, usuario autorizado y configuración de banca.
   Ninguna contraseña, App Key, sesión ni certificado privado debe ir en Flutter,
   GitHub o un chat. Se provisionan en el gestor de secretos del backend.
3. Fuente de horarios, jornadas y estados finales fiable, con correspondencia entre
   el partido de la app, `eventId`, `marketId` de MATCH_ODDS y `selectionId` del empate.
4. Límites de apuesta, exposición y banca autorizada, comisión de cuenta y política
   para aplazados, anulaciones, resultados corregidos y órdenes parcialmente igualadas.
5. Persistencia de servidor y reconciliación de órdenes, no SharedPreferences, para
   evitar dobles apuestas entre móviles/reintentos y recuperar respuestas perdidas.

## Contrato previsto para la siguiente fase (aún no implementado)

- `GET /round-betting/rounds/{season}/{round}`: partidos, resultados finales,
  exposición, historial y siguiente escalón calculados en servidor para LaLiga.
- `POST /round-betting/prepare`: recibe partido elegido; el servidor valida el usuario,
  la jornada, ausencia de otro empate, órdenes pendientes, horario, saldo y mercado.
  Devuelve `draftId`, importe fijado en céntimos, cuota mínima aceptada, horario,
  selección, caducidad corta y versión. No coloca la apuesta.
- `POST /round-betting/drafts/{draftId}/confirm`: solo después de otro OK del usuario.
  Consume atómicamente un borrador de un solo uso ligado al usuario/partido/importe/
  cuota/versión y rechaza cambios con HTTP 409 para exigir una nueva confirmación.
  Nunca se incrementa importe ni se acepta una cuota peor silenciosamente.
- El adaptador Betfair solo puede ejecutarse por esta ruta. Actualizaciones de datos,
  temporizadores y notificaciones no tienen permiso para colocar órdenes.
- Usar un identificador estable por apuesta, bloqueo persistente y reconciliación
  de `customerOrderRef`/estado del proveedor. Un timeout de `placeOrders` significa
  estado desconocido: no volver a enviar sin comprobar si la orden ya existe.
- El backend distingue propuesta, autorizada, enviando, respuesta desconocida,
  no igualada, parcialmente igualada, igualada, anulada y liquidada. La progresión
  solo cambia con el importe realmente ejecutado y la liquidación confirmada.
- Si aparece un empate, bloquear órdenes futuras; una orden ya igualada no se puede
  tratar como cancelada. Cualquier parte pendiente requiere cancelación y comprobación.

## Validación

En esta implementación se ejecutaron los 13 casos del motor/proveedor mediante
un ejecutor local Dart sin dependencias Flutter: todos pasaron. `dart analyze`
del motor y parser no encontró incidencias. También se comprobaron formato,
imports locales y `git diff --check`.

La ejecución completa de Flutter quedó bloqueada por revisión automática cuando
su inicialización intentó acceder a metadatos de la instancia. No se ha eludido
ese bloqueo. Están pendientes el análisis completo, `flutter test` y la prueba
visual en un dispositivo con el SDK y dependencias del proyecto instalados.

`flutter test test/round_betting_test.dart` prueba reinicios, progresión, empate fuera
de la apuesta, 0-0 en directo, horarios, registros inválidos y límite.
Revisar además en dispositivo: importar jornada futura, completar horarios si faltan,
elegir simultáneo, cancelar el diálogo, confirmar el ensayo, recargar la app, importar
un resultado final y comprobar el nuevo escalón y el reinicio al cambiar jornada.
