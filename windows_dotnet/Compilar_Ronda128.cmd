@echo off
setlocal
cd /d "%~dp0"
dotnet run --project ApuestaJornada.Tests
if errorlevel 1 exit /b 1
dotnet publish ApuestaJornada.Windows -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish128
if errorlevel 1 exit /b 1
copy /y Estrategias\EmpatesJornada_Ronda128.gz publish128\
copy /y Estrategias\EmpatesJornada_PruebaReal.gz publish128\
copy /y README_Ronda128.md publish128\
echo Compilado en publish128\ApuestaJornada.exe
endlocal
