@echo off
setlocal ENABLEDELAYEDEXPANSION

if "%1" == "" (
  GOTO usage
)
if "%1" == "cli" (
  FOR /F "tokens=*" %%i in (%~dp0.env) do SET %%i
  set params=%*
  call set params=%%params:*%1=%%
  REM Start (and remove when done --rm) the openc3-base container with the current working directory
  REM mapped as volume (-v) /openc3/local and container working directory (-w) also set to /openc3/local.
  REM This allows tools running in the container to have a consistent path to the current working directory.
  REM Run the command "ruby /openc3/bin/openc3" with all parameters ignoring the first.
  docker run --rm --env-file %~dp0.env -v %cd%:/openc3/local -w /openc3/local openc3inc/openc3-base:!OPENC3_TAG! ruby /openc3/bin/openc3cli !params!
  GOTO :EOF
)
if "%1" == "cliroot" (
  FOR /F "tokens=*" %%i in (%~dp0.env) do SET %%i
  set params=%*
  call set params=%%params:*%1=%%
  docker run --rm --env-file %~dp0.env --user=root -v %cd%:/openc3/local -w /openc3/local openc3inc/openc3-base:!OPENC3_TAG! ruby /openc3/bin/openc3cli !params!
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
  GOTO util
)

GOTO usage

:startup
  CALL openc3 build || exit /b
  docker-compose -f compose.yaml up -d
  @echo off
GOTO :EOF

:stop
  docker-compose stop openc3-operator
  docker-compose stop openc3-cosmos-script-runner-api
  docker-compose stop openc3-cosmos-cmd-tlm-api
  timeout /t 5 /nobreak
  docker-compose -f compose.yaml down -t 30
  @echo off
GOTO :EOF

:cleanup
  docker-compose -f compose.yaml down -t 30 -v
  @echo off
GOTO :EOF

:build
  CALL scripts\windows\openc3_setup || exit /b
  docker-compose -f compose.yaml -f compose-build.yaml build openc3-ruby || exit /b
  docker-compose -f compose.yaml -f compose-build.yaml build openc3-base || exit /b
  docker-compose -f compose.yaml -f compose-build.yaml build openc3-node || exit /b
  docker-compose -f compose.yaml -f compose-build.yaml build || exit /b
  @echo off
GOTO :EOF

:run
  docker-compose -f compose.yaml up -d
  @echo off
GOTO :EOF

:dev
  docker-compose -f compose.yaml -f compose-dev.yaml up -d
  @echo off
GOTO :EOF

:test
  REM Building OpenC3
  CALL scripts\windows\openc3_setup || exit /b
  docker-compose -f compose.yaml -f compose-build.yaml build
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
  @echo *  start: run the docker containers for openc3 1>&2
  @echo *  stop: stop the running docker containers for openc3 1>&2
  @echo *  cleanup: cleanup network and volumes for openc3 1>&2
  @echo *  build: build the containers for openc3 1>&2
  @echo *  run: run the prebuilt containers for openc3 1>&2
  @echo *  dev: run openc3 in dev mode 1>&2
  @echo *  test: test openc3 1>&2
  @echo *  util: various helper commands 1>&2

@echo on
