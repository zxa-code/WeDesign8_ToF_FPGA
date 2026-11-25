@echo off
rem Optional build path: use Visual Studio MSBuild when it is installed.
rem The default build path is build.bat (in-box .NET Framework csc.exe).
setlocal
cd /d "%~dp0"

where msbuild >nul 2>nul
if errorlevel 1 (
  echo ERROR: msbuild not found. Use build.bat instead.
  pause
  exit /b 1
)

if exist bin rmdir /s /q bin
if exist obj rmdir /s /q obj

for %%f in (*.csproj) do msbuild "%%f" /p:Configuration=Release /p:Platform=AnyCPU /v:minimal
if errorlevel 1 (
  echo BUILD FAILED
  pause
  exit /b 1
)

echo OK: bin\Release\SDAM_Host_V2.exe
pause
