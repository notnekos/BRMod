@echo off
chcp 65001 >nul
rem BRMod installer: writes override.cfg next to "Buckshot Roulette.exe" so the game loads the mod.
set "MODDIR=%~dp0"
set "GAMEDIR=%~dp0.."
if not exist "%GAMEDIR%\Buckshot Roulette.exe" goto wrongplace
if exist "%GAMEDIR%\override.cfg" (
  findstr /c:"BRMod" "%GAMEDIR%\override.cfg" >nul || goto foreign
)
set "P=%MODDIR:\=/%brmod.gd"
> "%GAMEDIR%\override.cfg" echo [autoload]
>> "%GAMEDIR%\override.cfg" echo.
>> "%GAMEDIR%\override.cfg" echo BRMod="*%P%"
echo.
echo  BRMod установлен. Запускай игру через Steam.
echo  В меню рядом с версией должно появиться "+BRMod".
echo  Мод должен стоять у ВСЕХ игроков в лобби.
echo.
pause
exit /b 0

:wrongplace
echo.
echo  Папку BRMod нужно положить в папку игры, рядом с "Buckshot Roulette.exe":
echo  ...\steamapps\common\Buckshot Roulette\Buckshot Roulette_windows\BRMod
echo.
pause
exit /b 1

:foreign
echo.
echo  Рядом с игрой уже есть override.cfg от другого мода — не трогаю его.
echo  Добавь в него вручную строку в секцию [autoload]:
echo  BRMod="*%MODDIR:\=/%brmod.gd"
echo.
pause
exit /b 1
