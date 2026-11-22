# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time
from typing import Any

from openc3.environment import OPENC3_KEYCLOAK_URL, OPENC3_SCOPE
from openc3.script.server_proxy import ApiServerProxy, ScriptServerProxy
from openc3.utilities.authentication import OpenC3KeycloakAuthentication
from openc3.utilities.extract import convert_to_value


API_SERVER = ApiServerProxy()
SCRIPT_RUNNER_API_SERVER = ScriptServerProxy()
RUNNING_SCRIPT = None
DISCONNECT = False
OPENC3_IN_CLUSTER = False
if "openc3-cosmos-cmd-tlm-api" in API_SERVER.generate_url():
    OPENC3_IN_CLUSTER = True


def shutdown_script() -> None:
    """Shut down the connections to the COSMOS API and Script Runner API servers."""
    global API_SERVER
    API_SERVER.shutdown()
    global SCRIPT_RUNNER_API_SERVER
    SCRIPT_RUNNER_API_SERVER.shutdown()


def prompt_for_hazardous(target_name: str, cmd_name: str, hazardous_description: str | None) -> bool:
    """Ask the user whether to send a hazardous command.

    Script Runner replaces this command line version with a dialog.

    Args:
        target_name: Target name of the command.
        cmd_name: Command name.
        hazardous_description: Description of why the command is hazardous.

    Returns:
        Whether the user answered yes.
    """
    message_list = [f"Warning: Command {target_name} {cmd_name} is Hazardous. "]
    if hazardous_description:
        message_list.append(hazardous_description)
    message_list.append("Send? (y/N): ")
    answer = input("\n".join(message_list))
    try:
        return answer.lower()[0] == "y"
    except IndexError:
        return False


def _file_dialog(title: str, message: str, filter: str | None = None):
    answer = ""
    while len(answer) == 0:
        print(f"{title}\n{message}\n<Type file name>:")
        answer = input()
    return answer


###########################################################################
# START PUBLIC API
###########################################################################


def disconnect_script() -> None:
    """Put scripting in disconnect mode.

    In disconnect mode commands are logged and validated but not sent.
    """
    global DISCONNECT
    DISCONNECT = True


def ask_string(question: str, blank_or_default: Any = False, password: bool = False) -> str:
    """Prompt the user for input with a question and return the answer as a string.

    Script Runner replaces this command line version with a dialog.

    Args:
        question: Question to prompt the user with.
        blank_or_default: Whether to allow empty responses. A non-boolean
            value is used as the default value.
        password: Whether to treat the entry as a password. Unused by the
            command line version.

    Returns:
        The user's answer.
    """
    answer = ""
    default = None
    if blank_or_default is not True and blank_or_default is not False:
        question += f" (default = {blank_or_default})"
        default = str(blank_or_default)
        allow_blank = True
    else:
        allow_blank = blank_or_default
    while len(answer) == 0:
        print(question + " ")
        answer = input()
        if allow_blank:
            break
    if len(answer) == 0 and default:
        answer = default
    return answer


def ask(question: str, blank_or_default: Any = False, password: bool = False) -> Any:
    """Prompt the user for input with a question and convert the answer to a value.

    The answer is converted to an int, float, list etc. if it looks like one.
    Script Runner replaces this command line version with a dialog.

    Args:
        question: Question to prompt the user with.
        blank_or_default: Whether to allow empty responses. A non-boolean
            value is used as the default value.
        password: Whether to treat the entry as a password. Unused by the
            command line version.

    Returns:
        The user's answer converted to a value.
    """
    string = ask_string(question, blank_or_default, password)
    value = convert_to_value(string)
    return value


def message_box(string: str, *buttons: str, **options: Any) -> str:
    """Prompt the user with a message and buttons to choose from.

    Script Runner replaces this command line version with a dialog.

    Args:
        string: Message to prompt the user with.
        *buttons: Text for each button.
        **options: Optional informative and details text to add to the dialog.

    Returns:
        The text of the button the user chose.
    """
    print(f"{string} ({', '.join(buttons)}): ")
    if "details" in options:
        print(f"Details: {options['details']}\n")
    return input()


def vertical_message_box(string: str, *buttons: str, **options: Any) -> str:
    """Prompt the user with a message and vertically stacked buttons to choose from.

    Script Runner replaces this command line version with a dialog.

    Args:
        string: Message to prompt the user with.
        *buttons: Text for each button.
        **options: Optional informative and details text to add to the dialog.

    Returns:
        The text of the button the user chose.
    """
    return message_box(string, *buttons, **options)


def combo_box(string: str, *buttons: str, **options: Any) -> Any:
    """Prompt the user with a message and a list of selections to choose from.

    Script Runner replaces this command line version with a dialog.

    Args:
        string: Message to prompt the user with.
        *buttons: Text for each selection.
        **options: Optional informative and details text to add to the
            dialog, and multiple=True to allow selecting several items.

    Returns:
        The text of the selection the user chose, or a list of them when
        multiple selections are allowed.
    """
    return message_box(string, *buttons, **options)


def check_box(string: str, *buttons: str, **options: Any) -> Any:
    """Prompt the user with a message and checkboxes to select.

    Script Runner replaces this command line version with a dialog.

    Args:
        string: Message to prompt the user with.
        *buttons: Text for each checkbox.
        **options: Optional informative and details text to add to the dialog.

    Returns:
        The text of the checkboxes the user selected. The command line version
        returns the typed answer as a string.
    """
    return message_box(string, *buttons, **options)


def open_file_dialog(title: str, message: str = "Open File", filter: str | None = None) -> Any:
    """Prompt the user to select a single file.

    Script Runner replaces this command line version with a file dialog that
    returns the selected file. The command line version prompts for a file
    name and returns it.

    Args:
        title: Title to put on the dialog.
        message: Message to display in the dialog.
        filter: Comma delimited file types to allow, e.g. ".txt,.doc".

    Returns:
        The selected file in Script Runner, otherwise the file name typed at the prompt.
    """
    return _file_dialog(title, message, filter)


def open_files_dialog(title: str, message: str = "Open File", filter: str | None = None) -> Any:
    """Prompt the user to select one or more files.

    Script Runner replaces this command line version with a file dialog that
    returns a list of the selected files. The command line version prompts
    for a file name and returns it.

    Args:
        title: Title to put on the dialog.
        message: Message to display in the dialog.
        filter: Comma delimited file types to allow, e.g. ".txt,.doc".

    Returns:
        The list of selected files in Script Runner, otherwise the file name
        typed at the prompt.
    """
    return _file_dialog(title, message, filter)


def open_bucket_dialog(
    title: str, message: str = "Open Bucket File", default_path: str | None = None, filter: str | None = None
) -> Any:
    """Prompt the user to select a file from a bucket.

    Script Runner replaces this command line version with a bucket browser
    dialog that returns the selected file. The command line version returns
    the typed bucket file path.

    Args:
        title: Title to put on the dialog.
        message: Message to display in the dialog.
        default_path: Path to preselect in the form bucket/path/to/file.ext,
            or bucket/path/to/folder/ for a folder.
        filter: Comma delimited file suffixes to list, e.g. ".txt,.json".

    Returns:
        The selected file in Script Runner, otherwise the typed path as a string.
    """
    answer = ""
    hint = f" [default: {default_path}]" if default_path else ""
    if filter:
        hint += f" filter: {filter}"
    while len(answer) == 0:
        print(f"{title}\n{message}\n<Type bucket file path (e.g. BUCKET/path/to/file)>{hint}:")
        answer = input()
    return answer


def prompt(
    string: str,
    text_color: str | None = None,
    background_color: str | None = None,
    font_size: int | None = None,
    font_family: str | None = None,
    details: str | None = None,
) -> str:
    """Prompt the user with a message and wait for them to acknowledge it.

    Script Runner replaces this command line version with a dialog. The
    styling arguments are only used by Script Runner.

    Args:
        string: Message to prompt the user with.
        text_color: Color of the message text.
        background_color: Background color of the dialog.
        font_size: Font size of the message text.
        font_family: Font family of the message text.
        details: Additional details to display.

    Returns:
        The user's response.
    """
    print(f"{string}: ")
    if details:
        print(f"Details: {details}\n")
    return input()


def step_mode() -> None:
    """Switch Script Runner to step mode, pausing before each line.

    Has no effect outside Script Runner.
    """
    # running_script.py implements the real functionality
    pass


def run_mode() -> None:
    """Switch Script Runner back to run mode after `step_mode`.

    Has no effect outside Script Runner.
    """
    # running_script.py implements the real functionality
    pass


from openc3.api import WHITELIST

from .api_shared import *
from .autonomic import *
from .commands import *
from .cosmos_calendar import *
from .critical_cmd import *
from .exceptions import *
from .limits import *
from .metadata import *
from .packages import *
from .plugins import *
from .queue import *
from .screen import *
from .script_runner import *
from .storage import *
from .tables import *
from .telemetry import *


def initialize_offline_access(scope: str = OPENC3_SCOPE) -> None:
    """Set up an offline access token so that users can run scripts.

    Enterprise only. Use this for first time setup. It is not necessary when
    accessing the APIs through the web frontend as it handles it automatically.

    Example::

        initialize_offline_access()
        script_run("INST/procedures/collect.rb")

    Args:
        scope: COSMOS scope to set the offline access token in.

    Raises:
        RuntimeError: If not running COSMOS Enterprise (OPENC3_KEYCLOAK_URL is not set).
    """
    if not OPENC3_KEYCLOAK_URL:
        raise RuntimeError(
            "initialize_offline_access only valid in COSMOS Enterprise. OPENC3_KEYCLOAK_URL environment variable must be set."
        )
    auth = OpenC3KeycloakAuthentication(OPENC3_KEYCLOAK_URL)
    auth.token(include_bearer=True, openid_scope="openid offline_access")
    # set_offline_access is generated from the API WHITELIST at the end of this module
    set_offline_access(auth.refresh_token, scope=scope)  # ty: ignore[unresolved-reference]


###########################################################################
# END PUBLIC API
###########################################################################


def prompt_for_critical_cmd(
    uuid: str,
    _username: str,
    _target_name: str,
    _cmd_name: str,
    _cmd_params: dict[str, Any],
    cmd_string: str,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Wait for a critical command to be approved.

    Script Runner replaces this command line version with a dialog.

    Args:
        uuid: UUID of the critical command.
        _username: User who sent the command. Unused by the command line version.
        _target_name: Target name of the command. Unused by the command line version.
        _cmd_name: Command name. Unused by the command line version.
        _cmd_params: Command parameters. Unused by the command line version.
        cmd_string: The command as it appears in a script.
        scope: COSMOS scope the command was sent in.

    Raises:
        RuntimeError: If the command is rejected.
    """
    print("Waiting for critical command approval:")
    print(f"  {cmd_string}")
    print(f"  UUID: {uuid}")
    while True:
        status = critical_cmd_status(uuid, scope=scope)
        if status == "APPROVED":
            return
        elif status == "REJECTED":
            raise RuntimeError("Critical command rejected")
        time.sleep(0.1)


# Define all the WHITELIST methods
current_functions = dir()
for func in WHITELIST:
    if func not in current_functions:
        code = f"def {func}(*args, **kwargs):\n    return getattr(API_SERVER, '{func}')(*args, **kwargs)"
        function = compile(code, "<string>", "exec")
        exec(function, globals())
