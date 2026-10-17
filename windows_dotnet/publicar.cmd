@echo off
cd /d "%~dp0"
where dotnet >nul 2>nul
if errorlevel 1 (
  echo Instala el SDK de .NET 10 para compilar este proyecto.
  pause
  exit /b 1
)
dotnet run --project ApuestaJornada.Tests -c Release
if errorlevel 1 exit /b 1
dotnet publish ApuestaJornada.Windows -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o publish/win-x64
if errorlevel 1 exit /b 1
echo Ejecutable creado en publish\win-x64\ApuestaJornada.exe
pause
