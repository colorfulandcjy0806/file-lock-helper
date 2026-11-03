@echo off
set "SCRIPT=%~dp0FileLockHelper.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%SCRIPT%"
