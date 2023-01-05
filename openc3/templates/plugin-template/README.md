# OpenC3 COSMOS Plugin

See the [OpenC3](https://openc3.com) documentation for all things OpenC3.

## Building the plugin

1. <Path to COSMOS installation>\openc3.bat cli rake build VERSION=X.Y.Z
   - VERSION is required
   - gem file will be built locally

## Upload plugin

1. Go to localhost:2900/tools/admin
1. Click the paperclip icon and choose your plugin.gem file
1. Fill out plugin parameters
1. Click Install
