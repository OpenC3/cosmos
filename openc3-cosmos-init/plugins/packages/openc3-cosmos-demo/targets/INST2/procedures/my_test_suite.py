from openc3.tools.test_runner.test import Test, TestSuite, SkipTestCase


class ExampleTest(Test):
    def setup(self):
        print("Setup")

    def test_case_with_long_name(self):
        print(
            f"Running {Test.current_test_suite()}:{Test.current_test()}:{Test.current_test_case()}"
        )
        Test.print("This test verifies requirement 1")
        raise RuntimeError("error")
        print("continue past raise")  # NOSONAR

    def test_2(self):
        print(
            f"Running {Test.current_test_suite()}:{Test.current_test()}:{Test.current_test_case()}"
        )
        Test.print("This test verifies requirement 2")
        self.helper()
        wait(2)

    def test_3(self):
        print(
            f"Running {Test.current_test_suite()}:{Test.current_test()}:{Test.current_test_case()}"
        )
        raise SkipTestCase

    def helper(self):
        if openc3.script.RUNNING_SCRIPT and openc3.script.RUNNING_SCRIPT.manual:
            answer = ask("Are you sure?")
        else:
            answer = "y"

    def teardown(self):
        print("teardown")


class MyTestSuite(TestSuite):
    def __init__(self):
        super().__init__()
        self.add_test(ExampleTest)
