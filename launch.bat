@echo off
setlocal enabledelayedexpansion

rem ---- Start server ----
start "" zig_multiplayer_game.exe --server
rem Get PID of last process
for /f "tokens=2 delims==;" %%a in ('wmic process where "name='zig_multiplayer_game.exe'" get ProcessId /value ^| find "="') do (
    set pid1=%%a
)

rem ---- Start client #1 ----
start "" zig_multiplayer_game.exe --client-id 1
for /f "tokens=2 delims==;" %%a in ('wmic process where "name='zig_multiplayer_game.exe'" get ProcessId /value ^| find "="') do (
    if "%%a" neq "!pid1!" set pid2=%%a
)

rem ---- Start client #2 ----
start "" zig_multiplayer_game.exe --client-id 2
for /f "tokens=2 delims==;" %%a in ('wmic process where "name='zig_multiplayer_game.exe'" get ProcessId /value ^| find "="') do (
    if "%%a" neq "!pid1!" if "%%a" neq "!pid2!" set pid3=%%a
)

echo Started:
echo   Server PID: !pid1!
echo   Client1 PID: !pid2!
echo   Client2 PID: !pid3!
echo.

pause

echo Killing processes...
taskkill /PID !pid1! /T /F >nul 2>&1
taskkill /PID !pid2! /T /F >nul 2>&1
taskkill /PID !pid3! /T /F >nul 2>&1

echo Done.