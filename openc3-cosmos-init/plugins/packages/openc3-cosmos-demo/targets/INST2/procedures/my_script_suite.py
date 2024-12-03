from openc3.script.suite import Group, Suite

load_utility("INST2/procedures/utilities/clear.py")


class ExampleGroup(Group):
    def setup(self):
        print("Setup")

    def script_run_method_with_long_name(self):
        print(
            f"Running {Group.current_suite()}:{Group.current_group()}:{Group.current_script()}"
        )
        Group.print("This test verifies requirement 1")
        raise RuntimeError("error")
        print("continue past raise")  # NOSONAR

    def script_2(self):
        print(
            f"Running {Group.current_suite()}:{Group.current_group()}:{Group.current_script()}"
        )
        Group.print("This test verifies requirement 2")
        self.helper()
        wait(2)

    def script_3(self):
        print(
            f"Running {Group.current_suite()}:{Group.current_group()}:{Group.current_script()}"
        )
        raise SkipScript

    def helper(self):
        if RunningScript.manual:
            answer = ask("Are you sure?")
        else:
            answer = "y"

    def teardown(self):
        print("teardown")


class MySuite(Suite):
    def __init__(self):
        super().__init__()
        self.add_group(ExampleGroup)
