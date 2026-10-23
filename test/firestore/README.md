# Reglas del puente

Con Node y el emulador Firestore arrancado **localmente** en 127.0.0.1:8089 con
proyecto `demo-jornada`, ejecutar desde esta carpeta:

```text
npm install
npm test
```

El script carga las reglas de la raíz y borra solo los documentos del emulador.
No se conecta a producción. Comprueba acceso del dueño, rechazo de otros
usuarios/anónimos, revocación, inmutabilidad de un OK de simulación,
alta inicial única, retirada de permisos sin autoalta posterior
y conservación del acceso previo a los resultados de LaLiga.

También comprueba el canal real independiente: únicamente BACK al empate de
1 € con confirmación explícita, sin modificar o borrar la autorización ni
restablecer una reserva de envío. Las 70 comprobaciones incluyen rechazos
esperados; los mensajes PERMISSION_DENIED de esos casos no indican un fallo.
