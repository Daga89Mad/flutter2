# Ronda real — versión 0.7.2 — máximo 128 EUR por apuesta

Progresión: **1 → 2 → 4 → 8 → 16 → 32 → 64 → 128 EUR**. Máximo ocho apuestas en la misma jornada y pérdida acumulada máxima **255 EUR**. Después de perder el escalón de 128 EUR se detiene; no existe un escalón de 256 EUR. Si se agotan antes los encuentros elegidos, también se detiene. No arrastra la progresión a otra jornada.

Se conservan el inicio a mitad de jornada, el OK explícito, la elección de un único encuentro entre partidos simultáneos, la cuota 2,80–20, la parada al acertar o aparecer un nuevo empate final elegible y la exclusión de cualquier partido con Real Madrid, Barcelona o Atlético de Madrid. El lunes de la misma jornada conserva la progresión.

## Actualización desde 0.6

1. Publica el `firestore.rules` completo de esta entrega en Firebase. Se añaden reglas del protocolo nuevo y se conservan las de 15 EUR.
2. Actualiza la app desde `main` y compílala. El botón y el diálogo de OK muestran **128 EUR por apuesta / 255 EUR total**. La nueva autorización se guarda en `PuenteJornadaRonda128Real`; no se modifica un OK anterior de 15 EUR.
3. Descomprime todos los archivos de Windows 0.7.2 en una carpeta nueva. No borres documentos, recibos o CSV anteriores.
4. Pausa en BF Bot las estrategias anteriores de este sistema. Si existe un OK anterior de 15 EUR, revoca sus siguientes envíos con el botón de la app. Revisa cualquier apuesta importada en BF Bot: revocar no cancela apuestas en Betfair. Windows exige conciliar las reservas anteriores antes de publicar las nuevas.
5. Importa **EmpatesJornada_Ronda128.gz** en BF Bot. Nombre: **Empates jornada max128 EUR**. Identificador: `261030-RND128`. Proveedor: **EmpatesJornadaRonda128**. Debe usar el importe del tip (IgnoreTipStake=false) y tener máximo por apuesta 128 EUR. Es una estrategia distinta de las anteriores.
6. Configura la carga automática de ese proveedor cada 30 segundos desde la nueva ruta que muestra Windows: `%LocalAppData%\ApuestaJornada\<uid>\bfbot-round128\EmpatesJornadaRonda128.csv`. El archivo se crea sólo al publicar la primera orden.
7. Marca «Ronda REAL» en Windows y conecta primero con «Sólo comprobar historial» marcado. La ruta predeterminada del historial es `%LocalAppData%\bfbotmanager.com\Bf Bot Manager V3\uk_bets_history.gz`.
8. Comprueba en tu instalación que BF Bot actualiza ese archivo con el programa abierto y la opción «Guardar el historial de apuestas cada vez que se actualicen las apuestas» activada. La casilla de comprobación en Windows no sustituye esa prueba. La importación de esta nueva estrategia y su ejecución en tu instalación siguen pendientes de verificación.
9. Para habilitar publicaciones, detén Windows, desmarca sólo lectura, marca la comprobación del guardado automático cuando la hayas verificado y vuelve a conectar. El programa valida el archivo de estrategia.
10. En el móvil elige entre uno y ocho partidos futuros elegibles de la misma jornada, confirma MarketId y EventId de cada Match Odds y revisa el nuevo OK. Sólo habrá ocho escalones si se han autorizado ocho encuentros válidos. Si hay encuentros separados por menos de 120 minutos, elige sólo uno.

## Protecciones conservadas

- Cada duplicación exige una derrota completamente liquidada y dos lecturas estables del historial separadas al menos 15 segundos.
- Publicado no significa aceptado ni correspondido. Las reservas remotas y recibos locales impiden repetir órdenes tras reinicios o pérdida del acuse.
- Historial ausente/ilegible, correspondencia parcial, varias apuestas coincidentes, cuotas/importes incoherentes o liquidación nula bloquean la progresión.
- Entrada desde cinco minutos hasta 60 segundos antes del inicio; si se pierde la ventana, se detiene sin saltar partidos ni apostar en directo.
- Un nuevo empate final elegible posterior al punto de inicio detiene siguientes envíos. No cancela automáticamente órdenes ya publicadas.
- No hay reinicio automático. Sólo una ronda terminal sin reservas, recibos ni CSV puede sustituirse con nuevo OK; se archivan íntegros su autorización y estado en Archivo/{requestId}. Una ronda con órdenes reservadas no admite rearme.
- Windows y BF Bot deben estar encendidos y conectados, sin suspensión. Este programa no inicia sesión directamente en Betfair.

## Compilación y validación

Ejecuta `Compilar_Ronda128.cmd` con SDK .NET 10. El ejecutable distribuido incluye el runtime. Las pruebas de .NET cubren la secuencia completa hasta 128 EUR, el total de 255 EUR, la prohibición del escalón 256 EUR, límites de estrategia y aislamiento del OK antiguo. Las reglas se prueban con emulador Firestore.

No se han realizado apuestas reales al desarrollar ni probar estos cambios. El ejecutable WPF se compila en Linux y no se ha abierto su interfaz en Windows aquí. La comprobación de Flutter continúa pendiente: una ejecución anterior fue bloqueada por revisión automática del entorno al intentar consultar metadatos sensibles, y no se ha repetido. Ejecuta `flutter analyze` y compila en tu equipo antes de la prueba.

## Continuar tras una ventana perdida (0.7.2)

Publica las reglas actualizadas, actualiza la app móvil desde main y usa Windows 0.7.2. Conecta primero en Sólo comprobar historial. Cuando el PC haya confirmado la ronda como terminada y sin reservas, pulsa en el móvil Preparar nueva ronda desde 1 € · partidos restantes. Actualiza los resultados; sólo se podrán seleccionar partidos futuros y se debe esperar al final confirmado de cualquier encuentro iniciado. Los IDs se recuperan para la misma jornada y los mismos equipos; revísalos antes del nuevo OK.

El nuevo OK guarda atómicamente la autorización y el estado anteriores en Archivo/{requestId}, que no admite cambios ni borrados. Windows verifica ese archivo, la ausencia de recibos y CSV y que el historial no contenga apuestas reales pendientes antes de aceptar el rearme. Con reservas anteriores se mantiene el bloqueo.

No borres documentos ni ficheros para desbloquear la prueba. La lectura de apuestas simuladas no sustituye la conciliación de una apuesta real anterior eliminada del historial.
