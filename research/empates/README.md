# Investigación histórica A/B/C

Se ha preparado un pipeline Python reproducible para descargar y validar 20 CSV (LaLiga y Serie A, 2016/17–2025/26), entrenar Dixon-Coles con temporadas anteriores y medir Brier/log-loss/top 20 sin fugas del resultado de cada encuentro.

El script completo se entrega como archivo descargable en la conversación. Estado verificado: cuatro CSV históricos disponibles (2024/25 y 2025/26); otras dieciséis descargas bloqueadas temporalmente. Resultado exploratorio 2025/26: Brier A 0.188103, B 0.188281, C 0.187285, mercado 0.185415 (760 partidos). Son diferencias pequeñas que aún no justifican sustituir el modelo de la app.

Pendiente publicar/ejecutar el script completo en un entorno con descarga de CSV y verificar 10 temporadas. No cambiar `main` hasta validación.
