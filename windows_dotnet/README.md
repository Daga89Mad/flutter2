# Apuesta a jornada · C# / .NET para Windows

Aplicación WPF en C# con .NET 10. Sustituye al programa Python conservando el
protocolo de la app Flutter y las reglas de Firebase. **Solo simulación**: no
conecta con Betfair, no consulta saldo/cuotas reales y no envía órdenes a BF Bot
Manager. No hace falta instalar Python para utilizar el ejecutable distribuido.

## Usar el programa

1. Descomprime el paquete **Windows x64** completo y abre `ApuestaJornada.exe`.
   La distribución incluye el runtime .NET; no necesita Visual Studio ni instalar
   .NET por separado. No requiere permisos de administrador. No es un instalador.
2. Introduce el correo y contraseña de **la app**, no los de Betfair. Pulsa
   **Conectar PC**. No se guardan contraseñas ni tokens en disco.
3. Publica las reglas de `firestore.rules` del repositorio si aún no lo has hecho,
   y actualiza la app móvil. Tu UID debe tener `AccesoApuestaJornada/{uid}` con
   `activo: true`. El UID inicial autorizado se crea al abrir la app, como se
   documenta en `docs/apuesta_a_jornada.md`.
4. En el móvil, abre **Apuesta a jornada**, carga los diez partidos, activa modo PC,
   escoge los encuentros, presupuesto y cuota ficticia, y confirma el OK.
5. Espera la confirmación del PC en el móvil antes de cerrarlo. Windows debe seguir
   encendido, conectado a Internet y sin suspensión.

**Detener PC** interrumpe el trabajador y las consultas. El OK remoto sigue
existiendo y puede retomarse al conectar de nuevo. Para revocarlo, usa la app
móvil y espera su confirmación. No se simulan retroactivamente partidos iniciados.

Cierra el programa Python antes de abrir esta versión. Ambos comparten el archivo
de bloqueo para impedir dos procesos locales con la misma cuenta. Entre PCs, las
escrituras condicionadas de Firestore mantienen un lease de 60 segundos. Para
cambiar de Python a .NET, espera un minuto desde la última señal del otro programa.

## Comportamiento y almacenamiento

- 1 € por jornada; 2, 4, 8… tras derrota final confirmada. Máximo 256 € por ensayo
  y presupuesto acumulado autorizado. La siguiente jornada requiere otro OK.
- Cualquier empate final de la jornada detiene la serie, aunque no se eligiera.
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
son ficticias y el dueño puede editar su canal de ensayo: esta arquitectura no
está preparada para dinero real. La integración con BF Bot Manager requiere
verificar importación, aceptación, ejecución parcial, liquidación y cancelación.

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

Se ha compilado el motor, ejecutado 42 comprobaciones y compilado/publicado el
proyecto WPF para Windows x64 desde Linux. No se ha ejecutado la interfaz gráfica
en un Windows real ni probado el circuito con la cuenta Firebase del usuario.
El ejecutable no lleva firma digital de editor.
