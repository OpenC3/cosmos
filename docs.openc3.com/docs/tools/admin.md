---
title: Admin
description: Administer COSMOS, install plugins, change settings
sidebar_custom_props:
  myEmoji: 🛠️
---

## Introduction

Admin has it's own dedicated button at the top of the tools list. It is responsible for administering the COSMOS system including installing new plugins, viewing configuration, storing secrets and changing settings.

### Plugins

The Plugins tab is where you install new plugins into the COSMOS system. Plugins can dynamically add targets, microservices, interfaces, protocols, Telemetry Viewer widgets, and entire tools into the COSMOS runtime. The following screenshot shows the Plugins tab when only the COSMOS Demo is installed:

![Plugins](/img/admin/plugins.png)

The plugin gem name is listed along with all the targets it contains. You can Download, Edit, Upgrade, or Delete (uninstall) the plugin using the buttons to the right. If a plugin's target has been modified, the target name turns into a link which when clicked will download the changed files. New plugins are installed by clicking the top field.

### Targets

The Targets tab shows all the targets installed and what plugin they came from. Clicking the eyeball shows the raw JSON that makes up the target configuration.

![Targets](/img/admin/targets.png)

### Interfaces

The Interfaces tab shows all the interfaces installed. Clicking the eyeball shows the raw JSON that makes up the interface configuration.

![Interfaces](/img/admin/interfaces.png)

### Routers

The Routers tab shows all the routers installed. Clicking the eyeball shows the raw JSON that makes up the router configuration.

![Routers](/img/admin/routers.png)

### Microservices

The Microservices tab shows all the microservices installed, their update time, state, and count. Clicking the eyeball shows the raw JSON that makes up the microservice configuration.

![Microservices](/img/admin/microservices.png)

### Packages

The Packages tab shows all the Ruby gems and Python packages installed in the system. You can also install packages from this tab if you're in an offline (air gapped) environment where COSMOS can't pull dependencies from Rubygems or Pypi.

![Packages](/img/admin/packages.png)

### Tools

The Tools tab lists all the tools installed. You can reorder the tools in the Navigation bar by dragging and dropping the left side grab handle.

![Tools](/img/admin/tools.png)

You can also add links to existing tools in the navigation bar by using the Add button. Any [material design icons](https://pictogrammers.com/library/mdi/) can be used as the Tool icon.

![Add Tool](/img/admin/add_tool.png)

### Redis

The Redis tab allows you to interact directly with the underlying Redis database, making it easy to modify or delete data. THIS IS DANGEROUS, and should only be performed by COSMOS developers.

![Redis](/img/admin/redis.png)

### Secrets

The Secrets tab allows you to create secrets that can be used by Interfaces or Microservices using the [SECRET](../configuration/plugins#secret) keyword. Secrets require setting the Secret Name and then can be set to an individual value using the Secret Value, or to the contents of a file \(like a certificate file\) using the file selector. In the following example the USERNAME and PASSWORD were set to values while CA_FILE was set using an uploaded certificate file.

![Secrets](/img/admin/secrets.png)

### Settings

The Settings tab contains various settings used throughout COSMOS. These including clearing saved tool configuration, hiding the Astro Clock, changing the system time zone, adding a top and bottom banner, creating a subtitle in the navigation bar, and changing the URLs of the various package libraries.

![Settings1](/img/admin/settings1.png)
![Settings2](/img/admin/settings2.png)
