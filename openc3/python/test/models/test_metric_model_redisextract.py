import unittest
from unittest.mock import patch, MagicMock
from openc3.models.metric_model import MetricModel
from openc3.utilities.store import Store, EphemeralStore

'''
This test program includes two main test cases:

1. `test_redis_extract_p50_and_p99_seconds`: This test case checks the `redis_extract_p50_and_p99_seconds` method with various inputs, including valid inputs, None, and an empty string.

2. `test_redis_metrics`: This test case mocks the `Store.info` and `EphemeralStore.info` methods to return predefined dictionaries of metrics. It then calls the `redis_metrics` method and verifies that all the metrics are correctly extracted and calculated.

To run this test, you would need to have the `openc3` package installed and accessible in your Python environment. The test uses the `unittest` framework and mocking to isolate the tested functions from external dependencies.

This test suite provides good coverage for the two methods in question, testing various scenarios and edge cases for `redis_extract_p50_and_p99_seconds`, and thoroughly checking all the metrics extracted and calculated by `redis_metrics`.
'''

class TestMetricModel(unittest.TestCase):

    def test_redis_extract_p50_and_p99_seconds(self):
        # Test with valid input
        value = "p50=1000000,p99=5000000"
        p50, p99 = MetricModel.redis_extract_p50_and_p99_seconds(value)
        self.assertEqual(p50, 1.0)
        self.assertEqual(p99, 5.0)

        # Test with different valid input
        value = "p25=500000,p50=2000000,p75=3000000,p99=10000000"
        p50, p99 = MetricModel.redis_extract_p50_and_p99_seconds(value)
        self.assertEqual(p50, 2.0)
        self.assertEqual(p99, 10.0)

        # Test with None input
        p50, p99 = MetricModel.redis_extract_p50_and_p99_seconds(None)
        self.assertEqual(p50, 0.0)
        self.assertEqual(p99, 0.0)

        # Test with empty string
        p50, p99 = MetricModel.redis_extract_p50_and_p99_seconds("")
        self.assertEqual(p50, 0.0)
        self.assertEqual(p99, 0.0)

    @patch('openc3.utilities.store.Store.info')
    @patch('openc3.utilities.store.EphemeralStore.info')
    def test_redis_metrics(self, mock_ephemeral_info, mock_store_info):
        # Mock the Store.info and EphemeralStore.info methods
        mock_store_info.return_value = {
            "connected_clients": 10,
            "used_memory_rss": 1000000,
            "total_commands_processed": 5000,
            "instantaneous_ops_per_sec": 100,
            "instantaneous_input_kbps": 50,
            "instantaneous_output_kbps": 75,
            "latency_percentiles_usec_hget": "p50=1000000,p99=5000000",
            "latency_percentiles_usec_hgetall": "p50=2000000,p99=10000000",
            "latency_percentiles_usec_hset": "p50=1500000,p99=7500000",
            "latency_percentiles_usec_xadd": "p50=500000,p99=2500000",
            "latency_percentiles_usec_xread": "p50=750000,p99=3750000",
            "latency_percentiles_usec_xrevrange": "p50=1250000,p99=6250000",
            "latency_percentiles_usec_xtrim": "p50=250000,p99=1250000",
        }

        mock_ephemeral_info.return_value = {
            "connected_clients": 5,
            "used_memory_rss": 500000,
            "total_commands_processed": 2500,
            "instantaneous_ops_per_sec": 50,
            "instantaneous_input_kbps": 25,
            "instantaneous_output_kbps": 37,
            "latency_percentiles_usec_hget": "p50=500000,p99=2500000",
            "latency_percentiles_usec_hgetall": "p50=1000000,p99=5000000",
            "latency_percentiles_usec_hset": "p50=750000,p99=3750000",
            "latency_percentiles_usec_xadd": "p50=250000,p99=1250000",
            "latency_percentiles_usec_xread": "p50=375000,p99=1875000",
            "latency_percentiles_usec_xrevrange": "p50=625000,p99=3125000",
            "latency_percentiles_usec_xtrim": "p50=125000,p99=625000",
        }

        result = MetricModel.redis_metrics()

        # Test regular Redis metrics
        self.assertEqual(result["redis_connected_clients_total"], 10)
        self.assertEqual(result["redis_used_memory_rss_total"], 1000000)
        self.assertEqual(result["redis_commands_processed_total"], 5000)
        self.assertEqual(result["redis_iops"], 100)
        self.assertEqual(result["redis_instantaneous_input_kbps"], 50)
        self.assertEqual(result["redis_instantaneous_output_kbps"], 75)
        self.assertEqual(result["redis_hget_p50_seconds"], 1.0)
        self.assertEqual(result["redis_hget_p99_seconds"], 5.0)
        self.assertEqual(result["redis_hgetall_p50_seconds"], 2.0)
        self.assertEqual(result["redis_hgetall_p99_seconds"], 10.0)
        self.assertEqual(result["redis_hset_p50_seconds"], 1.5)
        self.assertEqual(result["redis_hset_p99_seconds"], 7.5)
        self.assertEqual(result["redis_xadd_p50_seconds"], 0.5)
        self.assertEqual(result["redis_xadd_p99_seconds"], 2.5)
        self.assertEqual(result["redis_xread_p50_seconds"], 0.75)
        self.assertEqual(result["redis_xread_p99_seconds"], 3.75)
        self.assertEqual(result["redis_xrevrange_p50_seconds"], 1.25)
        self.assertEqual(result["redis_xrevrange_p99_seconds"], 6.25)
        self.assertEqual(result["redis_xtrim_p50_seconds"], 0.25)
        self.assertEqual(result["redis_xtrim_p99_seconds"], 1.25)

        # Test ephemeral Redis metrics
        self.assertEqual(result["redis_ephemeral_connected_clients_total"], 5)
        self.assertEqual(result["redis_ephemeral_used_memory_rss_total"], 500000)
        self.assertEqual(result["redis_ephemeral_commands_processed_total"], 2500)
        self.assertEqual(result["redis_ephemeral_iops"], 50)
        self.assertEqual(result["redis_ephemeral_instantaneous_input_kbps"], 25)
        self.assertEqual(result["redis_ephemeral_instantaneous_output_kbps"], 37)
        self.assertEqual(result["redis_ephemeral_hget_p50_seconds"], 0.5)
        self.assertEqual(result["redis_ephemeral_hget_p99_seconds"], 2.5)
        self.assertEqual(result["redis_ephemeral_hgetall_p50_seconds"], 1.0)
        self.assertEqual(result["redis_ephemeral_hgetall_p99_seconds"], 5.0)
        self.assertEqual(result["redis_ephemeral_hset_p50_seconds"], 0.75)
        self.assertEqual(result["redis_ephemeral_hset_p99_seconds"], 3.75)
        self.assertEqual(result["redis_ephemeral_xadd_p50_seconds"], 0.25)
        self.assertEqual(result["redis_ephemeral_xadd_p99_seconds"], 1.25)
        self.assertEqual(result["redis_ephemeral_xread_p50_seconds"], 0.375)
        self.assertEqual(result["redis_ephemeral_xread_p99_seconds"], 1.875)
        self.assertEqual(result["redis_ephemeral_xrevrange_p50_seconds"], 0.625)
        self.assertEqual(result["redis_ephemeral_xrevrange_p99_seconds"], 3.125)
        self.assertEqual(result["redis_ephemeral_xtrim_p50_seconds"], 0.125)
        self.assertEqual(result["redis_ephemeral_xtrim_p99_seconds"], 0.625)

if __name__ == '__main__':
    unittest.main()
