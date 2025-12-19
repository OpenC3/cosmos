# Docker Compose Template System

This document describes the template-based system for generating `compose.yaml` files for both OpenC3 Core and OpenC3 Enterprise editions.

## Overview

The compose file generation system uses:
- **Single source of truth**: `compose.yaml.template` in the core repository
- **Mode-specific overrides**: `compose.core.yaml` and `compose.enterprise.yaml`
- **Generator script**: `scripts/release/generate_compose.py`

This approach ensures:
- Core maintains the authoritative compose structure
- Enterprise only specifies differences/additions
- Minimal maintenance in enterprise repository
- Automatic pickup of core updates

## Architecture

```
compose.yaml.template (in core)
    +
compose.core.yaml (overrides)
    ↓
generate_compose.py
    ↓
compose.yaml (core edition)

compose.yaml.template (in core)
    +
compose.enterprise.yaml (overrides)
    ↓
generate_compose.py
    ↓
compose.yaml (enterprise edition)
```

## File Locations

- **Template**: `/path/to/cosmos/compose.yaml.template`
- **Core overrides**: `/path/to/cosmos/compose.core.yaml`
- **Enterprise overrides**: `/path/to/cosmos-enterprise/compose.enterprise.yaml`
- **Generator**: `/path/to/cosmos/scripts/release/generate_compose.py` (or `cosmos-enterprise/scripts/release/generate_compose.py`)

## Placeholder Syntax

Placeholders in the template use double curly braces:

```yaml
{{PLACEHOLDER_NAME}}
```

### Rules

1. **Naming**: Use `UPPER_SNAKE_CASE` for placeholder names
2. **Pattern**: Must match regex `\{\{(\w+)\}\}`
3. **Replacement**: Exact string replacement (no escaping needed)
4. **Empty values**: Can be set to empty string `""` to remove content

### Multi-line Values

For multi-line placeholder values, use YAML literal block syntax with proper indentation:

```yaml
PLACEHOLDER_NAME: |2
  line 1 content
  line 2 content
```

The `|2` means:
- `|` = literal block scalar (preserves newlines)
- `2` = strip 2 spaces of indentation from each line

## Available Placeholders

### Image Configuration

| Placeholder | Purpose | Core Value | Enterprise Value |
|-------------|---------|------------|------------------|
| `LICENSE_HEADER` | File license header | AGPL license | Commercial license |
| `REGISTRY_VAR` | Registry env var name | `OPENC3_REGISTRY` | `OPENC3_ENTERPRISE_REGISTRY` |
| `NAMESPACE_VAR` | Namespace env var name | `OPENC3_NAMESPACE` | `OPENC3_ENTERPRISE_NAMESPACE` |
| `TAG_VAR` | Tag env var name | `OPENC3_TAG` | `OPENC3_ENTERPRISE_TAG` |
| `IMAGE_PREFIX` | Docker image prefix | `openc3-` | `openc3-enterprise-` |

### Directory Names

| Placeholder | Purpose | Core Value | Enterprise Value |
|-------------|---------|------------|------------------|
| `REDIS_DIR` | Redis config directory | `openc3-redis` | `openc3-enterprise-redis` |
| `TRAEFIK_DIR` | Traefik config directory | `openc3-traefik` | `openc3-enterprise-traefik` |

### Service-Specific Images

| Placeholder | Purpose | Core Value | Enterprise Value |
|-------------|---------|------------|------------------|
| `CMD_TLM_API_IMAGE` | Command/Telemetry API image | `openc3-cosmos-cmd-tlm-api` | `openc3-cosmos-enterprise-cmd-tlm-api` |
| `SCRIPT_RUNNER_API_IMAGE` | Script Runner API image | `openc3-cosmos-script-runner-api` | `openc3-cosmos-enterprise-script-runner-api` |
| `COSMOS_INIT_IMAGE` | Initialization service image | `openc3-cosmos-init` | `openc3-cosmos-enterprise-init` |

### Environment Configuration

| Placeholder | Purpose | Core Value | Enterprise Value |
|-------------|---------|------------|------------------|
| `ENV_FILE` | Environment file path | `.env` | `".env"` (quoted) |

### Service Customization

| Placeholder | Purpose | Type | Core Value | Enterprise Value |
|-------------|---------|------|------------|------------------|
| `MINIO_PORTS` | MinIO port mappings | Optional | Commented ports | Empty (no ports) |
| `CMD_TLM_API_SERVICE_PASSWORD` | Service password env var | Optional | Set with env var | Empty |
| `CMD_TLM_API_EXTRA_HOSTS` | Extra hosts config | Optional | `host.docker.internal` | Empty |
| `SCRIPT_RUNNER_API_SERVICE_PASSWORD` | Service password env var | Optional | Set with env var | Empty |
| `OPERATOR_PORTS` | Operator port mappings | Optional | Commented ports | Empty |
| `OPERATOR_VOLUME_COMMENTS` | Operator volume examples | Optional | Commented volumes | Commented volumes |
| `OPERATOR_CI_ENV` | CI environment variable | Optional | Set with CI var | Empty |
| `OPERATOR_SERVICE_PASSWORD` | Service password env var | Optional | Set with env var | Empty |
| `OPERATOR_COMMAND` | Operator command override | Optional | Empty (default cmd) | Ruby microservice operator |
| `INIT_CI_ENV` | CI environment variable | Optional | Set with CI var | Empty |

### Mode-Specific Services

| Placeholder | Purpose | Type | Core Value | Enterprise Value |
|-------------|---------|------|------------|------------------|
| `ENTERPRISE_SERVICES` | Additional services for enterprise | Required | Empty | `openc3-metrics` service definition |
| `ENTERPRISE_ONLY_SERVICES` | Enterprise-exclusive services | Required | Empty | PostgreSQL, Keycloak, Grafana services |
| `ENTERPRISE_VOLUMES` | Enterprise-specific volumes | Required | Empty | PostgreSQL and Grafana volumes |

## Placeholder Categories

### Required Placeholders

These **must** be defined in override files (cannot be empty):

- `LICENSE_HEADER`
- `REGISTRY_VAR`, `NAMESPACE_VAR`, `TAG_VAR`
- `IMAGE_PREFIX`
- `REDIS_DIR`, `TRAEFIK_DIR`
- `CMD_TLM_API_IMAGE`, `SCRIPT_RUNNER_API_IMAGE`, `COSMOS_INIT_IMAGE`
- `ENV_FILE`

### Optional Placeholders

These **can** be empty strings in override files:

- All service customization placeholders (ports, passwords, volumes, etc.)
- All mode-specific service and volume placeholders

## Usage

### Generating Compose Files

#### In Core Repository

```bash
cd /path/to/cosmos
./scripts/release/generate_compose.py --mode core
```

This generates `compose.yaml` using:
- Template: `./compose.yaml.template`
- Overrides: `./compose.core.yaml`

#### In Enterprise Repository

```bash
cd /path/to/cosmos-enterprise
../cosmos/scripts/release/generate_compose.py --mode enterprise --template ../cosmos/compose.yaml.template
```

This generates `compose.yaml` using:
- Template: `../cosmos/compose.yaml.template`
- Overrides: `./compose.enterprise.yaml`

### Validation

By default, the generator validates the output. Use `--no-validate` to skip:

```bash
./scripts/release/generate_compose.py --mode core --no-validate
```

### Dry Run

To preview output without writing:

```bash
./scripts/release/generate_compose.py --mode core --dry-run
```

### Integration with openc3.sh

The `openc3.sh` script automatically detects the mode and generates the compose file:

```bash
./openc3.sh util compose
```

## Adding New Placeholders

### 1. Add to Template

Add the placeholder where needed in `compose.yaml.template`:

```yaml
services:
  my-service:
{{NEW_PLACEHOLDER}}
    image: example
```

### 2. Add to Core Override

Add the value to `compose.core.yaml`:

```yaml
NEW_PLACEHOLDER: |2
    environment:
      FOO: bar
```

### 3. Add to Enterprise Override

Add the value to `compose.enterprise.yaml` (can be different or empty):

```yaml
NEW_PLACEHOLDER: ""
```

### 4. Update Documentation

Add the new placeholder to this README in the appropriate table.

## Naming Conventions

### Placeholders

- Use `UPPER_SNAKE_CASE`
- Be descriptive and specific
- Group related placeholders with common prefixes:
  - `OPERATOR_*` for operator service customizations
  - `CMD_TLM_API_*` for CMD/TLM API customizations
  - `ENTERPRISE_*` for enterprise-specific additions

### Override Keys

Must match placeholder names exactly (case-sensitive).

## Validation Rules

The generator validates:

1. **YAML Syntax**: Generated output must be valid YAML
2. **Required Keys**: Must have `services` and `volumes` top-level keys
3. **Placeholders**: No unreplaced `{{PLACEHOLDER}}` markers remain
4. **Service Structure**: Each service must be a dict with an `image` key
5. **Mode-Specific**:
   - **Enterprise**: Must contain `openc3-postgresql`, `openc3-keycloak`, `openc3-grafana`
   - **Core**: Must NOT contain any enterprise-only services

## Best Practices

### For Template Authors

1. **Keep placeholders inline** where possible to avoid blank lines
2. **Use consistent indentation** (2 spaces per level)
3. **Document intent** of each placeholder in this README
4. **Test both modes** after template changes
5. **Use multi-line format** (`|2`) for complex values

### For Override Authors

1. **Match indentation** with the template context
2. **Use empty string `""`** to remove optional content, not `null`
3. **Preserve formatting** (comments, spacing) in multi-line values
4. **Test generation** after changes
5. **Keep enterprise overrides minimal** - only specify differences

### For Maintenance

1. **Core is source of truth** - make structural changes in the template
2. **Enterprise tracks core** - update overrides when template changes
3. **Validate after changes** - run with `--validate` flag
4. **Document breaking changes** - update this README
5. **Version compatibility** - consider adding template version field

## Troubleshooting

### Unreplaced Placeholders

**Error**: `Warning: The following placeholders were not replaced: FOO_BAR`

**Solution**: Add `FOO_BAR` to your override file with an appropriate value (or empty string).

### Invalid YAML

**Error**: `Invalid YAML syntax: ...`

**Solution**: Check indentation in multi-line override values. Ensure they use `|2` and have consistent 2-space indentation.

### Missing Services (Enterprise)

**Error**: `Enterprise mode missing expected service: openc3-keycloak`

**Solution**: Ensure `ENTERPRISE_ONLY_SERVICES` in `compose.enterprise.yaml` includes all required services.

### Extra Services (Core)

**Error**: `Core mode should not contain enterprise service: openc3-metrics`

**Solution**: Ensure `ENTERPRISE_SERVICES` in `compose.core.yaml` is set to empty string `""`.

### Unused Overrides

**Warning**: `Override key 'OLD_PLACEHOLDER' has no corresponding placeholder in template`

**Solution**: Remove the unused key from your override file, or add the corresponding placeholder to the template if it should exist.

## Examples

### Example: Adding a New Service Environment Variable

**Template change** (`compose.yaml.template`):

```yaml
  openc3-operator:
    environment:
{{OPERATOR_NEW_ENV}}
      GEM_HOME: "/gems"
```

**Core override** (`compose.core.yaml`):

```yaml
OPERATOR_NEW_ENV: |2
      MY_VAR: "core_value"
```

**Enterprise override** (`compose.enterprise.yaml`):

```yaml
OPERATOR_NEW_ENV: |2
      MY_VAR: "enterprise_value"
```

### Example: Adding Enterprise-Only Service

**Template change** (`compose.yaml.template`):

```yaml
{{ENTERPRISE_ONLY_SERVICES}}
volumes:
```

**Core override** (`compose.core.yaml`):

```yaml
ENTERPRISE_ONLY_SERVICES: ""
```

**Enterprise override** (`compose.enterprise.yaml`):

```yaml
ENTERPRISE_ONLY_SERVICES: |2
  openc3-new-service:
    image: "${OPENC3_ENTERPRISE_REGISTRY}/${OPENC3_ENTERPRISE_NAMESPACE}/openc3-enterprise-new-service:${OPENC3_ENTERPRISE_TAG}"
    restart: "unless-stopped"
```

## Version History

- **v1.0** (2025-01-XX): Initial template system with placeholder-based generation
- Added validation with `--validate` and `--no-validate` flags
- Integrated with `openc3.sh util compose` command

## Related Files

- [`compose.yaml.template`](./compose.yaml.template) - Template file
- [`compose.core.yaml`](./compose.core.yaml) - Core overrides
- [`compose.enterprise.yaml`](../cosmos-enterprise/compose.enterprise.yaml) - Enterprise overrides
- [`scripts/release/generate_compose.py`](./scripts/release/generate_compose.py) - Generator script
- [`openc3.sh`](./openc3.sh) - CLI wrapper with `util compose` command
