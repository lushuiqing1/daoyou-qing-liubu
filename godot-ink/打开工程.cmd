@echo off
setlocal
set "TASK_GODOT=%~dp0..\.tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%TASK_GODOT%" set "TASK_GODOT=%~1"
if not exist "%TASK_GODOT%" (
  echo Godot executable not found. Import project.godot in Godot 4.7.2.
  pause
  exit /b 1
)
start "" "%TASK_GODOT%" --editor --path "%~dp0."
