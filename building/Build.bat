@echo off
setlocal
cd /d "%~dp0.."

where bash >nul 2>nul
if errorlevel 1 (
	echo bash not found. Install Git for Windows first.
	pause
	exit /b 1
)

bash "building/build.sh" %*
set RC=%ERRORLEVEL%

if not "%RC%"=="0" (
	echo.
	echo Build failed with exit code %RC%.
	pause
) else (
	echo.
	echo Done. PsychEngine.exe is in export\release\windows\bin
	pause
)
exit /b %RC%
