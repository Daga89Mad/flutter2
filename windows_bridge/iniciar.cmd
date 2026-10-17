@echo off
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  py -3 app.py
) else (
  python app.py
)
if errorlevel 1 (
  echo Instala Python 3.10 o superior con Tcl/Tk y vuelve a intentarlo.
  pause
)
