
import unittest
from unittest.mock import patch, MagicMock
import json
import time
from openc3.models.target_model import TargetModel

'''
This test suite covers the following scenarios for the `get_item_to_packet_map` method:

1. When the map is in the cache and not expired.
2. When the map is in the cache but expired.
3. When the map is not in the cache but is in the store.
4. When the map is neither in the cache nor in the store.
5. Testing with a custom scope.

These tests use mocking to isolate the method and avoid actual calls to the database or file system. They cover all the main paths through the method, including caching behavior, store interactions, and the fallback to building the map when it's not found.

To run these tests, you would need to have the `openc3` package installed and the `TargetModel` class available. You may need to adjust import paths based on your project structure.
'''

class TestTargetModelGetItemToPacketMap(unittest.TestCase):

    @patch('openc3.models.target_model.Store')
    @patch('openc3.models.target_model.TargetModel.build_item_to_packet_map')
    def test_get_item_to_packet_map_cached(self, mock_build, mock_store):
        # Test when the map is in the cache and not expired
        TargetModel.item_map_cache = {
            'TARGET': [time.time(), {'ITEM1': ['PACKET1'], 'ITEM2': ['PACKET2']}]
        }
        result = TargetModel.get_item_to_packet_map('TARGET')
        self.assertEqual(result, {'ITEM1': ['PACKET1'], 'ITEM2': ['PACKET2']})
        mock_store.get.assert_not_called()
        mock_build.assert_not_called()

    @patch('openc3.models.target_model.Store')
    @patch('openc3.models.target_model.TargetModel.build_item_to_packet_map')
    def test_get_item_to_packet_map_cached_expired(self, mock_build, mock_store):
        # Test when the map is in the cache but expired
        TargetModel.item_map_cache = {
            'TARGET': [time.time() - TargetModel.ITEM_MAP_CACHE_TIMEOUT - 1, {'OLD': ['DATA']}]
        }
        mock_store.get.return_value = json.dumps({'ITEM1': ['PACKET1'], 'ITEM2': ['PACKET2']})
        result = TargetModel.get_item_to_packet_map('TARGET')
        self.assertEqual(result, {'ITEM1': ['PACKET1'], 'ITEM2': ['PACKET2']})
        mock_store.get.assert_called_once_with('__TARGET__item_to_packet_map')
        mock_build.assert_not_called()

    @patch('openc3.models.target_model.Store')
    @patch('openc3.models.target_model.TargetModel.build_item_to_packet_map')
    def test_get_item_to_packet_map_not_cached_in_store(self, mock_build, mock_store):
        # Test when the map is not in the cache but is in the store
        TargetModel.item_map_cache = {}
        mock_store.get.return_value = json.dumps({'ITEM1': ['PACKET1'], 'ITEM2': ['PACKET2']})
        result = TargetModel.get_item_to_packet_map('TARGET')
        self.assertEqual(result, {'ITEM1': ['PACKET1'], 'ITEM2': ['PACKET2']})
        mock_store.get.assert_called_once_with('__TARGET__item_to_packet_map')
        mock_build.assert_not_called()

    @patch('openc3.models.target_model.Store')
    @patch('openc3.models.target_model.TargetModel.build_item_to_packet_map')
    def test_get_item_to_packet_map_not_cached_not_in_store(self, mock_build, mock_store):
        # Test when the map is neither in the cache nor in the store
        TargetModel.item_map_cache = {}
        mock_store.get.return_value = None
        mock_build.return_value = {'ITEM1': ['PACKET1'], 'ITEM2': ['PACKET2']}
        result = TargetModel.get_item_to_packet_map('TARGET')
        self.assertEqual(result, {'ITEM1': ['PACKET1'], 'ITEM2': ['PACKET2']})
        mock_store.get.assert_called_once_with('__TARGET__item_to_packet_map')
        mock_build.assert_called_once_with('TARGET', scope='DEFAULT')
        mock_store.set.assert_called_once_with('__TARGET__item_to_packet_map', json.dumps(mock_build.return_value))

    @patch('openc3.models.target_model.Store')
    @patch('openc3.models.target_model.TargetModel.build_item_to_packet_map')
    def test_get_item_to_packet_map_custom_scope(self, mock_build, mock_store):
        # Test with a custom scope
        TargetModel.item_map_cache = {}
        mock_store.get.return_value = None
        mock_build.return_value = {'ITEM1': ['PACKET1'], 'ITEM2': ['PACKET2']}
        result = TargetModel.get_item_to_packet_map('TARGET', scope='CUSTOM')
        self.assertEqual(result, {'ITEM1': ['PACKET1'], 'ITEM2': ['PACKET2']})
        mock_store.get.assert_called_once_with('CUSTOM__TARGET__item_to_packet_map')
        mock_build.assert_called_once_with('TARGET', scope='CUSTOM')
        mock_store.set.assert_called_once_with('CUSTOM__TARGET__item_to_packet_map', json.dumps(mock_build.return_value))

if __name__ == '__main__':
    unittest.main()
