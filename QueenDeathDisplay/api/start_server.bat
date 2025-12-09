@echo off
echo Starting Queen Death Display Web Server...
echo.
cd /d "%~dp0"

REM Try port 8082 first (default), then try alternatives if needed
python web_server.py 8082
if errorlevel 1 (
    echo.
    echo Port 8082 busy, trying port 8083...
    python web_server.py 8083
    if errorlevel 1 (
        echo.
        echo Port 8083 busy, trying port 8084...
        python web_server.py 8084
    )
)

pause

