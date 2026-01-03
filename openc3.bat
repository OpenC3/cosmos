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
    docker compose -f %~dp0compose.yaml run -it --rm -v %cd%:/openc3/local -w /openc3/local -e OPENC3_API_USER=!OPENC3_API_USER! -e OPENC3_API_PASSWORD=!OPENC3_API_PASSWORD! --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli !params!
  ) else (
    docker compose -f %~dp0compose.yaml run -it --rm -v %cd%:/openc3/local -w /openc3/local -e OPENC3_API_PASSWORD=!OPENC3_API_PASSWORD! --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli !params!
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
    docker compose -f %~dp0compose.yaml run -it --rm --user=root -v %cd%:/openc3/local -w /openc3/local -e OPENC3_API_USER=!OPENC3_API_USER! -e OPENC3_API_PASSWORD=!OPENC3_API_PASSWORD! --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli !params!
  ) else (
    docker compose -f %~dp0compose.yaml run -it --rm --user=root -v %cd%:/openc3/local -w /openc3/local -e OPENC3_API_PASSWORD=!OPENC3_API_PASSWORD! --no-deps openc3-cosmos-cmd-tlm-api ruby /openc3/bin/openc3cli !params!
  )
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
if "%1" == "generate_compose" (
  GOTO generate_compose
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
  if "%OPENC3_ENTERPRISE%" == "1" (
    docker compose stop openc3-metrics
  )
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
  set /P c=Are you sure? Cleanup removes ALL docker volumes and all %COSMOS_NAME% data! [Y/N]?
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
  if "%OPENC3_ENTERPRISE%" == "1" (
    docker compose -f compose.yaml -f compose-build.yaml build openc3-enterprise-gem || exit /b
  ) else (
    docker compose -f compose.yaml -f compose-build.yaml build openc3-ruby || exit /b
    docker compose -f compose.yaml -f compose-build.yaml build openc3-base || exit /b
    docker compose -f compose.yaml -f compose-build.yaml build openc3-node || exit /b
  )
  docker compose -f compose.yaml -f compose-build.yaml build || exit /b
  @echo off
GOTO :EOF

:run
  docker compose -f compose.yaml up -d
  @echo off
GOTO :EOF

:dev
  docker compose -f compose.yaml -f compose-dev.yaml up -d
  @echo off
GOTO :EOF

:test
  REM Building COSMOS
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

:generate_compose
  REM Check for help flag
  if "%2" == "--help" GOTO generate_compose_help
  if "%2" == "-h" GOTO generate_compose_help

  REM Check if Python 3 is available
  python --version >nul 2>&1
  if errorlevel 1 (
    echo Error: python is required but not found
    echo Please install Python 3 to use this command
    exit /b 1
  )

  REM Check if PyYAML is installed, install if missing
  python -c "import yaml" >nul 2>&1
  if errorlevel 1 (
    echo PyYAML not found, installing...
    python -m pip install --user pyyaml >nul 2>&1
    if errorlevel 1 (
      echo Error: Failed to install PyYAML automatically
      echo Please install it manually with: pip install pyyaml
      exit /b 1
    )
    echo * PyYAML installed successfully
  )

  REM Detect mode based on OPENC3_ENTERPRISE
  if "%OPENC3_ENTERPRISE%" == "1" (
    set MODE=enterprise
    REM Enterprise uses the template from core repo
    if exist "%~dp0..\cosmos\scripts\release\generate_compose.py" (
      set GENERATOR=%~dp0..\cosmos\scripts\release\generate_compose.py
      set TEMPLATE=%~dp0..\cosmos\compose.yaml.template
    ) else (
      echo Error: Cannot find generate_compose.py in ..\cosmos\scripts\release\
      echo Make sure the cosmos repository is checked out in the parent directory.
      exit /b 1
    )
  ) else (
    set MODE=core
    set GENERATOR=%~dp0scripts\release\generate_compose.py
    set TEMPLATE=
  )

  REM Build arguments for the generator
  set ARGS=--mode %MODE%

  REM Add template path for enterprise
  if defined TEMPLATE (
    set ARGS=%ARGS% --template %TEMPLATE%
  )

  REM Pass through any additional arguments (like --dry-run, --output)
  set params=%*
  call set params=%%params:*%1=%%
  if not "%params%" == "" (
    set ARGS=%ARGS% %params%
  )

  REM Run the generator
  python %GENERATOR% %ARGS%
  GOTO :EOF

:generate_compose_help
  echo Usage: %0 generate_compose [OPTIONS]
  echo.
  echo Generate compose.yaml from template and mode-specific overrides.
  echo.
  echo This command uses a template-based system to generate compose.yaml files
  echo for both OpenC3 Core and Enterprise editions. It ensures that shared
  echo configuration stays in sync while allowing edition-specific customizations.
  echo.
  echo Files used:
  if "%OPENC3_ENTERPRISE%" == "1" (
    echo   - Template:  ..\cosmos\compose.yaml.template
    echo   - Overrides: .\compose.enterprise.yaml
    echo   - Output:    .\compose.yaml
  ) else (
    echo   - Template:  .\compose.yaml.template
    echo   - Overrides: .\compose.core.yaml
    echo   - Output:    .\compose.yaml
  )
  echo.
  echo How it works:
  echo   1. The template file contains placeholders like {{REGISTRY_VAR}}, {{IMAGE_PREFIX}}, etc.
  echo   2. The override file defines the actual values for these placeholders
  echo   3. The script merges the template with the overrides to produce compose.yaml
  echo.
  echo Options:
  echo   --dry-run             Print output to stdout instead of writing to file
  echo   --output PATH         Custom output file path (default: .\compose.yaml)
  echo   -h, --help            Show this help message
  echo.
  echo Examples:
  echo   %0 generate_compose                    # Generate compose.yaml
  echo   %0 generate_compose --dry-run          # Preview without writing
  echo   %0 generate_compose --output test.yaml # Write to custom path
  echo.
  echo Making changes:
  echo   - To change shared config:    Edit compose.yaml.template
  echo   - To change core-specific:    Edit compose.core.yaml
  echo   - To change enterprise-specific: Edit compose.enterprise.yaml
  echo.
  echo After editing, regenerate compose.yaml for both core and enterprise.
  echo.
  echo Benefits:
  echo   - Single source of truth for shared configuration
  echo   - No manual syncing needed between core and enterprise
  echo   - Clear visibility of what's different between editions
  echo   - Automated generation prevents copy-paste errors
  GOTO :EOF

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
  @echo   generate_compose      Generate compose.yaml from template 1>&2
  @echo                         Merges template with core/enterprise overrides. 1>&2
  @echo                         Use '%0 generate_compose --help' for details. 1>&2
  @echo. 1>&2
  if "%OPENC3_DEVEL%" == "0" (
    @echo   upgrade               Upgrade %COSMOS_NAME% to latest version 1>&2
    @echo                         Downloads and installs latest release. 1>&2
    @echo. 1>&2
  )
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
