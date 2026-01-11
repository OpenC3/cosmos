@echo off
setlocal enabledelayedexpansion

REM Migration script to transfer data from old MINIO volume to new S3 (versitygw)
REM
REM This script:
REM 1. Starts a temporary MINIO container using the old openc3-bucket-v volume
REM 2. Uses mc to mirror all data from MINIO to the running openc3-bucket (versitygw)
REM 3. Provides instructions for completing the migration
REM
REM Prerequisites:
REM - COSMOS 7 must be running with openc3-bucket (versitygw)
REM - Docker must be running
REM - The old openc3-bucket-v volume must exist
REM - openc3-cosmos-init image must be built (contains mc)
REM
REM Migration workflow:
REM 1. Stop COSMOS 6
REM 2. Upgrade to COSMOS 7 and start: openc3.bat run
REM 3. Run this migration script to copy data from old volume to new S3

REM Configuration
if "%OPENC3_BUCKET_USERNAME%"=="" (set "MINIO_USER=openc3minio") else (set "MINIO_USER=%OPENC3_BUCKET_USERNAME%")
if "%OPENC3_BUCKET_PASSWORD%"=="" (set "MINIO_PASS=openc3miniopassword") else (set "MINIO_PASS=%OPENC3_BUCKET_PASSWORD%")
set "MINIO_PORT=9002"
set "MINIO_URL=http://localhost:%MINIO_PORT%"
set "OLD_VOLUME=openc3-bucket-v"
set "NEW_VOLUME=openc3-block-v"
set "MC_IMAGE=openc3inc/openc3-cosmos-init:latest"

REM Initialize variables
set "S3_CONTAINER="
set "DOCKER_NETWORK="
set "S3_SERVICE="

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
call :check_mc_image
if errorlevel 1 exit /b 1
call :detect_docker_environment
if errorlevel 1 exit /b 1
call :check_s3_running
if errorlevel 1 exit /b 1
call :start_minio
exit /b %errorlevel%

:cmd_migrate
call :detect_docker_environment
if errorlevel 1 exit /b 1
call :migrate_data
exit /b %errorlevel%

:cmd_status
call :detect_docker_environment
if errorlevel 1 exit /b 1
call :show_status
exit /b %errorlevel%

:cmd_cleanup
call :cleanup
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [start^|migrate^|status^|cleanup^|help]
echo.
echo Migrate data from old MINIO volume (openc3-bucket-v) to new S3 (openc3-bucket-v).
echo.
echo Commands:
echo   start     Start temporary MINIO on port 9002 using old volume for migration
echo   migrate   Mirror data from MINIO to S3 (versitygw) using mc
echo   status    Check migration status and bucket contents
echo   cleanup   Remove temporary MINIO container (after successful migration)
echo   help      Show this help message
echo.
echo Migration workflow:
echo   1. Stop COSMOS 6
echo   2. Upgrade to COSMOS 7 and start: openc3.bat run
echo   3. Start temporary MINIO: %~nx0 start
echo   4. Migrate data: %~nx0 migrate
echo   5. Verify data: %~nx0 status
echo   6. Cleanup temp container: %~nx0 cleanup
echo   7. (Optional) Remove old volume: docker volume rm openc3-bucket-v
echo.
exit /b 0

:detect_docker_environment
REM Find the openc3-bucket container (versitygw)
set "S3_CONTAINER="
for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /i "s3" ^| findstr /v "migration"') do (
    if "!S3_CONTAINER!"=="" set "S3_CONTAINER=%%i"
)

if "%S3_CONTAINER%"=="" (
    echo Error: Could not find running openc3-bucket container
    echo Make sure COSMOS 7 is running: openc3.bat run
    exit /b 1
)
echo Found S3 container: %S3_CONTAINER%

REM Get the network that the S3 container is connected to
set "DOCKER_NETWORK="
for /f "tokens=*" %%i in ('docker inspect --format "{{range $net, $config := .NetworkSettings.Networks}}{{$net}} {{end}}" "%S3_CONTAINER%" 2^>nul') do (
    for %%n in (%%i) do (
        if "!DOCKER_NETWORK!"=="" set "DOCKER_NETWORK=%%n"
    )
)

if "%DOCKER_NETWORK%"=="" (
    echo Error: Could not determine network for S3 container
    exit /b 1
)
echo Found Docker network: %DOCKER_NETWORK%

REM Get the service name from container labels
set "S3_SERVICE="
for /f "tokens=*" %%i in ('docker inspect --format "{{index .Config.Labels \"com.docker.compose.service\"}}" "%S3_CONTAINER%" 2^>nul') do (
    set "S3_SERVICE=%%i"
)

REM Fallback to container name if service not found
if "%S3_SERVICE%"=="" set "S3_SERVICE=%S3_CONTAINER%"
if "%S3_SERVICE%"=="<no value>" set "S3_SERVICE=%S3_CONTAINER%"
echo S3 service name: %S3_SERVICE%

exit /b 0

:check_mc_image
set "IMAGE_FOUND="
for /f "tokens=*" %%i in ('docker image ls --format "{{.Repository}}:{{.Tag}}" 2^>nul ^| findstr "openc3inc/openc3-cosmos-init:latest"') do (
    set "IMAGE_FOUND=1"
)

if "%IMAGE_FOUND%"=="" (
    echo Error: openc3-cosmos-init image not found
    echo.
    echo Build the image first:
    echo   openc3.bat build
    exit /b 1
)
exit /b 0

:check_s3_running
echo Checking S3 (versitygw) connectivity...

REM Try S3_SERVICE first, then S3_CONTAINER
for %%h in (%S3_SERVICE% %S3_CONTAINER%) do (
    for /f "tokens=*" %%c in ('docker run --rm --network "%DOCKER_NETWORK%" "%MC_IMAGE%" curl -s -o /dev/null -w "%%{http_code}" --connect-timeout 2 "http://%%h:9000/" 2^>nul') do (
        if not "%%c"=="000" if not "%%c"=="" (
            echo S3 (versitygw) is reachable at %%h:9000 ^(HTTP %%c^)
            set "S3_SERVICE=%%h"
            exit /b 0
        )
    )
)

echo Error: S3 (versitygw) is not responding
echo Tried: %S3_SERVICE%:9000 and %S3_CONTAINER%:9000
echo Make sure COSMOS 7 is running: openc3.bat run
exit /b 1

:check_old_volume_exists
set "VOLUME_FOUND="
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /x "%OLD_VOLUME%"') do (
    set "VOLUME_FOUND=1"
)

if "%VOLUME_FOUND%"=="" (
    echo Error: Old MINIO volume '%OLD_VOLUME%' not found
    echo.
    echo This volume should exist from your COSMOS 6 installation.
    echo If you haven't run COSMOS 6 before, there's nothing to migrate.
    exit /b 1
)
echo Found old MINIO volume: %OLD_VOLUME%
exit /b 0

:start_minio
echo Starting temporary MINIO container for migration...

REM Check if old volume exists
call :check_old_volume_exists
if errorlevel 1 exit /b 1

REM Check if container already exists
set "CONTAINER_EXISTS="
for /f "tokens=*" %%i in ('docker ps -a --format "{{.Names}}" 2^>nul ^| findstr /x "openc3-minio-migration"') do (
    set "CONTAINER_EXISTS=1"
)

if "%CONTAINER_EXISTS%"=="1" (
    echo Migration container already exists. Checking status...
    set "CONTAINER_RUNNING="
    for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /x "openc3-minio-migration"') do (
        set "CONTAINER_RUNNING=1"
    )
    if "!CONTAINER_RUNNING!"=="1" (
        echo Migration container is already running
        exit /b 0
    ) else (
        echo Starting existing container...
        docker start openc3-minio-migration
        timeout /t 2 /nobreak >nul
        exit /b 0
    )
)

REM Start MINIO on temporary port using the old volume
echo Starting MINIO on port %MINIO_PORT% with old volume...
docker run -d ^
    --name openc3-minio-migration ^
    --network "%DOCKER_NETWORK%" ^
    -p "%MINIO_PORT%:9000" ^
    -v "%OLD_VOLUME%:/data" ^
    -e "MINIO_ROOT_USER=%MINIO_USER%" ^
    -e "MINIO_ROOT_PASSWORD=%MINIO_PASS%" ^
    ghcr.io/openc3/openc3-minio:latest ^
    server --address ":9000" --console-address ":9001" /data

REM Wait for MINIO to be ready
echo Waiting for MINIO to be ready...
set "RETRY_COUNT=0"
:wait_minio_loop
if %RETRY_COUNT% geq 30 goto :minio_failed

for /f "tokens=*" %%c in ('curl -s -o nul -w "%%{http_code}" "%MINIO_URL%/" 2^>nul') do (
    if not "%%c"=="000" if not "%%c"=="" (
        echo MINIO is ready at %MINIO_URL% ^(HTTP %%c^)
        exit /b 0
    )
)

timeout /t 1 /nobreak >nul
set /a RETRY_COUNT+=1
goto :wait_minio_loop

:minio_failed
echo Error: MINIO failed to start
docker logs openc3-minio-migration
exit /b 1

:migrate_data
echo.
echo ==========================================
echo Starting data migration from MINIO to S3
echo ==========================================
echo.

call :check_mc_image
if errorlevel 1 exit /b 1
call :check_s3_running
if errorlevel 1 exit /b 1

REM Check if MINIO migration container is running
set "CONTAINER_RUNNING="
for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /x "openc3-minio-migration"') do (
    set "CONTAINER_RUNNING=1"
)

if not "%CONTAINER_RUNNING%"=="1" (
    echo Error: Migration MINIO container is not running
    echo Start it first with: %~nx0 start
    exit /b 1
)

REM List buckets in MINIO
echo.
echo Buckets in MINIO (source):
call :run_mc ls openc3minio/
echo.

REM Get list of buckets
set "BUCKETS="
for /f "tokens=*" %%i in ('docker run --rm --network "%DOCKER_NETWORK%" -e "MC_HOST_openc3minio=http://%MINIO_USER%:%MINIO_PASS%@openc3-minio-migration:9000" -e "MC_HOST_openc3s3=http://%MINIO_USER%:%MINIO_PASS%@%S3_SERVICE%:9000" "%MC_IMAGE%" mc ls openc3minio/ --json 2^>nul') do (
    for /f "tokens=2 delims=:," %%k in ("%%i") do (
        set "KEY=%%~k"
        REM Extract bucket name from JSON key field
        if "!KEY:~0,5!"==""key"" (
            for /f "tokens=2 delims=:" %%v in ("%%i") do (
                set "BUCKET_RAW=%%~v"
                set "BUCKET_RAW=!BUCKET_RAW:"=!"
                set "BUCKET_RAW=!BUCKET_RAW:/=!"
                set "BUCKET_RAW=!BUCKET_RAW:,=!"
                if not "!BUCKET_RAW!"=="" if not "!BUCKET_RAW!"==" " (
                    set "BUCKETS=!BUCKETS! !BUCKET_RAW!"
                )
            )
        )
    )
)

REM Alternative: Get buckets by parsing ls output directly
set "BUCKETS="
for /f "tokens=*" %%i in ('docker run --rm --network "%DOCKER_NETWORK%" -e "MC_HOST_openc3minio=http://%MINIO_USER%:%MINIO_PASS%@openc3-minio-migration:9000" "%MC_IMAGE%" mc ls openc3minio/ 2^>nul') do (
    for /f "tokens=5" %%b in ("%%i") do (
        set "BUCKET=%%b"
        set "BUCKET=!BUCKET:/=!"
        if not "!BUCKET!"=="" set "BUCKETS=!BUCKETS! !BUCKET!"
    )
)

if "%BUCKETS%"=="" (
    echo No buckets found in MINIO
    exit /b 0
)

REM Create buckets and mirror data
for %%b in (%BUCKETS%) do (
    echo.
    echo Processing bucket: %%b

    REM Create bucket in S3 if it doesn't exist
    docker run --rm --network "%DOCKER_NETWORK%" -e "MC_HOST_openc3s3=http://%MINIO_USER%:%MINIO_PASS%@%S3_SERVICE%:9000" "%MC_IMAGE%" mc ls "openc3s3/%%b" >nul 2>&1
    if errorlevel 1 (
        echo   Creating bucket: %%b
        docker run --rm --network "%DOCKER_NETWORK%" -e "MC_HOST_openc3s3=http://%MINIO_USER%:%MINIO_PASS%@%S3_SERVICE%:9000" "%MC_IMAGE%" mc mb "openc3s3/%%b" 2>nul
    )

    REM Mirror data
    echo   Mirroring data...
    docker run --rm --network "%DOCKER_NETWORK%" -e "MC_HOST_openc3minio=http://%MINIO_USER%:%MINIO_PASS%@openc3-minio-migration:9000" -e "MC_HOST_openc3s3=http://%MINIO_USER%:%MINIO_PASS%@%S3_SERVICE%:9000" "%MC_IMAGE%" mc mirror --preserve --overwrite "openc3minio/%%b" "openc3s3/%%b"

    echo   Bucket %%b migrated
)

echo.
echo ==========================================
echo Migration complete!
echo ==========================================
echo.
echo Next steps:
echo   1. Verify your data: %~nx0 status
echo   2. Cleanup temp container: %~nx0 cleanup
echo   3. (Optional) Remove old volume: docker volume rm %OLD_VOLUME%
echo.
exit /b 0

:show_status
echo.
echo ==========================================
echo Migration Status
echo ==========================================
echo.

call :check_mc_image
if errorlevel 1 exit /b 1

REM Check S3 (versitygw)
echo S3/versitygw (destination - COSMOS 7):
set "S3_REACHABLE=false"
for %%h in (%S3_SERVICE% %S3_CONTAINER%) do (
    for /f "tokens=*" %%c in ('docker run --rm --network "%DOCKER_NETWORK%" "%MC_IMAGE%" curl -s -o /dev/null -w "%%{http_code}" --connect-timeout 2 "http://%%h:9000/" 2^>nul') do (
        if not "%%c"=="000" if not "%%c"=="" (
            echo   Running at %%h:9000
            set "S3_SERVICE=%%h"
            set "S3_REACHABLE=true"
            echo   Buckets:
            docker run --rm --network "%DOCKER_NETWORK%" -e "MC_HOST_openc3s3=http://%MINIO_USER%:%MINIO_PASS%@%%h:9000" "%MC_IMAGE%" mc ls openc3s3/ 2>nul
            goto :s3_check_done
        )
    )
)
:s3_check_done

if "%S3_REACHABLE%"=="false" (
    echo   Not running
    echo   Make sure COSMOS 7 is running: openc3.bat run
)

echo.

REM Check temporary MINIO
echo MINIO (source - temporary migration container):
set "CONTAINER_RUNNING="
for /f "tokens=*" %%i in ('docker ps --format "{{.Names}}" 2^>nul ^| findstr /x "openc3-minio-migration"') do (
    set "CONTAINER_RUNNING=1"
)

if "%CONTAINER_RUNNING%"=="1" (
    echo   Migration container running
    for /f "tokens=*" %%c in ('curl -s -o nul -w "%%{http_code}" "%MINIO_URL%/" 2^>nul') do (
        if not "%%c"=="000" if not "%%c"=="" (
            echo   Buckets:
            docker run --rm --network "%DOCKER_NETWORK%" -e "MC_HOST_openc3minio=http://%MINIO_USER%:%MINIO_PASS%@openc3-minio-migration:9000" "%MC_IMAGE%" mc ls openc3minio/ 2>nul
        )
    )
) else (
    echo   Migration container not running
    echo   Start it with: %~nx0 start
)

echo.

REM Check volumes
echo Docker volumes:
echo   %OLD_VOLUME% (old MINIO data):
set "OLD_VOL_EXISTS="
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /x "%OLD_VOLUME%"') do (
    set "OLD_VOL_EXISTS=1"
)
if "%OLD_VOL_EXISTS%"=="1" (
    echo     exists
) else (
    echo     not found
)

echo   %NEW_VOLUME% (new S3 data):
set "NEW_VOL_EXISTS="
for /f "tokens=*" %%i in ('docker volume ls --format "{{.Name}}" 2^>nul ^| findstr /x "%NEW_VOLUME%"') do (
    set "NEW_VOL_EXISTS=1"
)
if "%NEW_VOL_EXISTS%"=="1" (
    echo     exists
) else (
    echo     not found
)
echo.
exit /b 0

:cleanup
echo Cleaning up migration container...

set "CONTAINER_EXISTS="
for /f "tokens=*" %%i in ('docker ps -a --format "{{.Names}}" 2^>nul ^| findstr /x "openc3-minio-migration"') do (
    set "CONTAINER_EXISTS=1"
)

if "%CONTAINER_EXISTS%"=="1" (
    docker stop openc3-minio-migration 2>nul
    docker rm openc3-minio-migration 2>nul
    echo Migration container removed
) else (
    echo Migration container not found
)

echo.
echo Migration cleanup complete.
echo.
echo Your data has been migrated to the new S3 volume '%NEW_VOLUME%'.
echo COSMOS 7 is already using this volume.
echo.
echo After verifying everything works, you can optionally remove the old MINIO volume:
echo   docker volume rm %OLD_VOLUME%
echo.
exit /b 0

:run_mc
docker run --rm --network "%DOCKER_NETWORK%" -e "MC_HOST_openc3minio=http://%MINIO_USER%:%MINIO_PASS%@openc3-minio-migration:9000" -e "MC_HOST_openc3s3=http://%MINIO_USER%:%MINIO_PASS%@%S3_SERVICE%:9000" "%MC_IMAGE%" mc %*
exit /b %errorlevel%
