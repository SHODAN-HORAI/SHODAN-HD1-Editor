@echo off
echo Unlocks every weapon, stratagem, perk, armor and upgrade in your HELLDIVERS save.
echo Your rank and XP stay as they are. Paid DLC stays locked unless you own it.
echo Close the game first. Your old save is backed up.
echo.
pause
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0files\unlock.ps1"
pause
