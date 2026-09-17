# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.

import unittest

from openc3.models.bridge_model import BridgeModel


class TestBridgeModel(unittest.TestCase):
    def test_enrollment_code_is_valid_only_within_ttl(self):
        model = BridgeModel(
            name="LAB1",
            scope="DEFAULT",
            enroll_code="one-time-code",
            enroll_code_generated_at=1_000,
        )

        self.assertTrue(model.enrollment_code_valid("one-time-code", 1_000))
        self.assertTrue(
            model.enrollment_code_valid(
                "one-time-code", 1_000 + BridgeModel.ENROLLMENT_CODE_TTL_SECONDS
            )
        )
        self.assertFalse(
            model.enrollment_code_valid(
                "one-time-code", 1_001 + BridgeModel.ENROLLMENT_CODE_TTL_SECONDS
            )
        )
        self.assertFalse(model.enrollment_code_valid("wrong-code", 1_001))

    def test_enrollment_codes_without_a_timestamp_fail_closed(self):
        model = BridgeModel(name="LAB1", scope="DEFAULT", enroll_code="legacy-code")

        self.assertFalse(model.enrollment_code_valid("legacy-code", 1_000))


if __name__ == "__main__":
    unittest.main()
