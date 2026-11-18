---
title: Notebooks (Enterprise)
description: Create and execute interactive procedures with steps for documentation, screens, and scripts
sidebar_custom_props:
  myEmoji: 📓
---

## Introduction

Notebooks is an interactive procedure tool that allows operators to create, execute, and track multi-step workflows. Each notebook consists of a series of steps that can include formatted documentation (Markdown), telemetry displays (Screens), and executable code (Scripts). Notebooks provide a structured way to guide operators through complex procedures while maintaining a complete audit trail of execution.

Notebooks are stored within COSMOS targets and can be created, edited, and executed through the Notebooks tool interface. Like screens and procedures, notebook definition files can be shipped in a plugin. See [Notebooks in Plugins](#notebooks-in-plugins). When a notebook is started, it creates a unique execution instance that tracks the completion status of each step.

Notebooks are similar to various e-procedure systems and Jupyter notebooks.

![Notebooks](/img/notebooks/notebooks.png)

## Notebooks Menus

### Notebook Menu Items

{/* Image sized to match up with bullets */}

<img src={require('@site/static/img/notebooks/notebook_menu.png').default}
alt="Notebook Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 150 + 'px'}} />

- Create a new notebook in the selected target
- Edit or view the current notebook definition
- View execution status of running and completed notebooks
  <br/>
  <br/>
  <br/>

#### New Notebook

Creates a new notebook within the currently selected target. You'll be prompted to enter a name for the notebook. The notebook name should be descriptive and follow your organization's naming conventions.

#### Edit Notebook

Opens a dialog showing the raw notebook definition. This allows advanced users to directly edit the notebook configuration syntax. When a notebook is running or completed, this option changes to "View Notebook" and becomes read-only.

#### Execution Status

The Execution Status dialog displays currently running notebooks and recently completed notebooks. This allows users to:

- Monitor active notebook executions across the system
- Connect to running notebooks to follow along with execution
- View completed notebooks to review execution history

![Execution Status](/img/notebooks/execution_status.png)

## Notebook Interface

The main Notebooks interface consists of several key areas:

### Selection Panel

At the top of the interface, you'll find drop-down menus to select:

- **Target** - The COSMOS target containing the notebooks
- **Notebook** - The specific notebook to view or execute
- **ID** - A unique identifier assigned when a notebook is started (read-only)
- **State** - The current execution state: empty (template), Running, or Completed

### Action Buttons

- **Start** - Begins execution of the notebook, creating a new instance with a unique ID
- **Complete** - Marks a running notebook as complete (requires all completable steps to be checked or confirmation)
- **Show Template** - Returns to the original template view after viewing a completed notebook

### Steps Area

The main area displays the notebook steps in order. Each step shows:

- Step content (markdown text, screen display, or script interface)
- Completion checkbox (for completable steps when running)
- Edit button (pencil icon) for modifying steps
- Drag handle for reordering steps (when not running)

## Step Types

Notebooks support several types of steps:

### Markdown Step

Markdown steps display formatted text content. They support standard Markdown syntax including:

- Headers
- Bold and italic text
- Bullet and numbered lists
- Links and images
- Code blocks

Markdown steps are ideal for procedure instructions, notes, warnings, and documentation.

![Markdown Step](/img/notebooks/markdown_step.png)

### Screen Step

Screen steps embed COSMOS telemetry screens directly within the notebook. You can either:

- **Reference an existing screen** - Select a target and screen from your COSMOS configuration
- **Define inline screen content** - Write custom screen definitions directly in the notebook

Screen steps allow operators to monitor relevant telemetry. Completing the screen step will capture the screen values at the time the step is completed.

![Screen Step](/img/notebooks/screen_step.png)

### Script Step

Script steps execute Ruby or Python code within the notebook context. You can either:

- **Reference an existing script** - Select a script file from your COSMOS scripts
- **Define inline script content** - Write custom script code directly in the notebook

Script steps include an embedded Script Runner interface that shows:

- The script code (read-only during execution)
- Log messages from script execution
- Execution controls (Start, Pause, Stop, Go, Retry)

![Script Step](/img/notebooks/script_step.png)

## Creating and Editing Notebooks

### Adding Steps

Click the "Add Step" button at the bottom of the notebook to add a new step. You'll be presented with a dialog to:

1. Select the step type (Markdown, Screen, or Script)
2. Configure the step content
3. Set optional properties like "Noncompletable"

### Editing Steps

Click the pencil icon next to any step to edit its content. The edit dialog allows you to:

- Modify the step content
- Change step properties
- Delete the step

When a notebook is running, you can still edit steps to make corrections. These changes are tracked as "redline" modifications in the execution history.

### Reordering Steps

When not running, you can drag steps using the drag handle (vertical dots icon) to reorder them.

### Step Properties

#### Noncompletable

Steps marked as "Noncompletable" do not show a checkbox when the notebook is running. Use this for informational steps that don't require operator acknowledgment. Not available for script steps.

## Running Notebooks

### Starting Execution

1. Select the target and notebook you want to execute
2. Click the **Start** button
3. The notebook will be assigned a unique ID and the state will change to "Running"
4. The URL will update to include the notebook ID for sharing

### Completing Steps

While a notebook is running:

- Completable steps show a checkbox
- Check the checkbox to mark a step as complete
- The completion is recorded with the operator's username and timestamp
- Script steps are automatically marked complete when the script finishes successfully

Scripts can be uncompleted and recompleted by rechecking the checkbox, or restarting the script. These actions are recorded in the notebook file.

### Completing the Notebook

When all required steps are complete (or after confirmation if some are incomplete):

1. Click the **Complete** button
2. If incomplete steps remain, you'll be prompted to confirm
3. The notebook state changes to "Completed"
4. The execution record is preserved for audit purposes

### Connecting to Running Notebooks

Other users can connect to a running notebook through the Execution Status dialog. This allows:

- Following along with procedure execution
- Monitoring progress across the team
- Taking over execution if needed (with appropriate permissions)

## Permissions

Notebooks respect COSMOS role-based access control:

| Role     | View | Edit | Execute |
| -------- | ---- | ---- | ------- |
| Admin    | ✓    | ✓    | ✓       |
| Operator | ✓    | ✓    | ✓       |
| Runner   | ✓    | ✗    | ✓       |
| Viewer   | ✓    | ✗    | ✗       |

Custom roles can be configured with specific permissions:

- `notebook_edit` - Allows editing notebook definitions
- `notebook_run` - Allows starting and completing notebooks

## Notebook Definition Syntax

Notebooks are stored as text files with a specific syntax. While most users will interact through the GUI, understanding the syntax helps with advanced editing:

```
STEP_START MARKDOWN
# Procedure Title

Follow these steps carefully.
STEP_END
NO_COMPLETE

STEP SCREEN INST HEALTH_STATUS

STEP_START SCRIPT
puts "Hello from script"
wait 1
STEP_END

STEP SCRIPT INST/procedures/collect.rb
```

Steps can define their content inline between `STEP_START` and `STEP_END`, or reference an existing file with a single-line `STEP`:

| Step Type | Inline (`STEP_START <type>` ... `STEP_END`)                              | Reference (`STEP <type> <args>`)                                 |
| --------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| MARKDOWN  | Markdown text                                                            | Not supported                                                    |
| SCREEN    | Screen definition (see [Screens](/docs/configuration/telemetry-screens)) | `STEP SCREEN <TARGET> <SCREEN>` (e.g. `STEP SCREEN INST HS`)     |
| SCRIPT    | Ruby or Python script code                                               | `STEP SCRIPT <TARGET>/procedures/<file>` (path to a script file) |

### Keywords

| Keyword              | Description                                                                |
| -------------------- | -------------------------------------------------------------------------- |
| `STEP_START <type>`  | Begins a step block with inline content (MARKDOWN, SCREEN, or SCRIPT)      |
| `STEP_END`           | Ends a step block                                                          |
| `STEP <type> <args>` | Single-line step referencing a screen or script file                       |
| `NO_COMPLETE`        | Marks the preceding step as non-completable                                |
| `STEP_UUID <uuid>`   | Stable step identifier used to merge concurrent edits. Added automatically |
| `VERSION <n>`        | Edit counter used to detect conflicting saves. Managed automatically       |
| `NOTEBOOK_START`     | Automatically added when execution begins                                  |
| `NOTEBOOK_COMPLETE`  | Automatically added when execution completes                               |
| `STEP_COMPLETE`      | Automatically added when a step is checked complete                        |
| `STEP_UNCOMPLETE`    | Automatically added when a step is unchecked complete                      |
| `REDLINE_STEP_START` | Marks an edited version of a step during execution                         |
| `REDLINE_STEP_END`   | Ends a redline block                                                       |
| `DATA`               | Single-line step data storage (DATA SCRIPT_ID 1)                           |
| `DATA_START`         | Begins a data block (DATA_START data_name)                                 |
| `DATA_END`           | Ends a data block                                                          |

## Notebooks in Plugins

Notebook definition files can be packaged in a plugin, the same way [screens](/docs/configuration/telemetry-screens) live in a target's `screens` folder and scripts live in its `procedures` folder. Put each notebook in the target's `notebooks` folder:

```
openc3-cosmos-gse/
  plugin.txt
  targets/
    GSE/
      notebooks/
        power_on.txt
        checkout.txt
      procedures/
        power_on.rb
      screens/
        status.txt
```

When the plugin is installed, the notebooks appear in the Notebooks tool under the specified target. The notebook name is the filename without the `.txt` extension.

### Creating a Plugin Notebook

Writing a notebook definition by hand is error prone, so build the notebook in the Notebooks tool first and then copy its definition into your plugin:

1. In the Notebooks tool, select a target and use **New Notebook** to create the notebook.
2. Add, edit, and reorder steps until the notebook works the way you want. Run it to verify the functionality.
3. Get the saved definition using either method:
   - Open **Edit Notebook** from the Notebook menu and copy the full text from the dialog.
   - In [Bucket Explorer](/docs/tools/bucket-explorer), open the config bucket and download `<SCOPE>/targets_modified/<TARGET>/notebooks/<name>.txt`.
4. Save the text as `targets/<TARGET>/notebooks/<name>.txt` in your plugin.

Copy the template, not a running or completed notebook. The definition of an executed notebook includes execution records (`NOTEBOOK_START`, `STEP_COMPLETE`, `DATA`, etc.) that should not be shipped in a plugin. Click **Show Template** first if needed.

The copied file includes `STEP_UUID` and `VERSION` lines. Leave them in place; the tool uses them to track edits.

### Plugin Notebook Rules

- Filenames must be lowercase and end in `.txt`. Other files in the folder are ignored.
- Files whose names start with an underscore (e.g. `_draft.txt`) are not listed in the tool.
- Notebook files are processed with [ERB](/docs/configuration/format#erb) at install time, like screens and other target `.txt` files. After copying a notebook from the tool, replace hardcoded target names with `<%= target_name %>` so the notebook still works if the target is renamed at install.

For example, a notebook copied from the tool and updated to use the installed target name:

```
VERSION 4
STEP_START MARKDOWN
# GSE Power On

Verify the GSE is connected before starting.
STEP_END
STEP_UUID 0f6d2a4e-6c1b-4f7e-9a51-3c2d7e8b9a10
NO_COMPLETE

STEP SCREEN <%= target_name %> STATUS
STEP_UUID 5b8e1c3a-2d4f-4a6b-8c9d-1e2f3a4b5c6d

STEP SCRIPT <%= target_name %>/procedures/power_on.rb
STEP_UUID 9a7b6c5d-4e3f-4210-8f9e-8d7c6b5a4f3e
```

If a user edits a plugin-provided notebook through the tool, the change is saved as a modified copy of the target file, so it survives plugin upgrades just like edited screens and procedures. See [Target Deployment](/docs/configuration/plugins#target-deployment). Executed notebooks are stored separately in the logs bucket, so upgrading or uninstalling the plugin does not delete execution records.

## Best Practices

### Procedure Design

- Start with a Markdown step explaining the procedure purpose and prerequisites
- Group related steps logically
- Use Screen steps to show relevant telemetry for monitoring
- Include verification steps after critical operations
- End with a summary or sign-off step

### Documentation

- Write clear, concise instructions in Markdown steps
- Include warnings and cautions prominently
- Reference relevant documentation or specifications

### Script Integration

- Keep inline scripts short and focused
- For complex operations, reference external script files
- Include appropriate error handling and retries
- Use `ask()` for operator inputs when needed

### Execution Tracking

- Use meaningful notebook names that identify the procedure
- Complete notebooks promptly to maintain accurate records
- Review completed notebooks for lessons learned
