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
REM Run from the project root so the diff, pathspecs and 'git apply' all agree
REM on paths no matter which directory openc3.bat was started from.
cd /d "%REPO_ROOT%"
if exist "%REPO_ROOT%\openc3-enterprise-traefik" (
    set IS_ENTERPRISE=true
) else (
    set IS_ENTERPRISE=false
)

REM Files the user owns. COSMOS never ships these, so the upgrade must never
REM touch them. Without the exclude, a committed compose.override.yaml shows up
REM in 'git diff -R TAG' as a deletion (it doesn't exist in the tag) and would
REM be removed. plugins/ holds the user's own plugins.
set EXCLUDE_PATHSPECS=":(exclude)plugins/" ":(exclude)compose.override.yaml" ":(exclude).env.local"

REM Check if arguments are provided
if "%1"=="" goto usage

REM Check for help flag
if "%1"=="--help" goto usage
if "%1"=="-h" goto usage

set TAG=%1

REM Determine whether the target is core or enterprise
echo %1 | findstr /i "enterprise" >nul 2>&1
if "%IS_ENTERPRISE%"=="true" (
    set UPGRADING_TO_ENTERPRISE=true
) else if %errorlevel% equ 0 (
    set UPGRADING_TO_ENTERPRISE=true
) else (
    set UPGRADING_TO_ENTERPRISE=false
)

REM Strip a leading "enterprise-" from the tag argument if present
echo %1 | findstr /b /i "enterprise-" >nul 2>&1
if %errorlevel% equ 0 (
    set TAG=%1
    set TAG=!TAG:enterprise-=!
)

REM OPENC3_UPGRADE_REEXEC is set when this script was started by an older
REM version of itself (see below), which already set up the remote and fetched.
if defined OPENC3_UPGRADE_REEXEC goto validate_tag

REM Setup the 'cosmos' remote for core or enterprise
if "%UPGRADING_TO_ENTERPRISE%"=="true" (
    set COSMOS_URL=https://github.com/OpenC3/cosmos-enterprise-project.git
    set REMOTE_DESC=enterprise
) else (
    set COSMOS_URL=https://github.com/OpenC3/cosmos-project.git
    set REMOTE_DESC=core
)
git remote -v | findstr /b "cosmos " >nul 2>&1
if !errorlevel! equ 0 (
    echo Setting 'cosmos' remote to the !REMOTE_DESC! repository.
    git remote set-url cosmos !COSMOS_URL!
) else (
    echo Adding 'cosmos' remote for the !REMOTE_DESC! repository.
    git remote add cosmos !COSMOS_URL!
)

REM Fetch the latest changes from the 'cosmos' remote
echo Fetching latest changes from 'cosmos' remote.
git fetch cosmos --tags

:validate_tag
REM Check the tag is valid (native git lookup, tolerant of findstr/line-ending quirks)
git rev-parse --verify "refs/tags/%TAG%" >nul 2>&1
if errorlevel 1 (
    echo Error: '%TAG%' is not a valid git tag.
    echo Available tags:
    git tag | sort
    goto usage
)

REM Run the upgrade logic from the version being installed rather than this
REM (older) copy, so fixes to the upgrade itself - like new files to exclude -
REM apply to the upgrade that delivers them. Only hand off to a script that
REM knows about OPENC3_UPGRADE_REEXEC; an older tag's script would hand back.
REM --filters applies .gitattributes so the copy gets the CRLF endings cmd needs.
if defined OPENC3_UPGRADE_REEXEC goto confirm
set NEW_SCRIPT=%TEMP%\openc3_upgrade_%RANDOM%%RANDOM%.bat
git cat-file --filters "refs/tags/%TAG%:scripts/windows/openc3_upgrade.bat" > "%NEW_SCRIPT%" 2>nul
if errorlevel 1 goto cleanup_new_script
findstr /c:"OPENC3_UPGRADE_REEXEC" "%NEW_SCRIPT%" >nul 2>&1
if errorlevel 1 goto cleanup_new_script
echo Running the upgrade script from '%TAG%'.
set OPENC3_UPGRADE_REEXEC=1
call "%NEW_SCRIPT%" %*
set NEW_SCRIPT_RESULT=!errorlevel!
del "%NEW_SCRIPT%" >nul 2>&1
exit /b !NEW_SCRIPT_RESULT!

:cleanup_new_script
del "%NEW_SCRIPT%" >nul 2>&1

:confirm
REM Warn if upgrading from core to enterprise (but not if just previewing)
if "%IS_ENTERPRISE%"=="false" if "%UPGRADING_TO_ENTERPRISE%"=="true" if not "%2"=="--preview" (
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

REM If the --preview flag is set, show the diff without applying changes
if "%2"=="--preview" (
    git diff -R "refs/tags/%TAG%" -- . %EXCLUDE_PATHSPECS%
    exit /b 0
)

REM Apply the changes
git diff -R "refs/tags/%TAG%" --binary -- . %EXCLUDE_PATHSPECS% | git apply --whitespace=fix
echo Applied changes from tag '%1'.
echo We recommend committing these changes to your local repository.
echo e.g. git commit -am "Upgrade to %1"
echo You can now run 'openc3.bat run' to start the upgraded OpenC3 environment.
echo.
GOTO :EOF

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
