# Apuesta a jornada · programa de Windows

Esta versión conecta el móvil con tu PC **en simulación**. No conecta con Betfair,
no necesita sus credenciales y no envía apuestas a BF Bot Manager. Tener una cuenta
Betfair permite preparar la siguiente integración, pero no la activa por sí solo.

## Primera instalación

1. Descarga el código de la rama `feature/apuesta-a-jornada` de este repositorio
   y extrae el ZIP. Conserva toda la carpeta `windows_bridge`.
2. Instala [Python 3 para Windows](https://www.python.org/downloads/windows/),
   versión 3.10 o superior, con Tcl/Tk (incluido normalmente en el instalador).
   No hay librerías adicionales que instalar.
3. Prepara las reglas de Firebase del repositorio. `firebase.json` referencia
   `firestore.rules`; antes de publicarlas, compara ese archivo con las reglas
   actuales de tu consola para conservar cualquier cambio posterior. El archivo
   parte de las reglas compartidas en el proyecto, no de una descarga de producción.
   Con Firebase CLI configurado por el propietario:

   ```text
   firebase deploy --only firestore:rules --project login-d2344
   ```

   También se pueden publicar desde la consola de Firestore. Estas reglas y la app
   modificada deben estar instaladas antes de probar el enlace. No se han desplegado
   cambios en tu Firebase desde este desarrollo.
   La app actualizada también exige `AccesoApuestaJornada/{uid}` con `activo: true`.
   Al abrirla por primera vez con `DBbLkTOEvqMTUP4zMAn7ap8iLFZ2`, crea ese primer
   permiso una única vez después de publicar las reglas. Los demás se añaden
   desde la consola Firebase. No borres la marca `_inicializacion` al retirar
   permisos. Sin acceso autorizado, el botón se oculta y el PC no puede continuar.
4. Abre `windows_bridge/iniciar.cmd`. Inicia sesión con **el mismo correo y
   contraseña de la app móvil**, no con los de Betfair. No compartas contraseñas
   por el chat. La configuración pública de Firebase ya está incluida.
5. En la app actualizada abre **Apuesta a jornada**, importa los diez partidos de
   LaLiga y escoge temporada y jornada. Activa **Ejecutar ensayo en mi PC Windows**.
   Elige uno por cada grupo de partidos solapados, introduce presupuesto y cuota
   ficticia y confirma **OK · autorizar jornada**.
6. Espera a ver en el móvil la confirmación y la última señal del PC. Entonces
   puedes cerrar el móvil. Windows debe seguir encendido, con Internet y sin
   suspensión. El programa consulta cada 15 segundos; los resultados deportivos
   se consultan como máximo una vez por minuto.
7. Para parar, usa **Revocar autorización del PC** en el móvil y espera la
   confirmación del PC. Si no hay Internet no puede confirmarse la revocación.
   **Detener PC** deja de consultar cuando termina el acceso de red en curso;
   no borra el OK remoto. Al reconectar, puede retomar ese OK hasta su caducidad.

Si aparece un error de acceso, comprueba las reglas y que ambas sesiones son de
la misma cuenta de la app. Si el PC no tiene señal reciente, el móvil lo indica;
no cambia a ejecución local automáticamente. Tras una suspensión puede retomar
los partidos futuros; no simula retroactivamente los ya iniciados.

## Qué hace el ensayo

- Un OK por jornada y una sola autorización remota por usuario.
- 1 €, después 2, 4, 8… únicamente tras derrota final confirmada de la apuesta
  anterior. Máximo 256 € por apuesta y presupuesto acumulado autorizado.
- Cualquier empate final de esa jornada detiene la secuencia, aunque ese partido
  no estuviera elegido. La siguiente jornada requiere otro OK y comienza en 1 €.
- Espera los cinco minutos anteriores al encuentro elegido; si otro partido
  iniciado aún no tiene resultado final, espera y puede perder la oportunidad.
- Cambios de horario/calendario, caducidad o límites detienen la autorización.
- SQLite evita repetir un ensayo al reiniciar o fallar el envío del estado.
- Un lease de 60 segundos bloquea un segundo PC mientras el primero lo renueva. No debe copiarse el archivo
  `agent.txt` entre PCs. Un traslado recupera el último historial confirmado en
  Firebase; no recupera registros que el otro PC no llegó a subir. Guarda su base local en `%LOCALAPPDATA%/ApuestaJornada`.

El PC contrasta equipos y horarios de Firestore con TheSportsDB y consulta sus
resultados aunque el móvil esté cerrado. El proveedor gratuito puede fallar o
retrasarse: se espera sin registrar nuevas apuestas si no puede verificarse el
calendario completo. No se permiten ajustes manuales de horario en el modo PC;
son exclusivos del ensayo local. Los importes y cuotas son ficticios, por lo que
este ensayo **no demuestra rentabilidad** ni contempla ejecuciones o comisiones.

No se guardan contraseñas ni tokens en disco. Se vuelve a iniciar sesión al abrir
el programa. El historial local contiene equipos, elecciones e importes ficticios.
La cuenta de la app puede modificar su propio canal: esto es adecuado para el
ensayo, no constituye una autorización segura para dinero real.

## Siguiente fase: BF Bot Manager

En el PC, instala la [prueba oficial de BF Bot Manager](https://www.bfbotmanager.com/en/trial)
y configura allí tu única cuenta Betfair, empezando por su modo de simulación.
El coste/licencia del proveedor es independiente de este programa.

Para programar el adaptador hacen falta un ejemplo de CSV exportado desde **My S.**
(sin datos personales) y verificar cómo el programa informa de apuesta aceptada,
rechazada, parcial y liquidada. La [importación oficial de tips](https://www.bfbotmanager.com/en/help/knowledge_base/article/53-bet-on-imported-tips)
no acredita por sí sola todo ese circuito. También hay que verificar la retirada
de tips ya importados y la prevención de duplicados. Hasta entonces no se genera
un CSV activo ni se configura una URL que pueda enviar dinero real.

## Pruebas de desarrollo

Desde la raíz del repositorio:

```text
python -m unittest discover -s windows_bridge/tests -v
```

Son pruebas locales con dobles de Firebase y del proveedor; no usan cuentas,
no crean documentos en producción ni conectan con Betfair. La interfaz Tkinter,
la autenticación real y el circuito móvil-PC necesitan una prueba en Windows con
el proyecto Firebase configurado. No se distribuye todavía un instalador .exe.
