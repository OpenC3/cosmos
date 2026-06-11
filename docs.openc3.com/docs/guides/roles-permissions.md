---
title: Roles and Permissions
description: Understanding COSMOS Enterprise roles and access control
sidebar_custom_props:
  myEmoji: 🔐
---

COSMOS Enterprise provides a comprehensive role-based access control (RBAC) system that allows you to manage user permissions across different scopes. This system integrates with Keycloak for authentication and authorization.

## Overview

Roles in COSMOS Enterprise control what actions users can perform within the system. Roles are assigned to users per scope, allowing fine-grained control over access to different missions or projects.

Roles involve two systems working together:

1. **Keycloak** assigns roles to users. A user's roles are carried in their JWT token as Keycloak realm roles named `{SCOPE}__{ROLE_NAME}` (e.g. `DEFAULT__operator`).
2. **COSMOS** defines what each role is allowed to do. The five built-in roles (admin, operator, viewer, approver, runner) have permission sets built into COSMOS itself, so they only need to exist as realm roles in Keycloak. Custom roles additionally require a role definition in COSMOS (created through the Admin Tool or the [REST API](#role-management-rest-api)) that lists the role's permissions.

This means creating a custom role is a two-part process: define the role and its permissions in COSMOS, **and** create a matching `{SCOPE}__{ROLE_NAME}` realm role in Keycloak and assign it to users. Creating a role in COSMOS does not create the Keycloak realm role (or vice versa) — if either half is missing, the role grants no permissions.

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

The **Admin** role provides administrative access within a scope. Admins can also manage the files within Bucket Explorer.

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

Creating a custom role requires two steps:

1. **Define the role in COSMOS** with its permission set, using the Admin Tool or the [REST API](#role-management-rest-api).
2. **Create and assign the role in Keycloak** as a realm role named `{SCOPE}__{ROLE_NAME}` (e.g. `DEFAULT__inst_commander`), using the Keycloak admin console (see [Viewing / Assigning Roles to Users](#viewing--assigning-roles-to-users)) or the [Keycloak Admin REST API](#assigning-roles-via-the-keycloak-admin-rest-api).

Both steps are required. The Keycloak realm role puts the role name in the user's token, and the COSMOS role definition maps that name to permissions. A custom role assigned in Keycloak without a COSMOS definition grants no permissions, and a COSMOS role definition with no Keycloak realm role is never assigned to anyone.

### Creating Custom Roles

Custom roles are managed through the Admin Tool or programmatically via the [REST API](#role-management-rest-api):

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

## Role Management REST API

In addition to the Admin Tool, COSMOS Enterprise provides REST endpoints for role CRUD (create, read, update, delete) operations. These are useful for automation and integration workflows, such as provisioning roles as part of a deployment pipeline.

:::warning[Keycloak realm role required]
These endpoints only manage the COSMOS side of a role (its permission definition). They do not create or delete the corresponding Keycloak realm role. For users to actually receive a custom role, you must also create a `{SCOPE}__{ROLE_NAME}` realm role in Keycloak and assign it to users — see [Assigning Roles via the Keycloak Admin REST API](#assigning-roles-via-the-keycloak-admin-rest-api) below.
:::

All endpoints require an `Authorization` header containing a Keycloak access token and a `scope` query parameter. See [Testing with Curl](/docs/guides/curl) for details on obtaining and refreshing tokens.

### Endpoints

| Method      | Endpoint                  | Required Permission              | Description                                                |
| ----------- | ------------------------- | -------------------------------- | ---------------------------------------------------------- |
| GET         | `/openc3-api/roles`       | `admin`                          | List all role names                                        |
| GET         | `/openc3-api/roles/:name` | `system`                         | Get a role's definition (use `all` to return every role)   |
| POST        | `/openc3-api/roles`       | `superadmin` (`ALLSCOPES__admin`) | Create a role                                              |
| PUT / PATCH | `/openc3-api/roles/:name` | `superadmin` (`ALLSCOPES__admin`) | Update a role (replaces the entire permissions list)       |
| DELETE      | `/openc3-api/roles/:name` | `superadmin` (`ALLSCOPES__admin`) | Delete a role                                              |

### Role Definition Format

The POST and PUT endpoints accept a request body with a `json` field containing the role definition as a JSON-encoded string:

```json
{
  "name": "inst_commander",
  "permissions": [
    { "permission": "tlm" },
    { "permission": "cmd", "target_name": "INST" }
  ]
}
```

Each entry in `permissions` requires a `permission` name (see [Permission Definitions](#permission-definitions)) and optionally accepts `target_name`, `packet_name`, `interface_name`, or `router_name` to restrict the permission to a specific resource. Omitting the resource fields grants the permission for all resources.

**Note:** Creating a role with an empty `permissions` list automatically seeds it with the Viewer permissions (`system`, `tlm`, `cmd_info`, `script_view`, `notebook_view`).

### Examples

First obtain an access token from Keycloak as described in [Testing with Curl](/docs/guides/curl#curl-example-with-openc3-cosmos-enterprise) (the user must have `ALLSCOPES__admin` for create / update / delete):

```bash
ACCESS_TOKEN=$(curl -s -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'username=admin&password=admin&client_id=api&grant_type=password' \
  -X POST http://localhost:2900/auth/realms/openc3/protocol/openid-connect/token | jq -r .access_token)
```

List all roles:

```bash
curl -H "Authorization: $ACCESS_TOKEN" "http://localhost:2900/openc3-api/roles?scope=DEFAULT"
# => ["admin","approver","inst_commander","operator","runner","viewer"]
```

Create a role:

```bash
curl -H "Authorization: $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"json": "{\"name\":\"inst_commander\",\"permissions\":[{\"permission\":\"tlm\"},{\"permission\":\"cmd\",\"target_name\":\"INST\"}]}"}' \
  -X POST "http://localhost:2900/openc3-api/roles?scope=DEFAULT"
```

Get a role's definition:

```bash
curl -H "Authorization: $ACCESS_TOKEN" "http://localhost:2900/openc3-api/roles/inst_commander?scope=DEFAULT"
# => {"name":"inst_commander","permissions":[{"permission":"tlm"},{"permission":"cmd","target_name":"INST"}],"updated_at":1768424881396924134}
```

Update a role (the permissions list is fully replaced, so read the current definition first if you want to add to it):

```bash
curl -H "Authorization: $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"json": "{\"name\":\"inst_commander\",\"permissions\":[{\"permission\":\"tlm\"},{\"permission\":\"cmd\",\"target_name\":\"INST\"},{\"permission\":\"script_run\"}]}"}' \
  -X PUT "http://localhost:2900/openc3-api/roles/inst_commander?scope=DEFAULT"
```

Delete a role:

```bash
curl -H "Authorization: $ACCESS_TOKEN" \
  -X DELETE "http://localhost:2900/openc3-api/roles/inst_commander?scope=DEFAULT"
```

### Assigning Roles via the Keycloak Admin REST API

The COSMOS role defines the permission set, but users receive roles through Keycloak. To complete the automation workflow, create a matching Keycloak realm role named `{SCOPE}__{ROLE_NAME}` and assign it to users using the Keycloak Admin REST API:

```bash
# Get a Keycloak admin token (master realm)
KC_TOKEN=$(curl -s -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'username=<keycloak-admin>&password=<password>&client_id=admin-cli&grant_type=password' \
  -X POST http://localhost:2900/auth/realms/master/protocol/openid-connect/token | jq -r .access_token)

# Create the realm role in the openc3 realm
curl -H "Authorization: Bearer $KC_TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "DEFAULT__inst_commander"}' \
  -X POST http://localhost:2900/auth/admin/realms/openc3/roles

# Look up the user and role, then assign the role to the user
USER_ID=$(curl -s -H "Authorization: Bearer $KC_TOKEN" \
  "http://localhost:2900/auth/admin/realms/openc3/users?username=operator" | jq -r '.[0].id')
ROLE=$(curl -s -H "Authorization: Bearer $KC_TOKEN" \
  http://localhost:2900/auth/admin/realms/openc3/roles/DEFAULT__inst_commander)
curl -H "Authorization: Bearer $KC_TOKEN" -H "Content-Type: application/json" \
  -d "[$ROLE]" \
  -X POST "http://localhost:2900/auth/admin/realms/openc3/users/$USER_ID/role-mappings/realm"
```

For full details on the available endpoints, authentication options, and payloads, see the [Keycloak Admin REST API documentation](https://www.keycloak.org/docs-api/latest/rest-api/index.html) and the [Keycloak Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html#assigning-permissions-using-roles-and-groups).

## Authorization Flow

When a user attempts an action, COSMOS Enterprise performs the following checks:

1. **Token Validation** - Verify the JWT token from Keycloak
2. **Role Extraction** - Extract roles from the token's `realm_access` claim
3. **Scope Matching** - Match user roles against the requested scope or `ALLSCOPES`
4. **Permission Check** - Verify the action's required permission is granted by the role
5. **Resource Matching** - For custom roles, check if specific resources match
6. **Command Authority** - If applicable, verify command authority for the target

## Default Users

COSMOS Enterprise Keycloak realm includes default test users:

| Username | Password | Roles                                                                | Email               |
| -------- | -------- | -------------------------------------------------------------------- | ------------------- |
| admin    | admin    | ALLSCOPES\_\_admin, ALLSCOPES\_\_operator, ALLSCOPES\_\_approver      | admin@openc3.com    |
| operator | operator | ALLSCOPES\_\_operator                                                 | operator@openc3.com |
| approver | approver | ALLSCOPES\_\_approver                                                 | approver@openc3.com |
| viewer   | viewer   | ALLSCOPES\_\_viewer (via default role)                                | viewer@openc3.com   |

The realm's default role (`default-roles-openc3`) includes `ALLSCOPES__viewer`, so every user — including newly created ones — receives viewer access across all scopes by default.

:::warning[Default credentials]
These are default development/testing accounts. In production deployments, you should configure proper authentication and remove or change these default credentials.
:::

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

#### User Group Role from LDAP Federation

If you have instead imported user groups from an LDAP user federation system, you can instead assign roles to user groups rather than individual users, but you must do the following:

1. Navigate to "Client Scopes"
2. Click on the "roles" scope
3. Go to the "Mappers" tab
4. Click "Add mapper" then "From predefined mappers"
5. Search for "groups" and check the box next to that, then click "Add"

![Keycloak Groups Token Mapper](/img/guides/roles-permissions/keycloak_groups_token_mapper.png)
