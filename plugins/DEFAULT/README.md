# Plugins Configuration Folder

Warning: This folder is read/write with the OpenC3 system and is meant to be kept configuration controlled

First level folders are scope names, and should be all caps.  For open source OpenC3, the only first level folder will be DEFAULT.

Inside of each scope folder, are folders that can be arbitrarily named with one folder for each instance of an installed plugin.

The one exception is an optional folder called "targets_modified" that contains any changes made to plugins by the online system.
This folder can also be used to make local edits to scripts and other configuration that will automatically be picked up by the online system.
This folder is only supported by the Docker versions of OpenC3 and will not function in the Kubernetes versions.

Folder Structure
* plugins
    * DEFAULT
        * PluginName1
            * plugin_name.gem
            * plugin_instance.json
        * PluginName2
            * plugin_name.gem
            * plugin_instance.json
        * PluginName3
        * targets_modified
            * targetname
                * procedures
                * screens
