---
title: Admin
description: Administer COSMOS, install plugins, change settings
sidebar_custom_props:
  myEmoji: 🧑‍⚖️
---

## Introduction

Admin has it's own dedicated button at the top of the tools list. It is responsible for administering the COSMOS system including installing new plugins, viewing configuration, storing secrets and changing settings.

### Plugins

The Plugins tab is where you install new plugins into the COSMOS system. Plugins can dynamically add targets, microservices, interfaces, protocols, Telemetry Viewer widgets, and entire tools into the COSMOS runtime. The following screenshot shows the Plugins tab when only the COSMOS Demo is installed:

![Plugins](/img/admin/plugins.png)

The plugin gem name is listed along with all the targets it contains. You can Download, Edit, Upgrade, or Delete (uninstall) the plugin using the buttons to the right. If a plugin's target has been modified, the target name turns into a link which when clicked will download the changed files. New plugins are installed by clicking the top field.

Plugins that were installed before the UV per-plugin virtual environment feature was added show a **Migrate to UV** button. Clicking this button creates an isolated UV virtual environment for the plugin and reinstalls its Python dependencies, giving it the same dependency isolation as newly installed plugins.

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

The Python packages section is organized into the following subsections:

- **Cached** — Python wheels available in the UV download cache. This includes system packages (seeded from the COSMOS Docker image at first startup) plus any packages downloaded during plugin installs. This section shows what's available for installation without network access, which is useful for planning plugin installs in airgapped environments. You can upload additional `.whl` files here to make them available to future plugin installs.
- **Plugin venvs** — Lists each installed plugin's isolated virtual environment and the packages installed in it. Each plugin gets its own venv at `/gems/plugin_venvs/<plugin>/.venv`, so different plugins can use different versions of the same package without conflicts.
- **Shared** (legacy) — Packages from the pre-UV shared install path. This section only appears when packages are present from plugins that were installed before the UV per-plugin virtual environment feature was added. Use the **Migrate to UV** button on the Plugins tab to migrate these plugins to isolated virtual environments.

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

The Settings tab contains various settings used throughout COSMOS. These including clearing saved tool configuration, hiding the Astro Clock, changing the system time zone, adding a top and bottom banner, creating a subtitle in the navigation bar, changing the theme, and changing the URLs of the various package libraries.

![Settings1](/img/admin/settings1.png)
![Settings2](/img/admin/settings2.png)

#### Theme

COSMOS includes several built-in color themes that change the look and feel of the entire application. To change the theme, select one from the Theme dropdown and click Save. Refresh the page to see the changes.

![Themes](/img/admin/themes.png)

The available themes are:

| Theme | Description |
|-------|-------------|
| Astro (Default) | Standard Astro dark theme with blue accents |
| Dark Cobalt | Neutral grey with cobalt blue accent |
| Dark Indigo | Cool grey with indigo/purple accent |
| Dark Slate | Blue-grey with teal/cyan accent |
| Dark Emerald | Neutral grey with emerald green accent |

The selected theme is a system-wide setting that applies to all users. After saving, each user must refresh their browser to see the updated theme.

### Roles (Enterprise)

The Roles tab allows users to create custom roles for role-based access control (RBAC). Roles define permissions and access levels throughout the COSMOS system. For more details, visit [Roles and Permissions](../guides/roles-permissions.md).

![Roles](/img/admin/roles.png)

### Scopes (Enterprise)

The Scopes tab allows users to create scopes which define data boundaries between separate environments. This enables a single COSMOS deployment to manage multiple environments with isolated data (e.g., separate constellations). Scopes can be added using the top dialog, and scope configurations can be managed here. Users can toggle between their scopes from the top-right scopes dropdown. [Command Authority](../configuration/command.md#command-authority-enterprise) and [Critical Commanding](../configuration/command.md#critical-commanding-enterprise) can also be configured per scope from this tab.

![Scopes](/img/admin/scopes.png)