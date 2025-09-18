@echo off

if ("%1" == "") (
  GOTO usage
)
if "%1" == "rspec" (
  GOTO rspec
)
if "%1" == "playwright" (
  GOTO playwright
)

GOTO usage

:rspec
  CD openc3
  rspec
  CD ..
GOTO :EOF

:playwright
  REM Starting OpenC3
  docker compose -f compose.yaml up -d
  CD playwright
  CALL pnpm run fixwindows
  CALL pnpm test
  CALL pnpm coverage
  CD ..
GOTO :EOF

:usage
  @echo Usage: %1 [rspec, playwright] 1>&2
  @echo *  rspec: run tests against Ruby code 1>&2
  @echo *  playwright: run end-to-end tests 1>&2
@echo on
