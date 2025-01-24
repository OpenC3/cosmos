#!/bin/sh

ARCH=`uname -m`
if [ "$ARCH" == "aarch64" ]; then
  ln -s /usr/bin/anycable-go-linux-arm64 /usr/bin/anycable-go
else
  ln -s /usr/bin/anycable-go-linux-amd64 /usr/bin/anycable-go
fi
