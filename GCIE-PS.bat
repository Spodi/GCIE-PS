:: This is a wrapper to start the PowerShell script in the
:: same directory with the same name automatically.
:: PowerShell is a bit paranoid about starting scripts otherwise.
:: This also takes care of things if called from a 32-bit app.
@echo off
title %~n0
:: color 17
if exist "%systemroot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" (
	call %systemroot%\SysNative\WindowsPowerShell\v1.0\powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%~dpn0.ps1" %*
) else (
	call %systemroot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%~dnp0.ps1" %*
)
EXIT /b %errorlevel%