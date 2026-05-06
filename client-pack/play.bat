@echo off
REM ────────────────────────────────────────────────────────────────────
REM  MU PORCARIA — launcher do client MuMain
REM
REM  Troca SERVER pelo domínio (ou IP) do servidor.
REM  Porta 44406 é a default do MuMain no OpenMU.
REM ────────────────────────────────────────────────────────────────────

SET SERVER=seu-dominio.com
SET PORT=44406

cd /d "%~dp0"
main.exe connect /u%SERVER% /p%PORT%
