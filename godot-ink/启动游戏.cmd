@echo off
setlocal
set "TASK_GODOT=%~dp0..\.tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%TASK_GODOT%" (
  echo Please pass the Godot executable path as the first argument.
  set "TASK_GODOT=%~1"
)
if not exist "%TASK_GODOT%" (
  echo Godot executable not found. Open project.godot with Godot 4.7.2.
  pause
  exit /b 1
)
start "" /wait "%TASK_GODOT%" --headless --editor --path "%~dp0." --import --quit
start "" "%TASK_GODOT%" --path "%~dp0."
