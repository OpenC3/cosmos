---
title: Roles and Permissions
description: Understanding COSMOS Enterprise roles and access control
sidebar_custom_props:
  myEmoji: 🔐
---

COSMOS Enterprise provides a comprehensive role-based access control (RBAC) system that allows you to manage user permissions across different scopes. This system integrates with Keycloak for authentication and authorization.

## Overview

Roles in COSMOS Enterprise control what actions users can perform within the system. Roles are assigned to users per scope, allowing fine-grained control over access to different missions or projects.

### Role Naming Convention

Roles are assigned using the format: `{SCOPE}__{ROLE_NAME}`

- `SCOPE`: The scope name (e.g., `DEFAULT`) or `ALLSCOPES` for global permissions
- `ROLE_NAME`: One of the built-in roles or a custom role name

Examples:
- `DEFAULT__operator` - Operator role in the DEFAULT scope
- `MISSION1__viewer` - Viewer role in the MISSION1 scope
- `ALLSCOPES__admin` - Admin role across all scopes

## Built-in Roles

Individual built-in roles in COSMOS Enterprise are scoped to a minimal set of permissions. Individual users can have multiple roles (e.g., Admin and Operator) if users need administrative access and commanding access. COSMOS Enterprise includes five built-in roles with predefined permission sets:

### Admin

The **Admin** role provides administrative access within a scope. Admins can also manage the files within the MinIO bucket.

**Permissions:**
- `system` - View system information
- `system_set` - Modify system settings
- `tlm` - View telemetry data
- `cmd_info` - View command information
- `script_view` - View scripts
- `admin` - Administrative functions (manage plugins, targets, interfaces, etc.)

**Special Cases:**
- When assigned to `ALLSCOPES`, gains `superadmin` permission for system-wide administration
- Can release command authority taken by other users in their scope

**Use Case:** Users responsible for system configuration and management.

### Operator

The **Operator** role has full access except for administrative functions and approval rights.

**Permissions:**
- `system` - View system information
- `system_set` - Modify system settings
- `tlm` - View telemetry data
- `tlm_set` - Modify telemetry settings
- `cmd_info` - View command information
- `cmd_raw` - Send raw commands
- `cmd` - Send commands
- `script_view` - View scripts
- `script_edit` - Create and edit scripts
- `script_run` - Run scripts

**Use Case:** Power users who need full operational control but not administrative access.

### Viewer

The **Viewer** role provides read-only access to the system.

**Permissions:**
- `system` - View system information
- `tlm` - View telemetry data
- `cmd_info` - View command information
- `script_view` - View scripts

**Use Case:** Users who need to monitor telemetry and system status without making changes.

### Approver

The **Approver** role is specifically for command approval workflows.

**Permissions:**
- `approve_hazardous` - Approve hazardous commands
- `approve_restricted` - Approve restricted commands
- `approve_normal` - Approve normal commands

**Use Case:** Users responsible for reviewing and approving commands before execution.

### Runner

The **Runner** role allows users to execute commands and scripts but cannot create or edit them. Runner does not come with approval rights.

**Permissions:**
- `system` - View system information
- `system_set` - Modify system settings
- `tlm` - View telemetry data
- `tlm_set` - Modify telemetry settings
- `cmd_info` - View command information
- `cmd_raw` - Send raw commands
- `cmd` - Send commands
- `script_view` - View scripts
- `script_run` - Run scripts

**Use Case:** Operators who execute procedures and send commands but don't modify configurations or scripts.

## Permission Definitions

### System Permissions

- **system** - View system information and status
- **system_set** - Modify system settings and configurations

### Telemetry Permissions

- **tlm** - View telemetry data
- **tlm_set** - Modify telemetry settings (limits, conversions, etc.)

### Command Permissions

- **cmd_info** - View command definitions and parameters
- **cmd_raw** - Send raw binary commands
- **cmd** - Send commands to targets

### Script Permissions

- **script_view** - View script contents
- **script_edit** - Create, edit, and delete scripts
- **script_run** - Execute scripts

### Administrative Permissions

- **admin** - Manage scope-level resources (targets, plugins, interfaces, routers, etc.)
- **superadmin** - System-wide administration across all scopes (requires `ALLSCOPES__admin`)

### Approval Permissions

- **approve_hazardous** - Approve hazardous commands
- **approve_restricted** - Approve restricted commands
- **approve_normal** - Approve normal commands

## Command Authority

When command authority is enabled for a scope, an additional layer of authorization is applied to command-related permissions:

- Users must "take" command authority for a specific target before sending commands
- Only the user who holds command authority can send commands to that target
- Admin users (with `ALLSCOPES__admin` or `{SCOPE}__admin`) can release authority taken by other users
- Command authority applies to these permissions when executed manually:
  - `tlm_set`
  - `cmd_raw`
  - `cmd`
  - `script_run`

## Custom Roles

In addition to the built-in roles, you can create custom roles with specific permission combinations.

### Creating Custom Roles

Custom roles are managed through the Admin Tool:

1. Navigate to the Admin Tool
2. Go to the Roles tab
3. Click "Add" and enter a role name (single lowercase word recommended)
4. Click "Edit" to configure permissions for the role

![Add Role](/img/guides/roles-permissions/add_role.png)

### Custom Role Permissions

Custom roles can have granular permissions that target specific resources:

- **target_name** - Restrict permission to a specific target
- **packet_name** - Restrict permission to a specific packet
- **interface_name** - Restrict permission to a specific interface
- **router_name** - Restrict permission to a specific router

Example: A custom role could allow `cmd` permission only for the `INST1` target.

![Edit Role](/img/guides/roles-permissions/edit_role.png)

## Authorization Flow

When a user attempts an action, COSMOS Enterprise performs the following checks:

1. **Token Validation** - Verify the JWT token from Keycloak
2. **Role Extraction** - Extract roles from the token's `realm_access` claim
3. **Scope Matching** - Match user roles against the requested scope or `ALLSCOPES`
4. **Permission Check** - Verify the action's required permission is granted by the role
5. **Resource Matching** - For custom roles, check if specific resources match
6. **Command Authority** - If applicable, verify command authority for the target

## Default Users

COSMOS Enterprise Keycloak realm includes default test users for each role:

| Username | Password | Default Role | Email |
|----------|----------|--------------|-------|
| operator | operator | DEFAULT__operator | operator@openc3.com |
| runner | runner | DEFAULT__runner | runner@openc3.com |
| viewer | viewer | DEFAULT__viewer | viewer@openc3.com |
| admin | admin | ALLSCOPES__admin | admin@openc3.com |
| approver | approver | DEFAULT__approver | approver@openc3.com |

**Note:** These are default development/testing accounts. In production deployments, you should configure proper authentication and remove or change these default credentials.

## Best Practices

1. **Principle of Least Privilege** - Assign users the minimum permissions needed for their role
2. **Use Scopes** - Leverage scopes to separate different missions or projects
3. **Custom Roles** - Create custom roles for specialized needs rather than giving admin access
4. **Command Authority** - Enable command authority for production systems to prevent conflicts
5. **Regular Audits** - Review user roles and permissions periodically
6. **Production Security** - Replace default credentials and integrate with your organization's SSO/IdP

## Managing Roles

### Viewing / Assigning Roles to Users

Roles are managed in Keycloak:

1. Access the Keycloak admin console
2. Navigate to Users
3. Select a user
4. Go to Role Mappings
5. Assign roles using the `{SCOPE}__{ROLE_NAME}` format

![Keycloak User Roles](/img/guides/roles-permissions/keycloak_user_roles.png)