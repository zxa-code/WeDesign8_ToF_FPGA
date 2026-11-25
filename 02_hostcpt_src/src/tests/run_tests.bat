@echo off
rem Compile and run the protocol unit tests (console, no WinForms needed).
setlocal
cd /d "%~dp0"

set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe
if not exist "%CSC%" (
  echo ERROR: csc.exe not found. Install .NET Framework 4.x.
  exit /b 1
)

if not exist bin mkdir bin

echo Compiling tests ...
"%CSC%" /nologo /target:exe /platform:anycpu /codepage:65001 /optimize+ ^
  /out:bin\ProtocolTests.exe ^
  ..\Protocol.cs ..\LinkStats.cs ProtocolTests.cs

if errorlevel 1 (
  echo TEST BUILD FAILED
  exit /b 1
)

bin\ProtocolTests.exe
exit /b %errorlevel%
