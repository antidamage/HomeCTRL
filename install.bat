@echo off
REM Local AI Stack Installer - Windows Wrapper
REM This script runs the installer in WSL or Git Bash

echo Local AI Stack Installer - Windows Wrapper
echo ==========================================
echo.
echo This installer is designed EXCLUSIVELY for Ubuntu 22.04 LTS
echo.
echo To use this installer on Windows, you MUST:
echo 1. Install WSL2 with Ubuntu 22.04 LTS (RECOMMENDED)
echo 2. OR run this on a native Ubuntu 22.04 LTS server
echo.
echo The installer will NOT work with other Linux distributions
echo or other WSL2 distributions.
echo.
echo For WSL2 installation, visit: https://docs.microsoft.com/en-us/windows/wsl/install
echo.
echo Other usages are unsupported.
echo.
echo Press any key to continue...
pause >nul

REM Check if WSL is available
wsl --version >nul 2>&1
if %errorlevel% equ 0 (
    echo WSL detected! Running installer in WSL...
    echo.
    wsl bash -c "cd /mnt/$(echo %cd% | sed 's/://' | sed 's/\\/\//g') && chmod +x install.sh && ./install.sh"
) else (
    echo WSL not detected.
    echo.
    echo Please install WSL2 with Ubuntu 22.04 LTS.
    echo.
    echo This installer is designed EXCLUSIVELY for Ubuntu 22.04 LTS
    echo and will not work with other Linux distributions.
    echo.
    echo For more information, visit: https://github.com/your-repo/HomeAI
    pause
)
