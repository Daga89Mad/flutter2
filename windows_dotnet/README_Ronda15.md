# Ronda real de hasta 15 EUR — versión 0.6

Implementa una prueba independiente con hasta cuatro encuentros elegidos de una jornada de LaLiga. Empieza en 1 EUR y duplica sólo después de una derrota totalmente liquidada: 1, 2, 4, 8 EUR. Máximo acumulado 15 EUR. Se detiene al ganar o aparecer un nuevo empate final en un encuentro elegible de la jornada. Los partidos finalizados al autorizar quedan fuera del nuevo inicio. Se excluye cualquier partido con Real Madrid, Barcelona o Atlético de Madrid. El lunes conserva la progresión y el presupuesto de la misma jornada.

## Instalar y comprobar

1. Publica el fichero completo `firestore.rules` de esta entrega en el proyecto Firebase de la aplicación. No se ha desplegado automáticamente.
2. Actualiza y compila la aplicación Flutter desde `main`. Abre la pantalla de prueba REAL de 1 EUR y pulsa el botón nuevo «Ronda REAL · 1 → 2 → 4 → 8 EUR · máximo 15 EUR».
3. Descomprime el programa Windows completo en una carpeta nueva. Mantén los archivos de estrategia junto a `ApuestaJornada.exe`. No borres los recibos ni los CSV de la prueba anterior.
4. En Windows marca «Ronda REAL» y deja marcado inicialmente «Sólo comprobar historial». La ruta predeterminada es `%LocalAppData%\bfbotmanager.com\Bf Bot Manager V3\uk_bets_history.gz`. Corrígela si utilizas otro perfil de BF Bot.
5. Conecta con el usuario de nuestra app. El modo de comprobación lee el historial y publica estados, pero no crea órdenes. El historial anterior permite conciliar el piloto real de 1 EUR antes de cualquier nuevo envío.
6. En BF Bot activa «Guardar el historial de apuestas cada vez que se actualicen las apuestas». Comprueba que `uk_bets_history.gz` cambia cuando BF Bot actualiza una apuesta estando abierto. El guardado al cerrar se observó en los archivos enviados; el guardado durante ejecución aún debe comprobarse en tu PC.
7. Pausa la estrategia antigua «Empates por jornada». Importa la NUEVA `EmpatesJornada_Ronda15.gz`. Debe llamarse «Empates jornada 15 EUR», tener identificador `261026-RND015`, proveedor `EmpatesJornadaRonda`, máximo por apuesta 8 EUR y usar el importe del tip (`IgnoreTipStake=false`). No actives otras estrategias que apuesten a esos tips.
8. Configura en BF Bot la carga automática del proveedor `EmpatesJornadaRonda` desde el CSV cuya ruta muestra Windows. Recarga cada 30 segundos. El CSV aparece sólo al enviar el primer encuentro autorizado.
9. Detén Windows, desmarca «Sólo comprobar historial» y marca la comprobación del guardado automático sólo después de verificarla. Vuelve a conectar: el programa valida el archivo de estrategia y muestra el aviso del límite de 15 EUR.
10. En el móvil elige de uno a cuatro partidos futuros. Comprueba MarketId y EventId exactos en Betfair para cada Match Odds. En partidos simultáneos o separados menos de 120 minutos elige sólo uno. Revisa la lista y autoriza con el OK REAL de hasta 15 EUR. Este OK no se ha ejecutado por desarrollar ni instalar el programa.

## Qué confirma el sistema

- Publicar el CSV NO acredita que Betfair haya aceptado una apuesta.
- Lee el XML comprimido de BF Bot sin modificarlo. Vincula mercado, selección 58805, proveedor, estrategia, divisa, BACK y fecha de reserva. Rechaza apuestas simuladas.
- Una correspondencia parcial, varios BetId, importes/cuotas incoherentes o una liquidación nula detienen la prueba para revisión. Nunca rellena una apuesta parcial ni la reenvía.
- Antes de duplicar exige el importe completo liquidado como pérdida y dos lecturas idénticas separadas al menos 15 segundos.
- Reserva en Firestore y guarda un recibo local ANTES del CSV. Reinicios, pérdida del acuse o borrado del CSV no habilitan un reenvío. Una reserva sin apuesta confirmada queda bloqueada.
- Si la liquidación llega demasiado tarde para la ventana de 5 minutos a 60 segundos antes del siguiente inicio, se detiene. No salta al siguiente partido ni apuesta en directo.
- La revocación impide siguientes publicaciones; no cancela apuestas ya importadas. Revisa y cancela lo pendiente en BF Bot/Betfair.
- Una autorización de ronda por cuenta, sin reinicio automático después del cuarto escalón. No modifiques ni borres manualmente documentos o recibos para repetir una prueba.
- Windows y BF Bot deben permanecer encendidos y conectados, sin suspensión. El programa no inicia sesión directamente en Betfair.

## Compilar

Requiere SDK .NET 10 sólo para compilar fuentes; el ejecutable distribuido incluye el runtime.

```powershell
dotnet run --project ApuestaJornada.Tests
dotnet publish ApuestaJornada.Windows -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish
Copy-Item Estrategias\*.gz publish\
```

## Validación y límites

La lógica .NET y los controles de autorización se verifican con pruebas automatizadas sin enviar apuestas reales. El ejecutable Windows se compila desde Linux: no se ha abierto su interfaz WPF en un PC Windows en este entorno. La pantalla Flutter está añadida y formateada; la validación Flutter se ha bloqueado por revisión automática del entorno y debe ejecutarse en tu equipo. El historial interno de BF Bot no es una API contractual: si cambia o no se puede leer, se bloquean nuevos envíos. No se ha comprobado todavía la importación de la nueva estrategia ni la ejecución completa en tu instalación.

El plan original del domingo 25 de octubre de 2026 ya ha pasado. La app no reutiliza los IDs ni fechas de aquel plan: sólo permite un nuevo OK explícito sobre encuentros futuros comprobados. El desarrollo no activa ninguna apuesta por sí mismo.
