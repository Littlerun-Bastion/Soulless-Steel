@echo off
rem Runs the automated tests headless (project/game/test, see README there).
rem   run_tests.bat                  every suite
rem   run_tests.bat --fast           skip the slow suites (whole-game simulations)
rem   run_tests.bat --suite=Hangar   only suites whose name contains "Hangar"
rem Uses the Godot console exe in this folder, or the one in the GODOT variable.
setlocal
set "ROOT=%~dp0"
if not defined GODOT (
	for %%G in ("%ROOT%Godot_v*_win64_console.exe") do set "GODOT=%%~fG"
)
if not defined GODOT (
	echo Godot not found: put the Godot console exe in %ROOT% or set GODOT to its path.
	exit /b 2
)

rem Refresh Godot's import and script class cache, so new scripts and assets are known.
"%GODOT%" --headless --import --path "%ROOT%project" >nul 2>&1

"%GODOT%" --headless --path "%ROOT%project" res://game/test/RunAllTests.tscn -- %*
set "RESULT=%ERRORLEVEL%"

rem Opened by double-click: keep the window open to read the results.
echo %CMDCMDLINE% | findstr /i /c:"%~nx0" >nul && pause
exit /b %RESULT%
