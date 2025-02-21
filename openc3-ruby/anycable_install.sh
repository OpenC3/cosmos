#!/bin/sh

ARCH=`uname -m`
if [ "$ARCH" == "aarch64" ]; then
  chmod 755 /usr/bin/anycable-go-linux-arm64
  ln -s /usr/bin/anycable-go-linux-arm64 /usr/bin/anycable-go
else
  chmod 755 /usr/bin/anycable-go-linux-amd64
  ln -s /usr/bin/anycable-go-linux-amd64 /usr/bin/anycable-go
fi
chmod 755 /usr/bin/anycable-go