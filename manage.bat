@echo off
rem FNF-PE RealQuickJS toolbox - Windows entry.
rem All logic lives in manage.sh; this file only finds bash and hands over.
rem
rem   manage.bat               interactive menu
rem   manage.bat --zh          menu, Chinese
rem   manage.bat --en          menu, English
rem   manage.bat --zh 4        run item 4 directly

setlocal
chcp 65001 >nul 2>&1
cd /d "%~dp0"

set "BASH="
where bash >nul 2>nul && set "BASH=bash"
if not defined BASH if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"

if not defined BASH (
	echo.
	echo bash not found. Install Git for Windows ^(it ships bash^) and run again.
	echo 找不到 bash。装一个 Git for Windows，再双击本文件。
	echo.
	pause
	exit /b 1
)

"%BASH%" "%~dp0manage.sh" %*

set RC=%ERRORLEVEL%
if not "%RC%"=="0" (
	echo.
	echo exited with code %RC%.
	pause
)
exit /b %RC%
