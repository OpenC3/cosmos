#!/bin/sh
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# Installs the anycable-go binary matching the build architecture into
# /usr/bin. Run from a Dockerfile with the openc3-anycable directory mounted at
# the path given as $1, so the unused architecture never lands in an image layer:
#   RUN --mount=type=bind,from=anycable,target=/mnt/anycable /mnt/anycable/anycable_install.sh /mnt/anycable

SRC=${1:-$(dirname "$0")}
ARCH=`uname -m`
if [ "$ARCH" = "aarch64" ]; then
  BIN=anycable-go-linux-arm64
else
  BIN=anycable-go-linux-amd64
fi
cp "$SRC/$BIN" /usr/bin/anycable-go
chmod 755 /usr/bin/anycable-go
