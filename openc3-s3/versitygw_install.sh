#!/bin/sh

ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  TARBALL=$(ls /tmp/versitygw_*_Linux_arm64.tar.gz)
else
  TARBALL=$(ls /tmp/versitygw_*_Linux_x86_64.tar.gz)
fi

tar -xzf "${TARBALL}" -C /tmp
EXTRACTED_DIR=$(basename "${TARBALL}" .tar.gz)
mv "/tmp/${EXTRACTED_DIR}/versitygw" /usr/bin/versitygw
chmod 755 /usr/bin/versitygw
rm -rf /tmp/versitygw_*
