@echo off
cd /d "%~dp0.."
where node >nul 2>nul
if errorlevel 1 (echo Install Node.js 20.16 or newer first. & exit /b 1)
call npm ci
if errorlevel 1 exit /b 1
call npm run dev
