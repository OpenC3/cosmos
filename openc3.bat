@echo off
setlocal ENABLEDELAYEDEXPANSION

if "%1" == "" (
  GOTO usage
)
if "%1" == "cli" (
  REM tokens=* means process the full line
  REM findstr /V = print lines that don't match, /B beginning of line, /L literal search string, /C:# match #
  FOR /F "tokens=*" %%i in ('findstr /V /B /L /C:# %~dp0.env') do SET %%i
  set params=%*
  call set params=%%params:*%1=%%
  REM Start (and remove when done --rm) the openc3-operator container with the current working directory
  REM mapped as volume (-v) /openc3/local and container working directory (-w) also set to /openc3/local.
  REM This allows tools running in the container to have a consistent path to the current working directory.
  REM Run the command "ruby /openc3/bin/openc3" with all parameters ignoring the first.
  docker network create openc3-cosmos-network
  docker run -it --rm --env-file %~dp0.env --network openc3-cosmos-network -v %cd%:/openc3/local -w /openc3/local !OPENC3_REGISTRY!/!OPENC3_NAMESPACE!/openc3-operator!OPENC3_IMAGE_SUFFIX!:!OPENC3_TAG! ruby /openc3/bin/openc3cli !params!
  GOTO :EOF
)
if "%1" == "cliroot" (
  FOR /F "tokens=*" %%i in ('findstr /V /B /L /C:# %~dp0.env') do SET %%i
  set params=%*
  call set params=%%params:*%1=%%
  docker network create openc3-cosmos-network
  docker run -it --rm --env-file %~dp0.env --user=root --network openc3-cosmos-network -v %cd%:/openc3/local -w /openc3/local !OPENC3_REGISTRY!/!OPENC3_NAMESPACE!/openc3-operator!OPENC3_IMAGE_SUFFIX!:!OPENC3_TAG! ruby /openc3/bin/openc3cli !params!
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
if "%1" == "util" (
  FOR /F "tokens=*" %%i in ('findstr /V /B /L /C:# %~dp0.env') do SET %%i
  GOTO util
)

GOTO usage

:startup
  CALL openc3 build || exit /b
  docker compose -f compose.yaml up -d
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

:dev
  docker compose -f compose.yaml -f compose-dev.yaml up -d
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

:util
  REM Send the remaining arguments to openc3_util
  set args=%*
  call set args=%%args:*%1=%%
  CALL scripts\windows\openc3_util %args% || exit /b
  @echo off
GOTO :EOF

:usage
  @echo Usage: %0 [cli, cliroot, start, stop, cleanup, build, run, dev, test, util] 1>&2
  @echo *  cli: run a cli command as the default user ('cli help' for more info) 1>&2
  @echo *  cliroot: run a cli command as the root user ('cli help' for more info) 1>&2
  @echo *  start: build and run 1>&2
  @echo *  stop: stop the containers (compose stop) 1>&2
  @echo *  cleanup [local] [force]: REMOVE volumes / data (compose down -v) 1>&2
  @echo *  build: build the containers (compose build) 1>&2
  @echo *  run: run the containers (compose up) 1>&2
  @echo *  dev: run using compose-dev 1>&2
  @echo *  test: test openc3 1>&2
  @echo *  util: various helper commands 1>&2

@echo on
