> Actualización 0.7: para la ronda de máximo 128 EUR por apuesta / 255 EUR acumulados, consulta [README_Ronda128.md](README_Ronda128.md).

# Apuesta a jornada · C# / .NET para Windows · 0.4

Aplicación WPF en C# con .NET 10. Conserva la simulación existente y añade un
**piloto REAL independiente: una única orden BACK al empate de 1 € por cuenta**,
autorizada con un nuevo OK REAL del móvil. Publica un CSV para la importación
local de BF Bot Manager; no llama directamente a la API de Betfair.

**No implementa todavía la jornada real completa ni la martingala real.** No hay
un contrato de retorno automático verificado con BF Bot Manager para aceptación,
importe correspondido, cancelación o liquidación. Tras reservar una orden, la
cuenta queda bloqueada para evitar un segundo envío, incluso si se pierde el
acuse, se reinicia Windows o se borra el CSV. Un resultado deportivo no confirma
la ejecución de una apuesta. La app no calcula saldo ni ganancias reales.

## Preparar la primera orden real

1. Actualiza y compila la app Flutter desde `main`. Publica **el fichero completo**
   `firestore.rules` en Firebase. El ejecutable no despliega reglas. La cuenta
   debe conservar `AccesoApuestaJornada/{uid}` con `activo: true`.
2. Descomprime el ZIP completo y abre `ApuestaJornada.exe` (Windows x64). Incluye
   .NET y no necesita Python, Visual Studio ni permisos de administrador.
3. Con BF Bot Manager detenido, importa `EmpatesJornada_PruebaReal.gz`. Sustituye
   la estrategia anterior **Empates por jornada**; no mantengas dos copias activas
   ni otras estrategias que usen el proveedor `EmpatesJornada`. La copia incluida
   corrige la opción de detener nuevas entradas a 60 segundos del inicio, que
   estaba desactivada en la exportación anterior.
4. Comprueba en BF Bot Manager: cuenta Betfair en **EUR**, BACK, importe fijo 1 €,
   proveedor `EmpatesJornada`, mínimo 2,80/máximo 20, entrada de 5 minutos a
   60 segundos antes del inicio, sin entradas en vivo y cancelación del importe
   sin corresponder a 30 segundos del inicio. Comprueba también el modo REAL
   global y las cuotas disponibles. El archivo no permite verificar el modo
   global, la moneda, el saldo, datos retrasados ni la configuración cargada.
   Si sigue el aviso de datos retrasados, resuélvelo antes de depender de ellos.
5. En Windows, marca **REAL**, deja seleccionado el `.gz` incluido e inicia sesión
   con el correo y contraseña de **la app**, no los de Betfair. Confirma el aviso.
   El programa valida el archivo seleccionado; no puede leer ni modificar la
   estrategia que hayas cargado efectivamente en BF Bot Manager.
6. En BF Bot Manager configura la carga automática de tips desde el **archivo
   local cuya ruta muestra Windows**: normalmente
   `%LOCALAPPDATA%/ApuestaJornada/{uid}/bfbot-live/EmpatesJornada.csv`.
   Usa ese archivo exclusivamente para esta estrategia. Configura la revisión
   aproximadamente cada 20–30 segundos. El CSV aún no existe antes de autorizar;
   si el selector exige un archivo existente, prepara la ruta y realiza la
   primera importación manual cuando Windows publique el CSV dentro de la
   ventana de envío. No crees un CSV con apuestas de ejemplo ni cargues tips viejos.
7. En el móvil abre **Apuesta a jornada → Prueba REAL con BF Bot Manager**. Elige
   el partido del primer grupo pendiente; si coinciden horarios debes elegir uno.
   Copia los `MarketId` y `EventId` del mercado **Match Odds/Cuotas de partido** de
   Betfair y comprueba que corresponden a ese encuentro y al empate (58805).
   Los horarios/resultados siguen siendo automáticos; estos identificadores de
   mercado requieren comprobación manual en esta versión. No se rellenan con
   los IDs de las capturas antiguas.
8. Si empiezas con la jornada a medias, activa **Empezar desde ahora**: el diálogo
   muestra los finales que quedan excluidos. Revoca antes cualquier ensayo activo
   de simulación y espera la confirmación del PC en modo simulación. Después cambia
   Windows a REAL, revisa partido, IDs e importe y pulsa **OK · autorizar 1 € REAL**.
9. Windows espera la ventana de 5 minutos a 60 segundos antes del comienzo,
   contrasta calendario/resultados y relee el OK. Reserva duraderamente el envío
   y publica una única fila CSV. Debes mantener Windows despierto, con Internet
   y BF Bot Manager funcionando. El móvil puede cerrarse después del OK guardado.
10. Comprueba en BF Bot Manager la importación, aceptación, importe correspondido
    y liquidación. **CSV publicado / enviado no significa apuesta ejecutada**.
    Conserva el historial de apuestas para integrar el retorno en la siguiente fase.
    No hay botón para rearmar otra orden real en esta versión.

El CSV usa los campos documentados `Provider`, `EventId`, `MarketId`, `SelectionId`,
`MarketType`, `Handicap`, `BetType`, `Size`, `Price`, `MinPrice` y `MaxPrice`. El tamaño
es 1,00 y la cuota solicitada/mínima es 2,80 (se puede corresponder a mejor cuota).
El filtro de precio o las condiciones del mercado pueden impedir la apuesta.
Si Betfair rechaza el importe de 1 €, no se incrementa automáticamente.

Un nuevo empate final fuera de los finales excluidos bloquea el envío. También lo
bloquean un cambio de calendario, un partido iniciado sin final confirmado o datos
incompletos. Una reserva fallida requiere revisión; nunca se reintenta a ciegas.

**Revocar** solo impide el envío si se recibe a tiempo. Revocación y publicación
local no forman una transacción distribuida. Después de reservar/publicar, pausa
la estrategia y comprueba/cancela lo pendiente en BF Bot Manager. Ni el botón de
revocar ni cerrar Windows confirman una cancelación en Betfair.

No borres los documentos `PuenteJornadaReal/{uid}`, su estado ni la carpeta
`bfbot-live` para rearmar la cuenta: se perdería la protección contra duplicados.
El archivo `live-pilot-once.json` es un comprobante local, no un acuse de Betfair.
La cuenta de la app controla su propio canal; no es un servicio de custodia ni
una garantía de límites frente a cambios manuales en BF Bot Manager.

## Usar el modo simulación existente

1. Descomprime el paquete **Windows x64** completo y abre `ApuestaJornada.exe`.
   La distribución incluye el runtime .NET; no necesita Visual Studio ni instalar
   .NET por separado. No requiere permisos de administrador. No es un instalador.
2. Introduce el correo y contraseña de **la app**, no los de Betfair. Pulsa
   **Conectar PC**. No se guardan contraseñas ni tokens en disco.
3. Publica las reglas de `firestore.rules` del repositorio si aún no lo has hecho,
   y actualiza la app móvil. Tu UID debe tener `AccesoApuestaJornada/{uid}` con
   `activo: true`. El UID inicial autorizado se crea al abrir la app, como se
   documenta en `docs/apuesta_a_jornada.md`.
4. En la app actualizada, abre **Apuesta a jornada** y selecciona temporada y
   jornada: los diez partidos y sus horarios se cargan automáticamente. Activa
   modo PC, escoge encuentros, presupuesto y cuota ficticia, y confirma el OK.
   Si faltan datos del proveedor, pulsa Actualizar para reintentar; no hace falta
   introducir los horarios a mano ni entrar en «Cargar resultados».
5. Espera la confirmación del PC en el móvil antes de cerrarlo. Windows debe seguir
   encendido, conectado a Internet y sin suspensión.

**Detener PC** interrumpe el trabajador y las consultas. El OK remoto sigue
existiendo y puede retomarse al conectar de nuevo. Para revocarlo, usa la app
móvil y espera su confirmación. No se simulan retroactivamente partidos iniciados.

Cierra el programa Python antes de abrir esta versión. Ambos comparten el archivo
de bloqueo para impedir dos procesos locales con la misma cuenta. Entre PCs, las
escrituras condicionadas de Firestore mantienen un lease de 60 segundos. Para
cambiar de Python a .NET, espera un minuto desde la última señal del otro programa.

## Arrancar con la jornada a medias

Actualiza los tres componentes: app Flutter, ejecutable Windows 0.4 y reglas de
`firestore.rules`. El paquete incluye las reglas para publicarlas en Firebase;
no se despliegan al abrir el programa. La versión Python y los ejecutables .NET
anteriores no admiten este nuevo modo y rechazan sus autorizaciones.

1. Elige una jornada que todavía tenga partidos futuros. Si hay un ensayo anterior,
   revócalo y espera a que el PC confirme «revocado» o «detenido».
2. Activa **Empezar desde ahora · jornada a medias** en el móvil y elige los
   encuentros futuros, uno por grupo solapado.
3. Revisa el diálogo: muestra los partidos ya finalizados y sus marcadores.
   Esos partidos quedan fuera de la nueva serie, aunque ya hubiera un empate.
4. Da un nuevo OK. La serie arranca en **1 €**, con historial independiente.
   El siguiente empate final fuera de esa lista detiene la serie, incluso
   si ocurre en un encuentro no elegido. Nunca se reinicia automáticamente.

El gasto de los ensayos anteriores de la misma jornada sigue contando para el
presupuesto total; reiniciar a 1 € no borra ese gasto. Los historiales se conservan.
Si cambia la lista de finales durante la confirmación, se exige revisar otro OK.
No se entra en partidos empezados: si hay uno sin final confirmado se espera.
El ensayo continúa registrando solo en los cinco minutos previos al siguiente
partido elegido. Esta opción no reproduce partidos pasados ni adelanta el reloj.
Un empate anterior no demuestra que vaya a llegar otro.

## Comportamiento y almacenamiento

- 1 € al comenzar cada serie; 2, 4, 8… tras derrota final confirmada. Máximo 256 € por ensayo
  y presupuesto acumulado autorizado. La siguiente jornada requiere otro OK.
- Modo original: cualquier empate final de la jornada detiene la serie, aunque
  no se eligiera. Modo desde ahora: se excluyen solo los partidos ya finalizados
  y confirmados al dar ese nuevo OK.
- Horarios y resultados se contrastan con TheSportsDB. Sin diez partidos fiables,
  ante cambios de calendario o resultados sin final explícito, no se avanza.
- Solo se registra durante los cinco minutos previos al encuentro elegido y
  después de releer la autorización. Se comprueba su versión y se renueva el lease.
- Firebase Auth REST usa la cuenta normal de la app; no hay Admin SDK ni claves
  privadas. La clave API incluida es la misma configuración pública de Flutter.
- El historial se guarda como JSON por autorización, con escritura temporal,
  vaciado a disco y sustitución del archivo; las secuencias y duplicados se validan.
  Un archivo dañado bloquea la ejecución en lugar de empezar desde cero.
- Ubicación: `%LOCALAPPDATA%/ApuestaJornada/{uid}/dotnet-history`. No borres esa
  carpeta durante un ensayo. El historial SQLite de Python no se modifica.
- Al migrar, .NET recupera el último historial confirmado en Firebase. Un registro
  que el otro PC no llegó a subir necesita reconciliación; no se garantiza la
  recuperación de ensayos que solo existan en otro disco.

La revocación y el registro local no son una transacción distribuida. Las cuotas
son ficticias en el modo simulación. Este historial no se usa para calcular
importes reales. El piloto REAL independiente está descrito al principio de esta
guía y no reutiliza autorizaciones de simulación.

## Abrir y compilar el código

Abre `ApuestaJornada.sln` con un entorno compatible con .NET 10, o instala el SDK
.NET 10 y usa los siguientes comandos desde esta carpeta:

```text
dotnet run --project ApuestaJornada.Tests -c Release
dotnet build ApuestaJornada.Windows -c Release
dotnet publish ApuestaJornada.Windows -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o publish/win-x64
```

También se incluye `publicar.cmd` para generar la distribución x64 en Windows.
No se recortan ensamblados WPF. Puede publicarse con otro RuntimeIdentifier si
se necesita otra arquitectura; el paquete entregado es para x64.

Las pruebas son un ejecutor de comprobaciones C# sin paquetes de terceros; sale
con código distinto de cero si alguna falla. No utilizan cuentas reales ni
escriben en producción. Se incluye una autorización exportada por el motor Dart
para comprobar compatibilidad entre ambos programas.

## Validación y límites

Se han superado 81 comprobaciones .NET y 70 comprobaciones de reglas Firestore
en emulador local; se ha compilado/publicado WPF para Windows x64 desde Linux.
No se ha ejecutado la interfaz gráfica en Windows ni completado una compilación
Flutter o una prueba móvil/Betfair de extremo a extremo. No se han enviado
apuestas ni desplegado reglas desde este entorno. El ejecutable no lleva firma
digital de editor.
