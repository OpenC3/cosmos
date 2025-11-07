@echo off
setlocal ENABLEDELAYEDEXPANSION

REM Detect if this is a development (build) environment or runtime environment
REM by checking for compose-build.yaml
set OPENC3_DEVEL=0
if exist "%~dp0compose-build.yaml" (
  set OPENC3_DEVEL=1
)

if "%1" == "" (
  GOTO usage
)
if "%1" == "--help" (
  GOTO usage
)
if "%1" == "-h" (
  GOTO usage
)
if "%1" == "cli" (
  REM tokens=* means process the full line
  REM findstr /V = print lines that don't match, /B beginning of line, /L literal search string, /C:# match #
  FOR /F "tokens=*" %%i in ('findstr /V /B /L /C:# %~dp0.env') do SET %%i
  set params=%*
  call set params=%%params:*%1=%%
  REM Start (and remove when done --rm) the openc3-cosmos-cmd-tlm-api container with the current working directory
  REM mapped as volume (-v) /openc3/local and container working directory (-w) also set to /openc3/local.
  REM This allows tools running in the container to have a consistent path to the current working directory.
  REM Run the command "ruby /openc3/bin/openc3cli" with all parameters ignoring the first.
  docker compose -f %~dp0compose.yaml run -it --rm -v %cd%:/openc3/local -w /openc3/local -e OPENC3_API_PASSWORD=!OPENC3_API_PASSWORD! --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli !params!
  GOTO :EOF
)
if "%1" == "cliroot" (
  FOR /F "tokens=*" %%i in ('findstr /V /B /L /C:# %~dp0.env') do SET %%i
  set params=%*
  call set params=%%params:*%1=%%
  docker compose -f %~dp0compose.yaml run -it --rm --user=root -v %cd%:/openc3/local -w /openc3/local -e OPENC3_API_PASSWORD=!OPENC3_API_PASSWORD! --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli !params!
  GOTO :EOF
)
if "%1" == "start" (
  GOTO startup
)
if "%1" == "stop" (
  GOTO stop
)
if "%1" == "cleanup" (
  GOTO cleanup
)
if "%1" == "build" (
  GOTO build
)
if "%1" == "run" (
  GOTO run
)
if "%1" == "test" (
  GOTO test
)
if "%1" == "upgrade" (
  GOTO upgrade
)
if "%1" == "util" (
  FOR /F "tokens=*" %%i in ('findstr /V /B /L /C:# %~dp0.env') do SET %%i
  GOTO util
)

GOTO usage

:startup
  if "%OPENC3_DEVEL%" == "1" (
    CALL openc3 build || exit /b
    docker compose -f compose.yaml up -d
  ) else (
    docker compose -f compose.yaml up -d
  )
  @echo off
GOTO :EOF

:stop
  docker compose stop openc3-operator
  docker compose stop openc3-cosmos-script-runner-api
  docker compose stop openc3-cosmos-cmd-tlm-api
  timeout /t 5 /nobreak
  docker compose -f compose.yaml down -t 30
  @echo off
GOTO :EOF

:cleanup
  if "%2" == "force" (
    goto :cleanup_y
  )
  if "%3" == "force" (
    goto :cleanup_y
  )

:try_cleanup
  set /P c=Are you sure? Cleanup removes ALL docker volumes and all COSMOS data! [Y/N]?
  if /I "!c!" EQU "Y" goto :cleanup_y
  if /I "!c!" EQU "N" goto :EOF
goto :try_cleanup

:cleanup_y
  docker compose -f compose.yaml down -t 30 -v

  if "%2" == "local" (
    FOR /d %%a IN (%~dp0plugins\DEFAULT\*) DO RD /S /Q "%%a"
    FOR %%a IN (%~dp0plugins\DEFAULT\*) DO IF /i NOT "%%~nxa"=="README.md" DEL "%%a"
  )
  @echo off
GOTO :EOF

:build
  if "%OPENC3_DEVEL%" == "0" (
    @echo Error: 'build' command is only available in development environments 1>&2
    @echo This appears to be a runtime-only installation. 1>&2
    exit /b 1
  )
  CALL scripts\windows\openc3_setup || exit /b
  docker compose -f compose.yaml -f compose-build.yaml build openc3-ruby || exit /b
  docker compose -f compose.yaml -f compose-build.yaml build openc3-base || exit /b
  docker compose -f compose.yaml -f compose-build.yaml build openc3-node || exit /b
  docker compose -f compose.yaml -f compose-build.yaml build || exit /b
  @echo off
GOTO :EOF

:run
  docker compose -f compose.yaml up -d
  @echo off
GOTO :EOF

:test
  REM Building OpenC3
  CALL scripts\windows\openc3_setup || exit /b
  docker compose -f compose.yaml -f compose-build.yaml build
  set args=%*
  call set args=%%args:*%1=%%
  REM Running tests
  CALL scripts\windows\openc3_test %args% || exit /b
  @echo off
GOTO :EOF

:upgrade
  if "%OPENC3_DEVEL%" == "1" (
    @echo Error: 'upgrade' command is only available in runtime environments 1>&2
    @echo This appears to be a development installation. 1>&2
    exit /b 1
  )
  REM Send the remaining arguments to openc3_upgrade
  set args=%*
  call set args=%%args:*%1=%%
  CALL scripts\windows\openc3_upgrade %args% || exit /b
GOTO :EOF

:util
  REM Send the remaining arguments to openc3_util
  set args=%*
  call set args=%%args:*%1=%%
  CALL scripts\windows\openc3_util %args% || exit /b
  @echo off
GOTO :EOF

:usage
  if "%OPENC3_DEVEL%" == "1" (
    @echo OpenC3 - Command and Control System (Development Installation) 1>&2
  ) else (
    @echo OpenC3 - Command and Control System (Runtime-Only Installation) 1>&2
  )
  @echo Usage: %0 COMMAND [OPTIONS] 1>&2
  @echo. 1>&2
  @echo DESCRIPTION: 1>&2
  @echo   OpenC3 is a command and control system for embedded systems. This script 1>&2
  if "%OPENC3_DEVEL%" == "1" (
    @echo   provides a convenient interface for building, running, testing, and managing 1>&2
    @echo   OpenC3 in Docker containers. 1>&2
    @echo. 1>&2
    @echo   This is a DEVELOPMENT installation with source code and build capabilities. 1>&2
  ) else (
    @echo   provides a convenient interface for running, testing, and managing 1>&2
    @echo   OpenC3 in Docker containers. 1>&2
    @echo. 1>&2
    @echo   This is a RUNTIME-ONLY installation using pre-built images. 1>&2
  )
  @echo. 1>&2
  @echo COMMON COMMANDS: 1>&2
  if "%OPENC3_DEVEL%" == "1" (
    @echo   start                 Build and run OpenC3 (equivalent to: build + run) 1>&2
    @echo                         This is the typical command to get OpenC3 running. 1>&2
    @echo. 1>&2
  ) else (
    @echo   run                   Start OpenC3 containers 1>&2
    @echo                         Access at: http://localhost:2900 1>&2
    @echo. 1>&2
  )
  @echo   stop                  Stop all running OpenC3 containers gracefully 1>&2
  @echo                         Allows containers to shutdown cleanly. 1>&2
  @echo. 1>&2
  @echo   cli [COMMAND]         Run OpenC3 CLI commands in a container 1>&2
  @echo                         Use 'cli help' for available commands 1>&2
  @echo                         Examples: 1>&2
  @echo                           %0 cli generate plugin MyPlugin 1>&2
  @echo                           %0 cli validate myplugin.gem 1>&2
  @echo. 1>&2
  @echo   cliroot [COMMAND]     Run OpenC3 CLI commands as root user 1>&2
  @echo                         For operations requiring root privileges 1>&2
  @echo. 1>&2
  if "%OPENC3_DEVEL%" == "1" (
    @echo DEVELOPMENT COMMANDS: 1>&2
    @echo   build                 Build all OpenC3 Docker containers from source 1>&2
    @echo                         Required before first run or after code changes. 1>&2
    @echo. 1>&2
    @echo   run                   Start OpenC3 containers in detached mode 1>&2
    @echo                         Access at: http://localhost:2900 1>&2
    @echo. 1>&2
  )
  @echo   test [COMMAND]        Run test suites (rspec, playwright) 1>&2
  @echo                         Use '%0 test' to see available test commands. 1>&2
  @echo. 1>&2
  @echo   util [COMMAND]        Utility commands (encode, hash, etc.) 1>&2
  @echo                         Use '%0 util' to see available utilities. 1>&2
  @echo. 1>&2
  if "%OPENC3_DEVEL%" == "0" (
    @echo   upgrade               Upgrade OpenC3 to latest version 1>&2
    @echo                         Downloads and installs latest release. 1>&2
    @echo. 1>&2
  )
  @echo CLEANUP: 1>&2
  @echo   cleanup [OPTIONS]     Remove Docker volumes and data 1>&2
  @echo                         WARNING: This deletes all OpenC3 data! 1>&2
  @echo                         Options: 1>&2
  @echo                           local  - Also remove local plugin files 1>&2
  @echo                           force  - Skip confirmation prompt 1>&2
  @echo. 1>&2
  @echo GETTING STARTED: 1>&2
  @echo   1. First time setup:     %0 start 1>&2
  @echo   2. Access OpenC3:        http://localhost:2900 1>&2
  @echo   3. Stop when done:       %0 stop 1>&2
  @echo   4. Remove everything:    %0 cleanup 1>&2
  @echo. 1>&2
  @echo MORE INFORMATION: 1>&2
  @echo   Documentation: https://docs.openc3.com 1>&2
  @echo. 1>&2
  @echo OPTIONS: 1>&2
  @echo   -h, --help            Show this help message 1>&2
  @echo. 1>&2

@echo on
