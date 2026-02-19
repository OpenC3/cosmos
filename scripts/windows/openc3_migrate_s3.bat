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
REM 5. Cleanup: openc3_migrate_s3.bat cleanup
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
if "%OLD_VOLUME%"=="" set "OLD_VOLUME=openc3-bucket-v"
if "%NEW_VOLUME%"=="" set "NEW_VOLUME=openc3-object-v"

REM Container/image names
set "MINIO_MIGRATION_CONTAINER=openc3-minio-migration"
set "VERSITY_MIGRATION_CONTAINER=openc3-versity-migration"
set "MINIO_IMAGE=ghcr.io/openc3/openc3-minio:latest"
set "MC_IMAGE=ghcr.io/openc3/openc3-cosmos-init:6.10.4"
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
if "%1"=="" goto :usage
if "%1"=="help" goto :usage
if "%1"=="--help" goto :usage
if "%1"=="-h" goto :usage
if "%1"=="start" goto :cmd_start
if "%1"=="migrate" goto :cmd_migrate
if "%1"=="status" goto :cmd_status
if "%1"=="cleanup" goto :cmd_cleanup
goto :usage

:cmd_start
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
call :detect_environment
if errorlevel 1 exit /b 1
if "%MINIO_SOURCE%"=="" call :start_temp_minio
if errorlevel 1 exit /b 1
if "%VERSITY_DEST%"=="" call :start_temp_versity
if errorlevel 1 exit /b 1
call :migrate_data
exit /b %errorlevel%

:cmd_status
call :detect_environment
if errorlevel 1 exit /b 1
call :show_status
exit /b %errorlevel%

:cmd_cleanup
call :cleanup
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [start^|migrate^|status^|cleanup^|help]
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
echo   cleanup   Remove temporary migration containers
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
echo   4. Cleanup and start COSMOS 7:
echo      %~nx0 cleanup
echo      openc3.bat run
echo.
echo Configuration (via environment variables):
echo   OLD_VOLUME    Old MINIO volume name (default: openc3-bucket-v)
echo   NEW_VOLUME    New versitygw volume name (default: openc3-object-v)
echo   OPENC3_BUCKET_USERNAME  S3 credentials (default: openc3minio)
echo   OPENC3_BUCKET_PASSWORD  S3 credentials (default: openc3miniopassword)
echo.
exit /b 0

:detect_environment
echo [==>] Detecting environment...

REM Check for old volume
set "VOLUME_FOUND="
set "VOLUME_PREFIX="
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /x "%OLD_VOLUME%"') do set "VOLUME_FOUND=1"
if "%VOLUME_FOUND%"=="" (
    REM Check for prefixed volume (docker compose adds project name)
    for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /e /c:"_%OLD_VOLUME%"') do (
        set "PREFIXED_VOL=%%i"
        set "VOLUME_FOUND=1"
    )
    if "!VOLUME_FOUND!"=="1" (
        REM Extract prefix by removing the old volume name from the end
        set "VOLUME_PREFIX=!PREFIXED_VOL:%OLD_VOLUME%=!"
        set "OLD_VOLUME=!PREFIXED_VOL!"
        echo [INFO] Found old volume with prefix: !OLD_VOLUME!
    )
)
if "%VOLUME_FOUND%"=="" (
    echo [ERROR] Old MINIO volume '%OLD_VOLUME%' not found
    echo This volume should exist from your COSMOS 6 installation.
    echo If you haven't run COSMOS 6 before, there's nothing to migrate.
    exit /b 1
)
if "%VOLUME_PREFIX%"=="" echo [INFO] Found old MINIO volume: %OLD_VOLUME%

REM Apply the same prefix to new volume if one was detected
if not "%VOLUME_PREFIX%"=="" (
    set "NEW_VOLUME=%VOLUME_PREFIX%%NEW_VOLUME%"
    echo [INFO] Using matching prefix for new volume: !NEW_VOLUME!
)

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

:cleanup
REM Resolve volume names with prefix detection for display
set "VOLUME_FOUND="
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /x "%OLD_VOLUME%"') do set "VOLUME_FOUND=1"
if "%VOLUME_FOUND%"=="" (
    for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /e /c:"_%OLD_VOLUME%"') do (
        set "PREFIXED_VOL=%%i"
        set "VOLUME_FOUND=1"
    )
    if "!VOLUME_FOUND!"=="1" (
        set "VOLUME_PREFIX=!PREFIXED_VOL:%OLD_VOLUME%=!"
        set "OLD_VOLUME=!PREFIXED_VOL!"
        set "NEW_VOLUME=!VOLUME_PREFIX!%NEW_VOLUME%"
    )
)

echo [==>] Cleaning up migration containers...

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
echo [INFO] Cleanup complete
echo.
echo Your data has been migrated to volume '%NEW_VOLUME%'.
echo.
echo After verifying COSMOS 7 works correctly, you can remove the old volume:
echo   docker volume rm %OLD_VOLUME%
echo.
exit /b 0

:run_mc
docker run --rm --network "%DOCKER_NETWORK%" --entrypoint "" -e "MC_HOST_minio=http://%MINIO_USER%:%MINIO_PASS%@%MINIO_SOURCE%:9000" -e "MC_HOST_versity=http://%VERSITY_USER%:%VERSITY_PASS%@%VERSITY_DEST%:9000" "%MC_IMAGE%" mc %*
exit /b %errorlevel%
