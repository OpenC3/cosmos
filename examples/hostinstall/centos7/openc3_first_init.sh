#!/bin/sh
set -eux

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd $SCRIPT_DIR
source ./openc3_env.sh

# Configure Minio
mc alias set openc3minio "${OPENC3_BUCKET_URL}" ${OPENC3_BUCKET_USERNAME} ${OPENC3_BUCKET_PASSWORD} || exit 1

# Create new canned policy by name script using script-runner.json policy file.
mc admin policy add openc3minio script $SCRIPT_DIR/../../../openc3-cosmos-init/script-runner.json || exit 1

# Create a new user scriptrunner on MinIO use mc admin user.
mc admin user add openc3minio ${OPENC3_SR_BUCKET_USERNAME} ${OPENC3_SR_BUCKET_PASSWORD} || exit 1

# Once the user is successfully created you can now apply the getonly policy for this user.
mc admin policy set openc3minio script user=${OPENC3_SR_BUCKET_USERNAME} || exit 1

# Install Plugins
mkdir -p /tmp/openc3/tmp/tmp
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-tool-base-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-cmdtlmserver-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-limitsmonitor-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-cmdsender-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-scriptrunner-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-packetviewer-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-tlmviewer-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-tlmgrapher-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-dataextractor-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-dataviewer-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-handbooks-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-tablemanager-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-admin-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-calendar-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-tool-autonomic-*.gem || exit 1
sudo -E --preserve-env=RUBYLIB /openc3/bin/openc3cli load $SCRIPT_DIR/../../../openc3-cosmos-init/plugins/gems/openc3-cosmos-demo-*.gem || exit 1

# Sleep To Keep Process Alive - Ctrl-C when done
echo "Sleep until Ctrl-C to Keep Process Alive"
sleep 1000000000

cd ~/
