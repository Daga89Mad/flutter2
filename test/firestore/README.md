# Reglas del puente

Con Node y el emulador Firestore arrancado **localmente** en 127.0.0.1:8089 con
proyecto `demo-jornada`, ejecutar desde esta carpeta:

```text
npm install
npm test
```

El script carga las reglas de la raíz y borra solo los documentos del emulador.
No se conecta a producción. Comprueba acceso del dueño, rechazo de otros
usuarios/anónimos, revocación, inmutabilidad de un OK, modo solo de simulación
y conservación del acceso previo a los resultados de LaLiga.
