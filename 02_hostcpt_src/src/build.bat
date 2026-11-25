@echo off
rem Build SDAM_Host_V2.exe with the in-box .NET Framework 4.x C# compiler.
rem No Visual Studio / MSBuild / .NET SDK required.
setlocal
cd /d "%~dp0"

set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe
if not exist "%CSC%" (
  echo ERROR: csc.exe not found. Install .NET Framework 4.x.
  exit /b 1
)

set OUTDIR=bin\Release
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

set REFS=/r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Windows.Forms.DataVisualization.dll /r:System.Xml.dll /r:System.Data.dll

echo Building %OUTDIR%\SDAM_Host_V2.exe ...
"%CSC%" /nologo /target:winexe /platform:anycpu /codepage:65001 /optimize+ /warn:4 ^
  /out:"%OUTDIR%\SDAM_Host_V2.exe" ^
  %REFS% ^
  Protocol.cs LinkStats.cs SerialPortManager.cs MainForm.cs MainForm.Designer.cs Program.cs

if errorlevel 1 (
  echo BUILD FAILED
  exit /b 1
)

echo OK: %OUTDIR%\SDAM_Host_V2.exe
echo Run tests with: tests\run_tests.bat
endlocal
