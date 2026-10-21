@echo off
setlocal enabledelayedexpansion

REM Migration script to transfer data from MINIO (COSMOS 6) to versitygw (COSMOS 7)
REM
REM This script supports multiple migration scenarios:
REM 1. Pre-migration while COSMOS 6 is running (uses live MINIO, starts temp versitygw)
REM 2. Post-migration after COSMOS 6 stopped (starts temp MINIO, starts temp versitygw)
REM 3. Migration with COSMOS 7 running (starts temp MINIO, uses live versitygw)
REM
REM The script is idempotent - mc mirror only copies new/changed files, so it's safe
REM to run multiple times. This allows users to pre-migrate data while COSMOS 6 is
REM running, then do a final sync after shutdown to minimize downtime.
REM
REM Prerequisites:
REM - Docker must be running
REM - The old MINIO volume (OLD_VOLUME) must exist
REM - For pre-migration: openc3-buckets image must be available (pulled or built)
REM
REM Migration workflow for upgrading from COSMOS 6 to COSMOS 7:
REM 1. (Optional) While COSMOS 6 is running, run: openc3_migrate_s3.bat start && openc3_migrate_s3.bat migrate
REM 2. Stop COSMOS 6: openc3.bat stop
REM 3. Upgrade to COSMOS 7
REM 4. Run final migration: openc3_migrate_s3.bat migrate
REM 5. Stop the migration containers: openc3_migrate_s3.bat stop
REM 6. Start COSMOS 7: openc3.bat run

REM Configuration - can be overridden by environment variables
REM MINIO credentials (source - COSMOS 6 defaults)
if "%MINIO_ROOT_USER%"=="" (set "MINIO_USER=openc3minio") else (set "MINIO_USER=%MINIO_ROOT_USER%")
if "%MINIO_ROOT_PASSWORD%"=="" (set "MINIO_PASS=openc3miniopassword") else (set "MINIO_PASS=%MINIO_ROOT_PASSWORD%")
REM Versitygw credentials (destination - uses COSMOS 7 bucket credentials)
if "%OPENC3_BUCKET_USERNAME%"=="" (set "VERSITY_USER=openc3bucket") else (set "VERSITY_USER=%OPENC3_BUCKET_USERNAME%")
if "%OPENC3_BUCKET_PASSWORD%"=="" (set "VERSITY_PASS=openc3bucketpassword") else (set "VERSITY_PASS=%OPENC3_BUCKET_PASSWORD%")
REM User IDs - must match openc3.bat behavior
REM On Windows, typically runs as 1001:1001 (no rootless detection needed)
if "%OPENC3_USER_ID%"=="" set "OPENC3_USER_ID=1001"
if "%OPENC3_GROUP_ID%"=="" set "OPENC3_GROUP_ID=1001"
REM Volume names - set both OLD_VOLUME and NEW_VOLUME to full volume names, or
REM neither to detect them (including any docker compose project prefix)
set "OLD_VOLUME_BASE=openc3-bucket-v"
set "NEW_VOLUME_BASE=openc3-object-v"

REM Container/image names
set "MINIO_MIGRATION_CONTAINER=openc3-minio-migration"
set "VERSITY_MIGRATION_CONTAINER=openc3-versity-migration"
set "MINIO_IMAGE=ghcr.io/openc3/openc3-minio:latest"
REM COSMOS 6 init image containing the patched mc client used for the migration.
REM Defaults to the Core init image. Set MC_IMAGE to use a different init image,
REM e.g. one already available locally on an offline / air-gapped system.
if "%MC_IMAGE%"=="" set "MC_IMAGE=ghcr.io/openc3/openc3-cosmos-init:6.10.4"
if "%OPENC3_REGISTRY%"=="" (set "OPENC3_REGISTRY=docker.io")
if "%OPENC3_NAMESPACE%"=="" (set "OPENC3_NAMESPACE=openc3inc")
if "%OPENC3_TAG%"=="" (set "OPENC3_TAG=latest")
set "VERSITY_IMAGE=%OPENC3_REGISTRY%/%OPENC3_NAMESPACE%/openc3-buckets:%OPENC3_TAG%"

REM Network
set "MIGRATION_NETWORK=openc3-migration-net"

REM State variables
set "MINIO_SOURCE="
set "VERSITY_DEST="
set "DOCKER_NETWORK="

REM Parse command
set "COMMAND=%~1"
if "%1"=="" goto :usage
if "%1"=="help" goto :usage
if "%1"=="--help" goto :usage
if "%1"=="-h" goto :usage
if "%1"=="start" goto :cmd_start
if "%1"=="migrate" goto :cmd_migrate
if "%1"=="status" goto :cmd_status
if "%1"=="stop" goto :cmd_stop
goto :usage

:cmd_start
call :check_volume_env
if errorlevel 1 exit /b 1
call :ensure_mc_image
if errorlevel 1 exit /b 1
call :detect_environment
if errorlevel 1 exit /b 1
if "%MINIO_SOURCE%"=="" call :start_temp_minio
if errorlevel 1 exit /b 1
if "%VERSITY_DEST%"=="" call :start_temp_versity
if errorlevel 1 exit /b 1
echo.
echo [INFO] Migration containers ready
echo   MINIO source: %MINIO_SOURCE%
echo   versitygw destination: %VERSITY_DEST%
echo.
echo Run '%~nx0 migrate' to start migration
exit /b 0

:cmd_migrate
call :check_volume_env
if errorlevel 1 exit /b 1
call :ensure_mc_image
if errorlevel 1 exit /b 1
call :detect_environment
if errorlevel 1 exit /b 1
if "%MINIO_SOURCE%"=="" call :start_temp_minio
if errorlevel 1 exit /b 1
if "%VERSITY_DEST%"=="" call :start_temp_versity
if errorlevel 1 exit /b 1
call :migrate_data
exit /b %errorlevel%

:cmd_status
call :check_volume_env
if errorlevel 1 exit /b 1
call :ensure_mc_image
if errorlevel 1 exit /b 1
call :detect_environment
if errorlevel 1 exit /b 1
call :show_status
exit /b %errorlevel%

:cmd_stop
call :check_volume_env
if errorlevel 1 exit /b 1
call :stop_containers
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [start^|migrate^|status^|stop^|help]
echo.
echo Migrate data from MINIO (COSMOS 6) to versitygw (COSMOS 7).
echo.
echo This script is idempotent and can be run multiple times safely. It supports:
echo - Pre-migration while COSMOS 6 is running (to minimize downtime)
echo - Post-migration after COSMOS 6 is stopped
echo - Incremental sync (only copies new/changed files)
echo.
echo Commands:
echo   start     Start temporary containers needed for migration
echo   migrate   Mirror data from MINIO to versitygw (idempotent)
echo   status    Check migration status and compare bucket contents
echo   stop      Stop and remove temporary migration containers
echo   help      Show this help message
echo.
echo Migration workflow:
echo   1. (Optional) Pre-migrate while COSMOS 6 is running:
echo      %~nx0 start
echo      %~nx0 migrate
echo      (repeat migrate as needed to sync new data)
echo.
echo   2. Stop COSMOS 6 and upgrade to COSMOS 7
echo.
echo   3. Final migration:
echo      %~nx0 migrate
echo.
echo   4. Stop the migration containers and start COSMOS 7:
echo      %~nx0 stop
echo      openc3.bat run
echo.
echo Configuration (via environment variables):
echo   OLD_VOLUME    Full name of the old MINIO volume
echo   NEW_VOLUME    Full name of the new versitygw volume
echo                 Set both or neither. If neither is set, they are detected as
echo                 [^<prefix^>_]openc3-bucket-v and [^<prefix^>_]openc3-object-v,
echo                 where ^<prefix^> is the docker compose project name, if any.
echo   OPENC3_BUCKET_USERNAME  S3 credentials (default: openc3minio)
echo   OPENC3_BUCKET_PASSWORD  S3 credentials (default: openc3miniopassword)
echo   MC_IMAGE      COSMOS 6 init image used to run mc
echo                 (default: ghcr.io/openc3/openc3-cosmos-init:6.10.4)
echo                 If offline, set this to an init image available locally.
echo.
exit /b 0

:ensure_mc_image
REM Ensure the image used to run mc is available locally
echo [INFO] Using mc image: %MC_IMAGE%
docker image inspect "%MC_IMAGE%" >nul 2>&1
if not errorlevel 1 exit /b 0
echo [INFO] Pulling mc image: %MC_IMAGE%
docker pull "%MC_IMAGE%"
if not errorlevel 1 exit /b 0
echo [ERROR] Failed to pull mc image: %MC_IMAGE%
echo If you are offline, set MC_IMAGE to a COSMOS 6 init image available locally, e.g.:
echo   set MC_IMAGE=^<registry^>/^<namespace^>/openc3-cosmos-init:^<tag^>
echo   %~nx0 %COMMAND%
exit /b 1

:detect_environment
echo [==>] Detecting environment...

call :resolve_volumes
if errorlevel 2 exit /b 1
if errorlevel 1 (
    if "%OLD_VOLUME%"=="" (
        echo [ERROR] Old MINIO volume '%OLD_VOLUME_BASE%' not found
    ) else (
        echo [ERROR] Old MINIO volume '%OLD_VOLUME%' not found
    )
    echo This volume should exist from your COSMOS 6 installation.
    echo If you haven't run COSMOS 6 before, there's nothing to migrate.
    exit /b 1
)
echo [INFO] Using old MINIO volume: %OLD_VOLUME%

REM Check for new volume
set "NEW_VOL_FOUND="
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /x "%NEW_VOLUME%"') do set "NEW_VOL_FOUND=1"
if "%NEW_VOL_FOUND%"=="" (
    echo [INFO] New volume '%NEW_VOLUME%' will be created
) else (
    echo [INFO] Found new versitygw volume: %NEW_VOLUME%
)

REM Detect MINIO source
set "MINIO_SOURCE="
for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /i "minio" ^| findstr /v "migration"') do (
    if "!MINIO_SOURCE!"=="" set "MINIO_SOURCE=%%i"
)
if not "%MINIO_SOURCE%"=="" (
    echo [INFO] Found live MINIO (COSMOS 6): %MINIO_SOURCE%
    for /f "tokens=*" %%n in ('docker inspect --format "{{range $net, $config := .NetworkSettings.Networks}}{{$net}} {{end}}" "%MINIO_SOURCE%" 2^>nul') do (
        for %%x in (%%n) do if "!DOCKER_NETWORK!"=="" set "DOCKER_NETWORK=%%x"
    )
) else (
    REM Check for temp container
    for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /x "%MINIO_MIGRATION_CONTAINER%"') do set "MINIO_SOURCE=%%i"
    if not "!MINIO_SOURCE!"=="" (
        echo [INFO] Using temp MINIO container: !MINIO_SOURCE!
    ) else (
        echo [INFO] No MINIO running - will start temp container
    )
)

REM Detect versitygw destination
set "VERSITY_DEST="
for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /i "bucket" ^| findstr /v "migration"') do (
    if "!VERSITY_DEST!"=="" set "VERSITY_DEST=%%i"
)
if not "%VERSITY_DEST%"=="" (
    echo [INFO] Found live versitygw (COSMOS 7): %VERSITY_DEST%
    if "%DOCKER_NETWORK%"=="" (
        for /f "tokens=*" %%n in ('docker inspect --format "{{range $net, $config := .NetworkSettings.Networks}}{{$net}} {{end}}" "%VERSITY_DEST%" 2^>nul') do (
            for %%x in (%%n) do if "!DOCKER_NETWORK!"=="" set "DOCKER_NETWORK=%%x"
        )
    )
) else (
    REM Check for temp container
    for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /x "%VERSITY_MIGRATION_CONTAINER%"') do set "VERSITY_DEST=%%i"
    if not "!VERSITY_DEST!"=="" (
        echo [INFO] Using temp versitygw container: !VERSITY_DEST!
    ) else (
        echo [INFO] No versitygw running - will start temp container
    )
)

REM Existing containers keep the volume they were created with, so make sure
REM the ones we will use (live, or temp ones that get restarted) match
set "MINIO_CHECK=%MINIO_SOURCE%"
if "%MINIO_CHECK%"=="" for /f "tokens=*" %%i in ('docker ps -a --format "{{.Names}}" 2^>nul ^| findstr /l /x /c:"%MINIO_MIGRATION_CONTAINER%"') do set "MINIO_CHECK=%%i"
set "VERSITY_CHECK=%VERSITY_DEST%"
if "%VERSITY_CHECK%"=="" for /f "tokens=*" %%i in ('docker ps -a --format "{{.Names}}" 2^>nul ^| findstr /l /x /c:"%VERSITY_MIGRATION_CONTAINER%"') do set "VERSITY_CHECK=%%i"
call :check_container_volume "%MINIO_CHECK%" "%OLD_VOLUME%"
if errorlevel 1 exit /b 1
call :check_container_volume "%VERSITY_CHECK%" "%NEW_VOLUME%"
if errorlevel 1 exit /b 1

REM Ensure network exists
if "%DOCKER_NETWORK%"=="" (
    set "NET_EXISTS="
    for /f "tokens=*" %%i in ('docker network ls --format "{{.Name}}" 2^>nul ^| findstr /x "%MIGRATION_NETWORK%"') do set "NET_EXISTS=1"
    if "!NET_EXISTS!"=="" (
        echo [INFO] Creating migration network: %MIGRATION_NETWORK%
        docker network create "%MIGRATION_NETWORK%" >nul
    )
    set "DOCKER_NETWORK=%MIGRATION_NETWORK%"
)
echo [INFO] Using Docker network: %DOCKER_NETWORK%
exit /b 0

:check_volume_env
REM Require OLD_VOLUME and NEW_VOLUME to be set together, so a prefix is never
REM applied to a user-supplied name
if not "%OLD_VOLUME%"=="" if not "%NEW_VOLUME%"=="" exit /b 0
if "%OLD_VOLUME%"=="" if "%NEW_VOLUME%"=="" exit /b 0
echo [ERROR] OLD_VOLUME and NEW_VOLUME must be set together, as full volume names, e.g.:
echo   set OLD_VOLUME=cosmos_%OLD_VOLUME_BASE%
echo   set NEW_VOLUME=cosmos_%NEW_VOLUME_BASE%
echo   %~nx0 %COMMAND%
echo Leave both unset to detect them automatically.
exit /b 1

:resolve_volumes
REM Set OLD_VOLUME and NEW_VOLUME. If the user set them, use them as given.
REM Otherwise find OLD_VOLUME_BASE with or without a docker compose project
REM prefix, asking the user which to use if more than one matches, and give
REM NEW_VOLUME_BASE the same prefix.
REM Returns 0 if resolved, 1 if no volume matches, 2 if no volume was selected.
if "%OLD_VOLUME%"=="" goto :resolve_detect
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /l /x /c:"%OLD_VOLUME%"') do exit /b 0
exit /b 1

:resolve_detect
set "CANDIDATE_COUNT=0"
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /l /x /c:"%OLD_VOLUME_BASE%"') do (
    set /a CANDIDATE_COUNT+=1
    set "CANDIDATE_!CANDIDATE_COUNT!=%%i"
)
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /l /e /c:"_%OLD_VOLUME_BASE%"') do (
    set /a CANDIDATE_COUNT+=1
    set "CANDIDATE_!CANDIDATE_COUNT!=%%i"
)
if %CANDIDATE_COUNT%==0 exit /b 1
set "CHOICE=1"
if %CANDIDATE_COUNT%==1 goto :resolve_selected

echo [WARN] Multiple volumes match '%OLD_VOLUME_BASE%':
for /l %%n in (1,1,%CANDIDATE_COUNT%) do echo   %%n^) !CANDIDATE_%%n!
:resolve_prompt
set "CHOICE="
set /p "CHOICE=Select the volume to use [1-%CANDIDATE_COUNT%]: "
REM No input (including no console to read from) means no selection
if not defined CHOICE goto :resolve_none
set "NOT_NUMBER="
for /f "delims=0123456789" %%x in ("!CHOICE!") do set "NOT_NUMBER=1"
if "!CHOICE:~0,1!"=="0" set "NOT_NUMBER=1"
if defined NOT_NUMBER goto :resolve_invalid
if !CHOICE! gtr %CANDIDATE_COUNT% goto :resolve_invalid
goto :resolve_selected
:resolve_invalid
echo Invalid selection: !CHOICE!
goto :resolve_prompt

:resolve_none
echo.
echo [ERROR] No volume selected
echo Set OLD_VOLUME and NEW_VOLUME for the volume you want to use, then run %~nx0 %COMMAND%:
for /l %%n in (1,1,%CANDIDATE_COUNT%) do (
    set "HINT_OLD=!CANDIDATE_%%n!"
    set "HINT_PREFIX=!HINT_OLD:%OLD_VOLUME_BASE%=!"
    echo   set OLD_VOLUME=!HINT_OLD!
    echo   set NEW_VOLUME=!HINT_PREFIX!%NEW_VOLUME_BASE%
    echo.
)
exit /b 2

:resolve_selected
set "OLD_VOLUME=!CANDIDATE_%CHOICE%!"
set "VOLUME_PREFIX=!OLD_VOLUME:%OLD_VOLUME_BASE%=!"
set "NEW_VOLUME=!VOLUME_PREFIX!%NEW_VOLUME_BASE%"
exit /b 0

:check_container_volume
REM Fail if a container exists but mounts a different volume at /data
if "%~1"=="" exit /b 0
set "ACTUAL_VOLUME="
for /f "tokens=*" %%v in ('docker inspect --format "{{range .Mounts}}{{if eq .Destination `/data`}}{{.Name}}{{end}}{{end}}" "%~1" 2^>nul') do set "ACTUAL_VOLUME=%%v"
if "%ACTUAL_VOLUME%"=="%~2" exit /b 0
if "%ACTUAL_VOLUME%"=="" set "ACTUAL_VOLUME=none"
echo [ERROR] Container '%~1' uses volume '%ACTUAL_VOLUME%', not '%~2'
if "%~1"=="%MINIO_MIGRATION_CONTAINER%" goto :check_container_temp
if "%~1"=="%VERSITY_MIGRATION_CONTAINER%" goto :check_container_temp
echo Set OLD_VOLUME and NEW_VOLUME to the volumes the running COSMOS uses, or stop it.
exit /b 1
:check_container_temp
echo Run '%~nx0 stop' to remove the temporary containers, then try again.
exit /b 1

:start_temp_minio
REM Check if already running
for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /x "%MINIO_MIGRATION_CONTAINER%"') do (
    echo [INFO] Temp MINIO already running
    set "MINIO_SOURCE=%MINIO_MIGRATION_CONTAINER%"
    exit /b 0
)

REM Check if exists but stopped
set "CONTAINER_EXISTS="
for /f "tokens=*" %%i in ('docker ps -a --format "{{.Names}}" 2^>nul ^| findstr /x "%MINIO_MIGRATION_CONTAINER%"') do set "CONTAINER_EXISTS=1"
if "%CONTAINER_EXISTS%"=="1" (
    echo [INFO] Starting existing temp MINIO container...
    docker start "%MINIO_MIGRATION_CONTAINER%" >nul
    timeout /t 2 /nobreak >nul
    set "MINIO_SOURCE=%MINIO_MIGRATION_CONTAINER%"
    exit /b 0
)

REM Note: We run as root because the original MINIO volume may have been created
REM by a container running as a different user. MINIO needs write access to
REM .minio.sys for internal metadata even when we're only reading data.
echo [==>] Starting temporary MINIO container...
docker run -d ^
    --name "%MINIO_MIGRATION_CONTAINER%" ^
    --network "%DOCKER_NETWORK%" ^
    --user root ^
    -v "%OLD_VOLUME%:/data" ^
    -e "MINIO_ROOT_USER=%MINIO_USER%" ^
    -e "MINIO_ROOT_PASSWORD=%MINIO_PASS%" ^
    "%MINIO_IMAGE%" ^
    server --address ":9000" --console-address ":9001" /data >nul

echo [INFO] Waiting for MINIO to be ready...
set "RETRY_COUNT=0"
:wait_minio
if %RETRY_COUNT% geq 30 goto :minio_check_running
REM Use mc admin info to check if MINIO is responding
docker run --rm --network "%DOCKER_NETWORK%" --entrypoint "" -e "MC_HOST_minio=http://%MINIO_USER%:%MINIO_PASS%@%MINIO_MIGRATION_CONTAINER%:9000" "%MC_IMAGE%" mc admin info minio >nul 2>&1
if %errorlevel%==0 (
    echo [INFO] MINIO is ready
    set "MINIO_SOURCE=%MINIO_MIGRATION_CONTAINER%"
    exit /b 0
)
timeout /t 1 /nobreak >nul
set /a RETRY_COUNT+=1
goto :wait_minio

:minio_check_running
REM Check if container is at least running
for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /x "%MINIO_MIGRATION_CONTAINER%"') do (
    echo [WARN] MINIO health check timed out, but container is running. Proceeding anyway.
    set "MINIO_SOURCE=%MINIO_MIGRATION_CONTAINER%"
    exit /b 0
)

:minio_failed
echo [ERROR] MINIO failed to start
docker logs "%MINIO_MIGRATION_CONTAINER%"
exit /b 1

:start_temp_versity
REM Check if already running
for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /x "%VERSITY_MIGRATION_CONTAINER%"') do (
    echo [INFO] Temp versitygw already running
    set "VERSITY_DEST=%VERSITY_MIGRATION_CONTAINER%"
    exit /b 0
)

REM Check if exists but stopped
set "CONTAINER_EXISTS="
for /f "tokens=*" %%i in ('docker ps -a --format "{{.Names}}" 2^>nul ^| findstr /x "%VERSITY_MIGRATION_CONTAINER%"') do set "CONTAINER_EXISTS=1"
if "%CONTAINER_EXISTS%"=="1" (
    echo [INFO] Starting existing temp versitygw container...
    docker start "%VERSITY_MIGRATION_CONTAINER%" >nul
    timeout /t 2 /nobreak >nul
    set "VERSITY_DEST=%VERSITY_MIGRATION_CONTAINER%"
    exit /b 0
)

REM Pull image if needed
docker image inspect "%VERSITY_IMAGE%" >nul 2>&1
if errorlevel 1 (
    echo [INFO] Pulling versitygw image: %VERSITY_IMAGE%
    docker pull "%VERSITY_IMAGE%"
)

REM Run as same user as production (matches compose.yaml)
echo [==>] Starting temporary versitygw container...
docker run -d ^
    --name "%VERSITY_MIGRATION_CONTAINER%" ^
    --network "%DOCKER_NETWORK%" ^
    --user "%OPENC3_USER_ID%:%OPENC3_GROUP_ID%" ^
    -v "%NEW_VOLUME%:/data" ^
    -e "ROOT_ACCESS_KEY=%VERSITY_USER%" ^
    -e "ROOT_SECRET_KEY=%VERSITY_PASS%" ^
    "%VERSITY_IMAGE%" >nul

REM Wait for container to be running
echo [INFO] Waiting for versitygw to start...
timeout /t 2 /nobreak >nul
for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /x "%VERSITY_MIGRATION_CONTAINER%"') do (
    echo [INFO] versitygw is ready
    set "VERSITY_DEST=%VERSITY_MIGRATION_CONTAINER%"
    exit /b 0
)

echo [ERROR] versitygw failed to start
docker logs "%VERSITY_MIGRATION_CONTAINER%"
exit /b 1

:migrate_data
echo.
echo ==========================================
echo Starting data migration from MINIO to versitygw
echo ==========================================
echo   Source: %MINIO_SOURCE% (volume: %OLD_VOLUME%)
echo   Destination: %VERSITY_DEST% (volume: %NEW_VOLUME%)
echo.

REM Only migrate config and logs buckets
REM Tools are installed and updated by the init container
if "%OPENC3_CONFIG_BUCKET%"=="" set "OPENC3_CONFIG_BUCKET=config"
if "%OPENC3_LOGS_BUCKET%"=="" set "OPENC3_LOGS_BUCKET=logs"
for %%b in (%OPENC3_CONFIG_BUCKET% %OPENC3_LOGS_BUCKET%) do (
    echo.
    echo [==>] Processing bucket: %%b

    REM Create bucket if it doesn't exist
    docker run --rm --network "%DOCKER_NETWORK%" --entrypoint "" -e "MC_HOST_versity=http://%VERSITY_USER%:%VERSITY_PASS%@%VERSITY_DEST%:9000" "%MC_IMAGE%" mc ls "versity/%%b" >nul 2>&1
    if errorlevel 1 (
        echo [INFO] Creating bucket: %%b
        docker run --rm --network "%DOCKER_NETWORK%" --entrypoint "" -e "MC_HOST_versity=http://%VERSITY_USER%:%VERSITY_PASS%@%VERSITY_DEST%:9000" "%MC_IMAGE%" mc mb "versity/%%b" 2>nul
    )

    REM Mirror data
    echo [INFO] Mirroring data...
    docker run --rm --network "%DOCKER_NETWORK%" --entrypoint "" -e "MC_HOST_minio=http://%MINIO_USER%:%MINIO_PASS%@%MINIO_SOURCE%:9000" -e "MC_HOST_versity=http://%VERSITY_USER%:%VERSITY_PASS%@%VERSITY_DEST%:9000" "%MC_IMAGE%" mc mirror --preserve "minio/%%b" "versity/%%b"
    echo [INFO] Bucket %%b migrated
)

echo.
echo ==========================================
echo Migration complete!
echo ==========================================
echo.
exit /b 0

:show_status
echo.
echo ==========================================
echo Migration Status
echo ==========================================
echo.

echo Volumes:
echo   Old (MINIO): %OLD_VOLUME%
set "VOL_EXISTS="
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /x "%OLD_VOLUME%"') do set "VOL_EXISTS=1"
if "%VOL_EXISTS%"=="1" (echo     exists) else (echo     not found)

echo   New (versitygw): %NEW_VOLUME%
set "VOL_EXISTS="
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /x "%NEW_VOLUME%"') do set "VOL_EXISTS=1"
if "%VOL_EXISTS%"=="1" (echo     exists) else (echo     not found)

echo.
echo Containers:
echo   MINIO source: %MINIO_SOURCE%
if not "%MINIO_SOURCE%"=="" echo     running

echo   versitygw destination: %VERSITY_DEST%
if not "%VERSITY_DEST%"=="" echo     running

if not "%MINIO_SOURCE%"=="" if not "%VERSITY_DEST%"=="" (
    echo.
    echo Bucket sizes (source -^> destination):
    echo.
    if "%OPENC3_CONFIG_BUCKET%"=="" set "OPENC3_CONFIG_BUCKET=config"
    if "%OPENC3_LOGS_BUCKET%"=="" set "OPENC3_LOGS_BUCKET=logs"
    echo   MINIO (source):
    call :run_mc du minio/%OPENC3_CONFIG_BUCKET% 2>nul
    call :run_mc du minio/%OPENC3_LOGS_BUCKET% 2>nul
    echo.
    echo   versitygw (destination):
    REM versitygw uses POSIX storage, so check disk usage and file count directly
    docker exec "%VERSITY_DEST%" sh -c "for dir in %OPENC3_CONFIG_BUCKET% %OPENC3_LOGS_BUCKET%; do size=$(du -sm /data/$dir 2>/dev/null | cut -f1); count=$(find /data/$dir -type f 2>/dev/null | wc -l); printf '    %%sMiB\t%%s files\t%%s\n' \"$size\" \"$count\" \"$dir\"; done" 2>nul
    echo.
    echo [INFO] Tools are not migrated - they are installed and updated by the init container.
    echo [INFO] If file counts match, migration was successful!
)

echo.
exit /b 0

:stop_containers
REM Resolve volume names for display
call :resolve_volumes
set "RESOLVE_RC=%errorlevel%"

echo [==>] Stopping migration containers...

set "CONTAINER_EXISTS="
for /f "tokens=*" %%i in ('docker ps -a --format "{{.Names}}" 2^>nul ^| findstr /x "%MINIO_MIGRATION_CONTAINER%"') do set "CONTAINER_EXISTS=1"
if "%CONTAINER_EXISTS%"=="1" (
    docker stop "%MINIO_MIGRATION_CONTAINER%" 2>nul
    docker rm "%MINIO_MIGRATION_CONTAINER%" 2>nul
    echo [INFO] Removed temp MINIO container
)

set "CONTAINER_EXISTS="
for /f "tokens=*" %%i in ('docker ps -a --format "{{.Names}}" 2^>nul ^| findstr /x "%VERSITY_MIGRATION_CONTAINER%"') do set "CONTAINER_EXISTS=1"
if "%CONTAINER_EXISTS%"=="1" (
    docker stop "%VERSITY_MIGRATION_CONTAINER%" 2>nul
    docker rm "%VERSITY_MIGRATION_CONTAINER%" 2>nul
    echo [INFO] Removed temp versitygw container
)

set "NET_EXISTS="
for /f "tokens=*" %%i in ('docker network ls --format "{{.Name}}" 2^>nul ^| findstr /x "%MIGRATION_NETWORK%"') do set "NET_EXISTS=1"
if "%NET_EXISTS%"=="1" (
    docker network rm "%MIGRATION_NETWORK%" 2>nul
    echo [INFO] Removed migration network
)

echo.
echo [INFO] Migration containers stopped
echo.
REM Don't name the new volume when we couldn't tell which old volume was used
if not "%RESOLVE_RC%"=="0" exit /b 0
echo Your data has been migrated to volume '%NEW_VOLUME%'.
echo.
exit /b 0

:run_mc
docker run --rm --network "%DOCKER_NETWORK%" --entrypoint "" -e "MC_HOST_minio=http://%MINIO_USER%:%MINIO_PASS%@%MINIO_SOURCE%:9000" -e "MC_HOST_versity=http://%VERSITY_USER%:%VERSITY_PASS%@%VERSITY_DEST%:9000" "%MC_IMAGE%" mc %*
exit /b %errorlevel%
