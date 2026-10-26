@echo off
setlocal
cd /d "%~dp0"
dotnet run --project ApuestaJornada.Tests
if errorlevel 1 exit /b 1
dotnet publish ApuestaJornada.Windows -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish
if errorlevel 1 exit /b 1
copy /y Estrategias\*.gz publish\
copy /y README_Ronda15.md publish\
echo Compilado en publish\ApuestaJornada.exe
endlocal
