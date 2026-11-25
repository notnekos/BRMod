@echo off
chcp 65001 >nul
set "GAMEDIR=%~dp0.."
if exist "%GAMEDIR%\override.cfg" (
  findstr /c:"BRMod" "%GAMEDIR%\override.cfg" >nul && del "%GAMEDIR%\override.cfg"
)
echo.
echo  BRMod выключен (override.cfg удалён). Папку BRMod можно удалить.
echo.
pause
