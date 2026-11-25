@echo off
chcp 65001 >nul
rem BRMod: оффлайн-катка с тремя тупыми ботами для проверки мода.
set "GAMEDIR=%~dp0.."
if not exist "%GAMEDIR%\Buckshot Roulette.exe" goto wrongplace
findstr /c:"BRMod" "%GAMEDIR%\override.cfg" >nul 2>&1 || call "%~dp0install.bat"
echo.
echo  Катка с 3 ботами (боты просто стреляют наугад).
echo  Клавиши для проверки:
echo    F5  - дать себе следующий новый предмет (по кругу)
echo    F6  - убрать все свои предметы
echo    F7  - патрон в стволе = жёлтый (скрытый)
echo    F8  - патрон в стволе = розовый (лечащий)
echo    F9  - восстановить всем здоровье
echo    F10 - особые патроны при следующей перезарядке
echo    G   - автодоставание предметов (во время раздачи)
echo.
cd /d "%GAMEDIR%"
start "" "Buckshot Roulette.exe" -- --brmod-bots
exit /b 0

:wrongplace
echo  Папка BRMod должна лежать рядом с "Buckshot Roulette.exe".
pause
exit /b 1
