@echo off

if "%1" == "" (
  GOTO usage
)
if "%1" == "encode" (
  GOTO encode
)
if "%1" == "hash" (
  GOTO hash
)
if "%1" == "save" (
  GOTO save
)
if "%1" == "load" (
  GOTO load
)
if "%1" == "tag" (
  GOTO tag
)
if "%1" == "push" (
  GOTO push
)
if "%1" == "zip" (
  GOTO zip
)
if "%1" == "clean" (
  GOTO clean
)
if "%1" == "hostsetup" (
  GOTO hostsetup
)

GOTO usage

:encode
  powershell -c "[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("""%2"""))"
GOTO :EOF

:hash
  powershell -c "new-object System.Security.Cryptography.SHA256Managed | ForEach-Object {$_.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("""%2"""))} | ForEach-Object {$_.ToString("""x2""")} | Write-Host -NoNewline"
GOTO :EOF

:save
  if "%4" == "" (
    set repo=%~2
    set namespace=%~3
    set tag=%~4
    if not exist tmp md tmp

    echo on
    docker pull !repo!/!namespace!/openc3-enterprise-gem:!tag! || exit /b
    docker pull !repo!/!namespace!/openc3-enterprise-operator:!tag! || exit /b
    docker pull !repo!/!namespace!/openc3-enterprise-cmd-tlm-api:!tag! || exit /b
    docker pull !repo!/!namespace!/openc3-enterprise-script-runner-api:!tag! || exit /b
    docker pull !repo!/!namespace!/openc3-enterprise-traefik:!tag! || exit /b
    docker pull !repo!/!namespace!/openc3-enterprise-redis:!tag! || exit /b
    docker pull !repo!/!namespace!/openc3-enterprise-minio:!tag! || exit /b
    docker pull !repo!/!namespace!/openc3-enterprise-init:!tag! || exit /b
    docker pull !repo!/!namespace!/openc3-enterprise-keycloak:!tag! || exit /b
    docker pull !repo!/!namespace!/openc3-enterprise-postgresql:!tag! || exit /b

    docker save !repo!/!namespace!/openc3-enterprise-gem:!tag! -o tmp/openc3-enterprise-gem-!tag!.tar || exit /b
    docker save !repo!/!namespace!/openc3-enterprise-operator:!tag! -o tmp/openc3-enterprise-operator-!tag!.tar || exit /b
    docker save !repo!/!namespace!/openc3-enterprise-cmd-tlm-api:!tag! -o tmp/openc3-enterprise-cmd-tlm-api-!tag!.tar || exit /b
    docker save !repo!/!namespace!/openc3-enterprise-script-runner-api:!tag! -o tmp/openc3-enterprise-script-runner-api-!tag!.tar || exit /b
    docker save !repo!/!namespace!/openc3-enterprise-traefik:!tag! -o tmp/openc3-enterprise-traefik-!tag!.tar || exit /b
    docker save !repo!/!namespace!/openc3-enterprise-redis:!tag! -o tmp/openc3-enterprise-redis-!tag!.tar || exit /b
    docker save !repo!/!namespace!/openc3-enterprise-minio:!tag! -o tmp/openc3-enterprise-minio-!tag!.tar || exit /b
    docker save !repo!/!namespace!/openc3-enterprise-init:!tag! -o tmp/openc3-enterprise-init-!tag!.tar || exit /b
    docker save !repo!/!namespace!/openc3-enterprise-keycloak:!tag! -o tmp/openc3-enterprise-keycloak-!tag!.tar || exit /b
    docker save !repo!/!namespace!/openc3-enterprise-postgresql:!tag! -o tmp/openc3-enterprise-postgresql-!tag!.tar || exit /b
    echo off
  ) else (
    @echo "Usage: save <REPO> <NAMESPACE> <TAG>" 1>&2
    @echo "e.g. save docker.io openc3inc 5.1.0" 1>&2
  )
GOTO :EOF

:load
  if "%2" == "" (
    set tag=latest
  ) else (
    set tag=%~2
  )
  echo on
  docker load -i tmp/openc3-enterprise-gem-!tag!.tar || exit /b
  docker load -i tmp/openc3-enterprise-operator-!tag!.tar || exit /b
  docker load -i tmp/openc3-enterprise-cmd-tlm-api-!tag!.tar || exit /b
  docker load -i tmp/openc3-enterprise-script-runner-api-!tag!.tar || exit /b
  docker load -i tmp/openc3-enterprise-traefik-!tag!.tar || exit /b
  docker load -i tmp/openc3-enterprise-redis-!tag!.tar || exit /b
  docker load -i tmp/openc3-enterprise-minio-!tag!.tar || exit /b
  docker load -i tmp/openc3-enterprise-init-!tag!.tar || exit /b
  docker load -i tmp/openc3-enterprise-keycloak-!tag!.tar || exit /b
  docker load -i tmp/openc3-enterprise-postgresql-!tag!.tar || exit /b
  echo off
GOTO :EOF

:tag
  set argC=0
  for %%x in (%*) do Set /A argC+=1

  if !argC! < 4 (
    @echo "Usage: push <REPO1> <REPO2> <NAMESPACE1> <TAG1> <NAMESPACE2> <TAG2>" 1>&2
    @echo "e.g. push docker.io localhost:12345 openc3 latest" 1>&2
    @echo "Note: NAMESPACE2 and TAG2 default to NAMESPACE1 and TAG1 if not given" 1>&2
    GOTO :EOF
  )

  set repo1=%~2
  set repo2=%~3
  set namespace1=%~4
  set tag1=%~5
  if "%6" == "" (
    set namespace2=!namespace1!
  ) else (
    set namespace2=%~6
  )
  if "%7" == "" (
    set tag2=!tag1!
  ) else (
    set tag2=%~7
  )

  echo on
  docker tag !repo1!/!namespace1!/openc3-enterprise-gem:!tag1! !repo2!/!namespace2!/openc3-enterprise-gem:!tag2!
  docker tag !repo1!/!namespace1!/openc3-enterprise-operator:!tag1! !repo2!/!namespace2!/openc3-enterprise-operator:!tag2!
  docker tag !repo1!/!namespace1!/openc3-enterprise-cmd-tlm-api:!tag1! !repo2!/!namespace2!/openc3-enterprise-cmd-tlm-api:!tag2!
  docker tag !repo1!/!namespace1!/openc3-enterprise-script-runner-api:!tag1! !repo2!/!namespace2!/openc3-enterprise-script-runner-api:!tag2!
  docker tag !repo1!/!namespace1!/openc3-enterprise-traefik:!tag1! !repo2!/!namespace2!/openc3-enterprise-traefik:!tag2!
  docker tag !repo1!/!namespace1!/openc3-enterprise-redis:!tag1! !repo2!/!namespace2!/openc3-enterprise-redis:!tag2!
  docker tag !repo1!/!namespace1!/openc3-enterprise-minio:!tag1! !repo2!/!namespace2!/openc3-enterprise-minio:!tag2!
  docker tag !repo1!/!namespace1!/openc3-enterprise-init:!tag1! !repo2!/!namespace2!/openc3-enterprise-init:!tag2!
  docker tag !repo1!/!namespace1!/openc3-enterprise-keycloak:!tag1! !repo2!/!namespace2!/openc3-enterprise-keycloak:!tag2!
  docker tag !repo1!/!namespace1!/openc3-enterprise-postgresql:!tag1! !repo2!/!namespace2!/openc3-enterprise-postgresql:!tag2!
  echo off
GOTO :EOF

:push
  if "%4" == "" (
    set repo=%~2
    set namespace=%~3
    set tag=%~4
    if not exist tmp md tmp

    echo on
    docker push !repo!/!namespace!/openc3-enterprise-gem:!tag!
    docker push !repo!/!namespace!/openc3-enterprise-operator:!tag!
    docker push !repo!/!namespace!/openc3-enterprise-cmd-tlm-api:!tag!
    docker push !repo!/!namespace!/openc3-enterprise-script-runner-api:!tag!
    docker push !repo!/!namespace!/openc3-enterprise-traefik:!tag!
    docker push !repo!/!namespace!/openc3-enterprise-redis:!tag!
    docker push !repo!/!namespace!/openc3-enterprise-minio:!tag!
    docker push !repo!/!namespace!/openc3-enterprise-init:!tag!
    docker push !repo!/!namespace!/openc3-enterprise-keycloak:!tag!
    docker push !repo!/!namespace!/openc3-enterprise-postgresql:!tag!
    echo off
  ) else (
    @echo "Usage: push <REPO> <NAMESPACE> <TAG>" 1>&2
    @echo "e.g. push localhost:12345 openc3 latest" 1>&2
  )
GOTO :EOF

:zip
  zip -r openc3.zip *.* -x "*.git*" -x "*coverage*" -x "*tmp/cache*" -x "*node_modules*" -x "*yarn.lock"
GOTO :EOF

:clean
  for /d /r %%i in (*node_modules*) do (
    echo Removing "%%i"
    @rmdir /s /q "%%i"
  )
  for /d /r %%i in (*coverage*) do (
    echo Removing "%%i"
    @rmdir /s /q "%%i"
  )
  REM Prompt for removing yarn.lock files
  forfiles /S /M yarn.lock /C "cmd /c del /P @path"
  REM Prompt for removing Gemfile.lock files
  forfiles /S /M Gemfile.lock /C "cmd /c del /P @path"
GOTO :EOF

:hostsetup
  docker run --rm --privileged --pid=host justincormack/nsenter1 /bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled" || exit /b
  docker run --rm --privileged --pid=host justincormack/nsenter1 /bin/sh -c "echo never > /sys/kernel/mm/transparent_hugepage/defrag" || exit /b
  docker run --rm --privileged --pid=host justincormack/nsenter1 /bin/sh -c "sysctl -w vm.max_map_count=262144" || exit /b
GOTO :EOF

:usage
  @echo Usage: %1 [encode, hash, save, load, tag, push, zip, clean, hostsetup] 1>&2
  @echo *  encode: encode a string to base64 1>&2
  @echo *  hash: hash a string using SHA-256 1>&2
  @echo *  save: save openc3 to tar files 1>&2
  @echo *  load: load openc3 tar files 1>&2
  @echo *  tag: tag images 1>&2
  @echo *  push: push images 1>&2
  @echo *  zip: create openc3 zipfile 1>&2
  @echo *  clean: remove node_modules, coverage, etc 1>&2
  @echo *  hostsetup: configure host for redis 1>&2

@echo on
