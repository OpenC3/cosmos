@echo off
setlocal ENABLEDELAYEDEXPANSION

REM Detect if this is a development (build) environment or runtime environment
REM by checking for compose-build.yaml
set OPENC3_DEVEL=0
if exist "%~dp0compose-build.yaml" (
  set OPENC3_DEVEL=1
)

REM Detect if this is enterprise by checking for enterprise-specific services
set OPENC3_ENTERPRISE=0
if exist "%~dp0compose-build.yaml" (
  findstr /C:"openc3-enterprise-gem" "%~dp0compose-build.yaml" >nul 2>&1
  if !ERRORLEVEL! == 0 (
    set OPENC3_ENTERPRISE=1
  )
)
if !OPENC3_ENTERPRISE! == 0 (
  if exist "%~dp0compose.yaml" (
    findstr /C:"openc3-metrics" "%~dp0compose.yaml" >nul 2>&1
    if !ERRORLEVEL! == 0 (
      set OPENC3_ENTERPRISE=1
    )
  )
)

REM Set display name based on enterprise flag
if "%OPENC3_ENTERPRISE%" == "1" (
  set COSMOS_NAME=COSMOS Enterprise
) else (
  set COSMOS_NAME=COSMOS Core
)

REM Detect container runtime (docker or podman)
set CONTAINER_CMD=
where docker >nul 2>&1 && set CONTAINER_CMD=docker
if not defined CONTAINER_CMD (
  where podman >nul 2>&1 && set CONTAINER_CMD=podman
)
if not defined CONTAINER_CMD (
  echo Neither docker nor podman found! 1>&2
  exit /b 1
)

REM Detect compose command. Never fall back to podman-compose; COSMOS only
REM supports docker-compose as the standalone compose tool, even under podman.
set CONTAINER_COMPOSE_CMD=
%CONTAINER_CMD% compose version >nul 2>&1 && set CONTAINER_COMPOSE_CMD=%CONTAINER_CMD% compose
if not defined CONTAINER_COMPOSE_CMD (
  where docker-compose >nul 2>&1 && set CONTAINER_COMPOSE_CMD=docker-compose
)
if not defined CONTAINER_COMPOSE_CMD (
  echo No compose command found! 1>&2
  exit /b 1
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
  REM Start (and remove when done --rm) the cmd-tlm-api container with the current working directory
  REM mapped as volume (-v) /openc3/local and container working directory (-w) also set to /openc3/local.
  REM This allows tools running in the container to have a consistent path to the current working directory.
  REM Run the command "ruby /openc3/bin/openc3cli" with all parameters ignoring the first.
  REM Note: The service name is always openc3-cosmos-cmd-tlm-api; compose.yaml pulls the correct image
  REM (enterprise or non-enterprise) based on environment variables.
  if "%OPENC3_ENTERPRISE%" == "1" (
    !CONTAINER_COMPOSE_CMD! -f %~dp0compose.yaml run -it --rm -v %cd%:/openc3/local -w /openc3/local -e OPENC3_API_USER=!OPENC3_API_USER! -e OPENC3_API_PASSWORD=!OPENC3_API_PASSWORD! --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli !params!
  ) else (
    !CONTAINER_COMPOSE_CMD! -f %~dp0compose.yaml run -it --rm -v %cd%:/openc3/local -w /openc3/local -e OPENC3_API_PASSWORD=!OPENC3_API_PASSWORD! --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli !params!
  )
  GOTO :EOF
)
if "%1" == "cliroot" (
  FOR /F "tokens=*" %%i in ('findstr /V /B /L /C:# %~dp0.env') do SET %%i
  set params=%*
  call set params=%%params:*%1=%%
  REM Note: The service name is always openc3-cosmos-cmd-tlm-api; compose.yaml pulls the correct image
  REM (enterprise or non-enterprise) based on environment variables.
  if "%OPENC3_ENTERPRISE%" == "1" (
    !CONTAINER_COMPOSE_CMD! -f %~dp0compose.yaml run -it --rm --user=root -v %cd%:/openc3/local -w /openc3/local -e OPENC3_API_USER=!OPENC3_API_USER! -e OPENC3_API_PASSWORD=!OPENC3_API_PASSWORD! --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli !params!
  ) else (
    !CONTAINER_COMPOSE_CMD! -f %~dp0compose.yaml run -it --rm --user=root -v %cd%:/openc3/local -w /openc3/local -e OPENC3_API_PASSWORD=!OPENC3_API_PASSWORD! --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli !params!
  )
  GOTO :EOF
)
if "%1" == "start" (
  GOTO startup
)
if "%1" == "stop" (
  GOTO stop
)
if "%1" == "list" (
  GOTO list
)
if "%1" == "status" (
  GOTO status
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
if "%1" == "dev" (
  GOTO dev
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
    !CONTAINER_COMPOSE_CMD! -f compose.yaml up -d
  ) else (
    !CONTAINER_COMPOSE_CMD! -f compose.yaml up -d
  )
  @echo off
GOTO :EOF

:stop
  !CONTAINER_COMPOSE_CMD! stop openc3-operator
  !CONTAINER_COMPOSE_CMD! stop openc3-cosmos-script-runner-api
  !CONTAINER_COMPOSE_CMD! stop openc3-cosmos-cmd-tlm-api
  if "%OPENC3_ENTERPRISE%" == "1" (
    !CONTAINER_COMPOSE_CMD! stop openc3-metrics
  )
  timeout /t 5 /nobreak
  !CONTAINER_COMPOSE_CMD! -f compose.yaml down -t 30
  @echo off
GOTO :EOF

:list
  REM Build the list of compose files to query
  set "COMPOSE_FILES=-f %~dp0compose.yaml"
  if "%OPENC3_DEVEL%" == "1" (
    if exist "%~dp0compose-build.yaml" (
      set "COMPOSE_FILES=!COMPOSE_FILES! -f %~dp0compose-build.yaml"
    )
  )
  REM Get image repositories from compose config
  REM Strip docker.io/ prefix and :tag suffix so we match all tags per repository
  set "FILTER_ARGS="
  for /f "delims=" %%i in ('docker compose !COMPOSE_FILES! config --images 2^>nul') do (
    set "IMG=%%i"
    set "IMG=!IMG:docker.io/=!"
    REM Strip :tag suffix by splitting on colon
    for /f "tokens=1 delims=:" %%r in ("!IMG!") do set "REPO=%%r"
    REM Check if any local images exist for this repository
    for /f %%q in ('docker images -q "!REPO!" 2^>nul') do (
      set "FILTER_ARGS=!FILTER_ARGS! --filter reference=!REPO!"
    )
  )
  if "!FILTER_ARGS!" == "" (
    @echo No %COSMOS_NAME% images found locally.
    GOTO :EOF
  )
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}" !FILTER_ARGS!
  @echo off
GOTO :EOF

:status
  docker compose -f %~dp0compose.yaml ps
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
  set /P c=Are you sure? Cleanup removes ALL docker volumes and all %COSMOS_NAME% data! [Y/N]?
  if /I "!c!" EQU "Y" goto :cleanup_y
  if /I "!c!" EQU "N" goto :EOF
goto :try_cleanup

:cleanup_y
  !CONTAINER_COMPOSE_CMD! -f compose.yaml down -t 30 -v

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
  if "%OPENC3_ENTERPRISE%" == "1" (
    REM Enterprise: build core images first when OPENC3_TAG=latest, then enterprise
    CALL :build_core_images
    !CONTAINER_COMPOSE_CMD! -f compose.yaml -f compose-build.yaml build openc3-enterprise-gem || GOTO :pull_failed
  ) else (
    !CONTAINER_COMPOSE_CMD! -f compose.yaml -f compose-build.yaml build openc3-ruby || GOTO :pull_failed
    !CONTAINER_COMPOSE_CMD! -f compose.yaml -f compose-build.yaml build openc3-base || GOTO :pull_failed
    !CONTAINER_COMPOSE_CMD! -f compose.yaml -f compose-build.yaml build openc3-node || GOTO :pull_failed
  )
  !CONTAINER_COMPOSE_CMD! -f compose.yaml -f compose-build.yaml build || GOTO :pull_failed
  @echo off
GOTO :EOF

:run
  !CONTAINER_COMPOSE_CMD! -f compose.yaml up -d || GOTO :pull_failed
  @echo off
GOTO :EOF

:dev
  !CONTAINER_COMPOSE_CMD! -f compose.yaml -f compose-dev.yaml up -d
  @echo off
GOTO :EOF

:test
  REM Building COSMOS
  CALL scripts\windows\openc3_setup || exit /b
  !CONTAINER_COMPOSE_CMD! -f compose.yaml -f compose-build.yaml build
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

:resolve_openc3_tag
  REM Resolve OPENC3_TAG from the env file if not already set.
  if not defined OPENC3_TAG FOR /F "tokens=1,* delims==" %%a in ('findstr /B /C:"OPENC3_TAG=" "%~dp0.env" 2^>nul') do set "OPENC3_TAG=%%b"
  if not defined OPENC3_TAG set "OPENC3_TAG=latest"
  exit /b 0

:build_core_images
  REM Build all core images from the sibling cosmos repo when OPENC3_TAG=latest.
  CALL :resolve_openc3_tag
  if not "!OPENC3_TAG!" == "latest" exit /b 0
  set "CORE_DIR=%~dp0..\cosmos"
  if exist "!CORE_DIR!\compose-build.yaml" (
    @echo Building core images from !CORE_DIR! ...
    !CONTAINER_COMPOSE_CMD! --project-directory "!CORE_DIR!" -f "!CORE_DIR!\compose.yaml" -f "!CORE_DIR!\compose-build.yaml" build || exit /b
  ) else (
    @echo Warning: Core repo not found at !CORE_DIR! — using existing latest tagged images
  )
  exit /b 0

REM Reached when a compose build/run fails. We do NOT login automatically:
REM forcing a login would require credentials for public registries (e.g.
REM docker.io) and break air-gapped builds. Instead suggest logging in.
:pull_failed
  CALL :suggest_registry_login
  exit /b 1

:suggest_registry_login
  FOR /F "tokens=*" %%i in ('findstr /V /B /L /C:# %~dp0.env') do SET %%i
  @echo. 1>&2
  @echo The command failed. If this was a registry authentication error (403), 1>&2
  @echo login to the registry and retry the command: 1>&2
  if defined OPENC3_REGISTRY (
    @echo   !CONTAINER_CMD! login !OPENC3_REGISTRY! 1>&2
  )
  if "!OPENC3_ENTERPRISE!" == "1" (
    if defined OPENC3_ENTERPRISE_REGISTRY (
      @echo   !CONTAINER_CMD! login !OPENC3_ENTERPRISE_REGISTRY! 1>&2
    )
  )
  if not defined OPENC3_REGISTRY (
    @echo   !CONTAINER_CMD! login ^<registry^> 1>&2
  )
  exit /b 0

:usage
  if "%OPENC3_DEVEL%" == "1" (
    if "%OPENC3_ENTERPRISE%" == "1" (
      @echo OpenC3 COSMOS - Command and Control System (Enterprise Development Installation) 1>&2
    ) else (
      @echo OpenC3 COSMOS - Command and Control System (Development Installation) 1>&2
    )
  ) else (
    if "%OPENC3_ENTERPRISE%" == "1" (
      @echo OpenC3 COSMOS - Command and Control System (Enterprise Runtime-Only Installation) 1>&2
    ) else (
      @echo OpenC3 COSMOS - Command and Control System (Runtime-Only Installation) 1>&2
    )
  )
  @echo Usage: %0 COMMAND [OPTIONS] 1>&2
  @echo. 1>&2
  @echo DESCRIPTION: 1>&2
  @echo   %COSMOS_NAME% is a command and control system for embedded systems. This script 1>&2
  if "%OPENC3_DEVEL%" == "1" (
    @echo   provides a convenient interface for building, running, testing, and managing 1>&2
    @echo   %COSMOS_NAME% in Docker containers. 1>&2
    @echo. 1>&2
    if "%OPENC3_ENTERPRISE%" == "1" (
      @echo   This is an ENTERPRISE DEVELOPMENT installation with source code and build capabilities. 1>&2
    ) else (
      @echo   This is a DEVELOPMENT installation with source code and build capabilities. 1>&2
    )
  ) else (
    @echo   provides a convenient interface for running, testing, and managing 1>&2
    @echo   %COSMOS_NAME% in Docker containers. 1>&2
    @echo. 1>&2
    if "%OPENC3_ENTERPRISE%" == "1" (
      @echo   This is an ENTERPRISE RUNTIME-ONLY installation using pre-built images. 1>&2
    ) else (
      @echo   This is a RUNTIME-ONLY installation using pre-built images. 1>&2
    )
  )
  @echo. 1>&2
  @echo COMMON COMMANDS: 1>&2
  if "%OPENC3_DEVEL%" == "1" (
    @echo   start                 Build and run %COSMOS_NAME% (equivalent to: build + run) 1>&2
    @echo                         This is the typical command to get %COSMOS_NAME% running. 1>&2
    @echo. 1>&2
  ) else (
    @echo   run                   Start %COSMOS_NAME% containers 1>&2
    @echo                         Access at: http://localhost:2900 1>&2
    @echo. 1>&2
  )
  @echo   stop                  Stop all running %COSMOS_NAME% containers gracefully 1>&2
  @echo                         Allows containers to shutdown cleanly. 1>&2
  @echo. 1>&2
  @echo   cli [COMMAND]         Run %COSMOS_NAME% CLI commands in a container 1>&2
  @echo                         Use 'cli help' for available commands 1>&2
  @echo                         Examples: 1>&2
  @echo                           %0 cli generate plugin MyPlugin 1>&2
  @echo                           %0 cli validate myplugin.gem 1>&2
  @echo. 1>&2
  @echo   cliroot [COMMAND]     Run %COSMOS_NAME% CLI commands as root user 1>&2
  @echo                         For operations requiring root privileges 1>&2
  @echo. 1>&2
  if "%OPENC3_DEVEL%" == "1" (
    @echo DEVELOPMENT COMMANDS: 1>&2
    @echo   build                 Build all %COSMOS_NAME% Docker containers from source 1>&2
    @echo                         Required before first run or after code changes. 1>&2
    @echo. 1>&2
    @echo   run                   Start %COSMOS_NAME% containers in detached mode 1>&2
    @echo                         Access at: http://localhost:2900 1>&2
    @echo. 1>&2
    @echo   dev                   Start %COSMOS_NAME% containers in development mode 1>&2
    @echo                         Uses compose-dev.yaml for development. 1>&2
    @echo. 1>&2
  )
  @echo   test [COMMAND]        Run test suites (rspec, playwright) 1>&2
  @echo                         Use '%0 test' to see available test commands. 1>&2
  @echo. 1>&2
  @echo   util [COMMAND]        Utility commands (encode, hash, etc.) 1>&2
  @echo                         Use '%0 util' to see available utilities. 1>&2
  @echo. 1>&2
  if "%OPENC3_DEVEL%" == "0" (
    @echo   upgrade               Upgrade %COSMOS_NAME% to latest version 1>&2
    @echo                         Downloads and installs latest release. 1>&2
    @echo. 1>&2
  )
  @echo STATUS: 1>&2
  @echo   list                  List %COSMOS_NAME% Docker images for this installation 1>&2
  @echo                         Only shows images belonging to the current installation. 1>&2
  @echo. 1>&2
  @echo   status                Show container status for this %COSMOS_NAME% installation 1>&2
  @echo. 1>&2
  @echo CLEANUP: 1>&2
  @echo   cleanup [OPTIONS]     Remove Docker volumes and data 1>&2
  @echo                         WARNING: This deletes all %COSMOS_NAME% data! 1>&2
  @echo                         Options: 1>&2
  @echo                           local  - Also remove local plugin files 1>&2
  @echo                           force  - Skip confirmation prompt 1>&2
  @echo. 1>&2
  @echo GETTING STARTED: 1>&2
  @echo   1. First time setup:     %0 start 1>&2
  @echo   2. Access %COSMOS_NAME%:        http://localhost:2900 1>&2
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
