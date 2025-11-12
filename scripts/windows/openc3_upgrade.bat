@echo off
setlocal enabledelayedexpansion

REM Check if git is available
git --version >nul 2>&1
if %errorlevel% neq 0 (
    echo git not found!!!
    exit /b 1
)

REM Determine if this is Core or Enterprise installation
for /f "delims=" %%i in ('git rev-parse --show-toplevel') do set REPO_ROOT=%%i
if exist "%REPO_ROOT%\openc3-enterprise-traefik" (
    set IS_ENTERPRISE=true
) else (
    set IS_ENTERPRISE=false
)

REM Function to display usage
:usage
    echo Usage: openc3.bat upgrade ^<tag^> --preview
    echo e.g. openc3.bat upgrade v6.4.1
    echo The '--preview' flag will show the diff without applying changes.
    if "%IS_ENTERPRISE%"=="false" (
        echo.
        echo You can also upgrade to Enterprise versions of OpenC3 if you have access
        echo e.g. openc3.bat upgrade enterprise-v6.4.1
        echo NOTE: Upgrading to Enterprise preserves all your existing data
        echo but is a one-way operation and cannot be undone.
    )
    exit /b 1

REM Check if arguments are provided
if "%1"=="" goto usage

REM Check for help flag
if "%1"=="--help" goto usage
if "%1"=="-h" goto usage

set TAG=%1

REM Setup the 'cosmos' remote based on IS_ENTERPRISE or if upgrading to enterprise
echo %1 | findstr /i "enterprise" >nul 2>&1
if "%IS_ENTERPRISE%"=="true" (
    set UPGRADING_TO_ENTERPRISE=true
) else if %errorlevel% equ 0 (
    set UPGRADING_TO_ENTERPRISE=true
) else (
    set UPGRADING_TO_ENTERPRISE=false
)

if "%UPGRADING_TO_ENTERPRISE%"=="true" (
    set COSMOS_URL=https://github.com/OpenC3/cosmos-enterprise-project.git
    git remote -v | findstr /b "cosmos " >nul 2>&1
    if %errorlevel% equ 0 (
        echo Setting 'cosmos' remote to the enterprise repository.
        git remote set-url cosmos !COSMOS_URL!
    ) else (
        echo Adding 'cosmos' remote for the enterprise repository.
        git remote add cosmos !COSMOS_URL!
    )

    REM Warn if upgrading from core to enterprise (but not if just previewing)
    if "%IS_ENTERPRISE%"=="false" if not "%2"=="--preview" (
        echo.
        echo WARNING: You are upgrading from OpenC3 Core to OpenC3 Enterprise.
        echo This is a ONE-WAY operation and CANNOT be undone.
        echo All your existing data will be preserved, but you will not be able
        echo to downgrade back to the Core version.
        echo.
        set /p CONFIRM="Are you sure you want to continue? (yes/no): "
        if /i not "!CONFIRM!"=="yes" (
            echo Upgrade cancelled.
            exit /b 1
        )
    )
) else (
    set COSMOS_URL=https://github.com/OpenC3/cosmos-project.git
    git remote -v | findstr /b "cosmos " >nul 2>&1
    if %errorlevel% equ 0 (
        echo Setting 'cosmos' remote to the core repository.
        git remote set-url cosmos !COSMOS_URL!
    ) else (
        echo Adding 'cosmos' remote for the core repository.
        git remote add cosmos !COSMOS_URL!
    )
)

REM Strip a leading "enterprise-" from the tag argument if present
echo %1 | findstr /b /i "enterprise-" >nul 2>&1
if %errorlevel% equ 0 (
    set TAG=%1:enterprise-=%
    set TAG=!TAG:enterprise-=!
)

REM Fetch the latest changes from the 'cosmos' remote
echo Fetching latest changes from 'cosmos' remote.
git fetch cosmos

REM Check the tag is valid
git tag | findstr /x "%TAG%" >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: '%TAG%' is not a valid git tag.
    echo Available tags:
    git tag | sort
    goto usage
)

REM Get the commit hash for the tag
for /f "tokens=1" %%a in ('git ls-remote cosmos refs/tags/%TAG%') do set HASH=%%a

REM If the --preview flag is set, show the diff without applying changes
if "%2"=="--preview" (
    git diff -R %HASH%
    exit /b 0
)

REM Apply the changes
git diff -R %HASH% | git apply --whitespace=fix --exclude="plugins/*"
echo Applied changes from tag '%1'.
echo We recommend committing these changes to your local repository.
echo e.g. git commit -am "Upgrade to %1"
echo You can now run 'openc3.bat run' to start the upgraded OpenC3 environment.
echo.
