@echo off
setlocal
pushd "%~dp0"
if not exist "tools\maplab\collect.py" (
  popd
  pushd "%~dp0\..\.."
)
where py >nul 2>nul
if errorlevel 1 (
  python tools\maplab\collect.py %*
) else (
  py -3 tools\maplab\collect.py %*
)
set "maplab_result=%errorlevel%"
if not "%maplab_result%"=="0" echo Collection failed. Keep this message; no game files were changed.
pause
popd
exit /b %maplab_result%
