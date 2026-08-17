@echo off
rem ============================================================
rem  Understand Anything Quick Tool - Launcher (ASCII only)
rem  Pure ASCII: works in ANY codepage (double-click / cmd /
rem  VS Code terminal). Runs the PowerShell implementation.
rem ============================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UA-QuickTool.ps1" %*
if errorlevel 1 (
    echo.
    echo Quick Tool exited with an error.
    pause
)
endlocal
