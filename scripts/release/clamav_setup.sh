#!/bin/sh

docker volume create clamav
docker run -it --rm -v clamav:/var/lib/clamav clamav/clamav freshclam
