# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import shutil
import tempfile
import unittest
import time
import gzip
import threading
from unittest.mock import patch, MagicMock
from openc3.interfaces.interface import Interface
from openc3.interfaces.file_interface import FileInterface
from openc3.packets.packet import Packet


class TestFileInterface(unittest.TestCase):
    def setUp(self):
        self.interface = None
        self.temp_dir = tempfile.mkdtemp()
        self.telemetry_dir = os.path.join(self.temp_dir, 'telemetry')
        self.command_dir = os.path.join(self.temp_dir, 'command')
        self.archive_dir = os.path.join(self.temp_dir, 'archive')
        os.makedirs(self.telemetry_dir)
        os.makedirs(self.command_dir)
        os.makedirs(self.archive_dir)

    def tearDown(self):
        if self.interface:
            self.interface.disconnect()
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def test_initialize(self):
        """Test initializes the instance variables"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.assertEqual(self.interface.command_write_folder, self.command_dir)
        self.assertEqual(self.interface.telemetry_read_folder, self.telemetry_dir)
        self.assertEqual(self.interface.telemetry_archive_folder, self.archive_dir)
        self.assertEqual(self.interface.file_read_size, 65536)
        self.assertTrue(self.interface.stored)
        self.assertEqual(self.interface.extension, ".bin")
        self.assertEqual(self.interface.label, "command")
        self.assertFalse(self.interface.polling)
        self.assertFalse(self.interface.recursive)

    def test_initialize_with_nil_folders(self):
        """Test handles nil folders appropriately"""
        self.interface = FileInterface(None, None, None)
        self.assertIsNone(self.interface.command_write_folder)
        self.assertIsNone(self.interface.telemetry_read_folder)
        self.assertIsNone(self.interface.telemetry_archive_folder)
        self.assertFalse(self.interface.read_allowed)
        self.assertFalse(self.interface.write_allowed)
        self.assertFalse(self.interface.write_raw_allowed)

    def test_initialize_with_protocol(self):
        """Test initializes with a protocol"""
        protocol_type = "Preidentified"
        protocol_args = [None, 100]
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir, 65536, True, protocol_type, protocol_args)
        self.assertEqual(len(self.interface.read_protocols), 1)
        self.assertEqual(len(self.interface.write_protocols), 1)

    def test_connect(self):
        """Test connects and sets up the listener"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.assertFalse(self.interface.connected())
        self.interface.connect()
        self.assertTrue(self.interface.connected())
        self.assertIsNotNone(self.interface.listener)

    def test_connect_no_telemetry_folder(self):
        """Test doesn't setup the listener if no telemetry folder"""
        self.interface = FileInterface(self.command_dir, None, None)
        self.interface.connect()
        self.assertTrue(self.interface.connected())
        self.assertIsNone(self.interface.listener)

    def test_disconnect(self):
        """Test closes the file if open"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        mock_file = MagicMock()
        mock_file.closed = False
        self.interface.file = mock_file
        self.interface.disconnect()
        mock_file.close.assert_called_once()
        self.assertIsNone(self.interface.file)

    def test_read_interface_no_files(self):
        """Test returns None if no telemetry files available"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.connect()

        # Mock get_next_telemetry_file to return None
        with patch.object(self.interface, 'get_next_telemetry_file', return_value=None):
            # Empty the queue and put None to ensure queue.get returns immediately
            while not self.interface.queue.empty():
                self.interface.queue.get()
            self.interface.queue.put(None)

            data, extra = self.interface.read_interface()
            self.assertIsNone(data)
            self.assertIsNone(extra)

    def test_read_interface(self):
        """Test reads data from a telemetry file"""
        filename = os.path.join(self.telemetry_dir, 'test.bin')
        with open(filename, 'wb') as file:
            file.write(b'\x01\x02\x03\x04')

        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.connect()

        data, _ = self.interface.read_interface()
        self.assertEqual(data, b'\x01\x02\x03\x04')

        # Put None so next call doesn't block
        self.interface.queue.put(None)
        data, _ = self.interface.read_interface()

        # Verify the file was archived
        self.assertTrue(os.path.exists(os.path.join(self.archive_dir, 'test.bin')))
        self.assertFalse(os.path.exists(filename))

    def test_read_interface_gzip(self):
        """Test reads data from a gzipped telemetry file"""
        filename = os.path.join(self.telemetry_dir, 'test.bin.gz')
        with gzip.open(filename, 'wb') as gz:
            gz.write(b'\x01\x02\x03\x04')

        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.connect()

        data, _ = self.interface.read_interface()
        self.assertEqual(data, b'\x01\x02\x03\x04')

    def test_read_interface_delete(self):
        """Test deletes the file if archive folder is DELETE"""
        filename = os.path.join(self.telemetry_dir, 'test.bin')
        with open(filename, 'wb') as file:
            file.write(b'\x01\x02\x03\x04')

        self.interface = FileInterface(self.command_dir, self.telemetry_dir, "DELETE")
        self.interface.connect()

        data, _ = self.interface.read_interface()
        self.assertEqual(data, b'\x01\x02\x03\x04')

        # Put None so next call doesn't block
        self.interface.queue.put(None)
        data, _ = self.interface.read_interface()

        self.assertFalse(os.path.exists(filename))

    def test_read_interface_file_read_size(self):
        """Test respects file_read_size"""
        filename = os.path.join(self.telemetry_dir, 'test.bin')
        with open(filename, 'wb') as file:
            file.write(b'\x01\x02\x03\x04\x05\x06\x07\x08')

        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir, 4)
        self.interface.connect()

        data, extra = self.interface.read_interface()
        self.assertEqual(data, b'\x01\x02\x03\x04')

        data, extra = self.interface.read_interface()
        self.assertEqual(data, b'\x05\x06\x07\x08')

        # Mock get_next_telemetry_file to return None
        with patch.object(self.interface, 'get_next_telemetry_file', return_value=None):
            # Empty the queue and put None
            while not self.interface.queue.empty():
                self.interface.queue.get()
            self.interface.queue.put(None)

            data, extra = self.interface.read_interface()
            self.assertIsNone(data)
            self.assertIsNone(extra)

    def test_read_interface_throttle(self):
        """Test respects throttle option"""
        filename1 = os.path.join(self.telemetry_dir, 'test1.bin')
        with open(filename1, 'wb') as file:
            file.write(b'\x01\x02\x03\x04')

        filename2 = os.path.join(self.telemetry_dir, 'test2.bin')
        with open(filename2, 'wb') as file:
            file.write(b'\x05\x06\x07\x08')

        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.set_option('THROTTLE', ['0.2'])
        self.interface.connect()

        start = time.time()
        data, _ = self.interface.read_interface()
        self.assertEqual(data, b'\x01\x02\x03\x04')

        data, _ = self.interface.read_interface()
        self.assertEqual(data, b'\x05\x06\x07\x08')

        elapsed = time.time() - start
        self.assertGreater(elapsed, 0.2)
        self.assertLess(elapsed, 1.0)

    def test_read_interface_queue_notification(self):
        """Test responds to file notifications via the queue"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.connect()

        def create_file():
            time.sleep(0.1)
            filename = os.path.join(self.telemetry_dir, 'test.bin')
            with open(filename, 'wb') as file:
                file.write(b'\x01\x02\x03\x04')
            self.interface.queue.put(filename)

        thread = threading.Thread(target=create_file)
        thread.start()

        data, _ = self.interface.read_interface()
        self.assertEqual(data, b'\x01\x02\x03\x04')
        thread.join()

    def test_write_interface(self):
        """Test writes data to a command file"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.connect()

        data = b'\x01\x02\x03\x04'
        result, extra = self.interface.write_interface(data)
        self.assertEqual(result, data)
        self.assertIsNone(extra)

        # Verify a file was created
        files = [f for f in os.listdir(self.command_dir) if os.path.isfile(os.path.join(self.command_dir, f))]
        self.assertEqual(len(files), 1)

        with open(os.path.join(self.command_dir, files[0]), 'rb') as f:
            file_data = f.read()
        self.assertEqual(file_data, data)

    def test_set_option_label(self):
        """Test handles LABEL option"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.set_option('LABEL', ['new_label'])
        self.assertEqual(self.interface.label, 'new_label')

    def test_set_option_extension(self):
        """Test handles EXTENSION option"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.set_option('EXTENSION', ['.txt'])
        self.assertEqual(self.interface.extension, '.txt')

    def test_set_option_polling(self):
        """Test handles POLLING option"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.set_option('POLLING', ['TRUE'])
        self.assertTrue(self.interface.polling)

    def test_set_option_recursive(self):
        """Test handles RECURSIVE option"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.set_option('RECURSIVE', ['TRUE'])
        self.assertTrue(self.interface.recursive)

    def test_set_option_throttle(self):
        """Test handles THROTTLE option"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.set_option('THROTTLE', ['100'])
        self.assertEqual(self.interface.throttle, 100)
        self.assertIsNotNone(self.interface.sleeper)

    def test_finish_file(self):
        """Test closes and archives the file"""
        filename = os.path.join(self.telemetry_dir, 'test.bin')
        with open(filename, 'wb') as file:
            file.write(b'\x01\x02\x03\x04')

        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.connect()

        file = open(filename, 'rb')
        self.interface.file = file
        self.interface.file_path = filename
        self.interface.finish_file()

        self.assertIsNone(self.interface.file)
        self.assertFalse(os.path.exists(filename))
        self.assertTrue(os.path.exists(os.path.join(self.archive_dir, 'test.bin')))

    def test_finish_file_delete(self):
        """Test deletes the file if archive folder is DELETE"""
        filename = os.path.join(self.telemetry_dir, 'test.bin')
        with open(filename, 'wb') as file:
            file.write(b'\x01\x02\x03\x04')

        self.interface = FileInterface(self.command_dir, self.telemetry_dir, "DELETE")
        self.interface.connect()

        file = open(filename, 'rb')
        self.interface.file = file
        self.interface.file_path = filename
        self.interface.finish_file()

        self.assertIsNone(self.interface.file)
        self.assertFalse(os.path.exists(filename))

    def test_get_next_telemetry_file(self):
        """Test returns the first file in the telemetry directory"""
        filename1 = os.path.join(self.telemetry_dir, 'test1.bin')
        with open(filename1, 'wb') as file:
            file.write(b'\x01\x02\x03\x04')

        time.sleep(0.1)  # Ensure file timestamps are different

        filename2 = os.path.join(self.telemetry_dir, 'test2.bin')
        with open(filename2, 'wb') as file:
            file.write(b'\x05\x06\x07\x08')

        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        result = self.interface.get_next_telemetry_file()
        self.assertEqual(result, filename1)

    def test_get_next_telemetry_file_no_files(self):
        """Test returns nil if no files exist"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        result = self.interface.get_next_telemetry_file()
        self.assertIsNone(result)

    def test_get_next_telemetry_file_recursive(self):
        """Test finds files recursively if recursive option set"""
        subdir = os.path.join(self.telemetry_dir, 'subdir')
        os.makedirs(subdir)
        filename = os.path.join(subdir, 'test.bin')
        with open(filename, 'wb') as file:
            file.write(b'\x01\x02\x03\x04')

        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.set_option('RECURSIVE', ['TRUE'])
        result = self.interface.get_next_telemetry_file()
        self.assertEqual(result, filename)

    def test_create_unique_filename(self):
        """Test creates a unique filename"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        filename = self.interface.create_unique_filename()
        self.assertIn(self.command_dir, filename)
        self.assertIn('command', filename)
        self.assertIn('.bin', filename)
        self.assertFalse(os.path.exists(filename))

    def test_create_unique_filename_existing(self):
        """Test handles existing files by adding a counter"""
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)

        # Mock isfile to make it think the file exists once then doesn't
        with patch('os.path.isfile', side_effect=[True, False]):
            filename = self.interface.create_unique_filename()
            self.assertIn('command_1', filename)

    def test_convert_data_to_packet(self):
        """Test sets the stored flag if configured"""
        # Test with stored=True
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir, 65536, True)
        packet = Packet("TGT", "PKT")

        with patch.object(Interface, 'convert_data_to_packet', return_value=packet):
            result = self.interface.convert_data_to_packet(b'\x01\x02\x03\x04')
            self.assertTrue(result.stored)

        # Test with stored=False
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir, 65536, False)
        packet = Packet("TGT", "PKT")

        with patch.object(Interface, 'convert_data_to_packet', return_value=packet):
            result = self.interface.convert_data_to_packet(b'\x01\x02\x03\x04')
            self.assertFalse(result.stored)

    def test_details(self):
        """Test returns correct interface details"""
        self.interface = FileInterface("/cmd", "/tlm", "/archive", 32768, True)
        self.interface.set_option('LABEL', ['test_label'])
        self.interface.set_option('EXTENSION', ['.dat'])
        self.interface.set_option('POLLING', ['TRUE'])
        self.interface.set_option('RECURSIVE', ['TRUE'])
        self.interface.set_option('THROTTLE', ['100'])
        details = self.interface.details()
        
        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)
        
        # Check that it includes the expected keys specific to FileInterface
        self.assertIn('command_write_folder', details)
        self.assertIn('telemetry_read_folder', details)
        self.assertIn('telemetry_archive_folder', details)
        self.assertIn('file_read_size', details)
        self.assertIn('stored', details)
        self.assertIn('filename', details)
        self.assertIn('extension', details)
        self.assertIn('label', details)
        self.assertIn('queue_length', details)
        self.assertIn('polling', details)
        self.assertIn('recursive', details)
        self.assertIn('throttle', details)
        self.assertIn('discard_file_header_bytes', details)
        
        # Verify the specific values are correct
        self.assertEqual(details['command_write_folder'], "/cmd")
        self.assertEqual(details['telemetry_read_folder'], "/tlm")
        self.assertEqual(details['telemetry_archive_folder'], "/archive")
        self.assertEqual(details['file_read_size'], 32768)
        self.assertTrue(details['stored'])
        self.assertEqual(details['filename'], '')  # No file currently open
        self.assertEqual(details['extension'], '.dat')
        self.assertEqual(details['label'], 'test_label')
        self.assertEqual(details['queue_length'], 0)  # Empty queue
        self.assertTrue(details['polling'])
        self.assertTrue(details['recursive'])
        self.assertEqual(details['throttle'], 100)
        self.assertIsNone(details['discard_file_header_bytes'])

    def test_details_with_none_folders(self):
        """Test details with None folder values"""
        self.interface = FileInterface(None, None, None)
        details = self.interface.details()
        
        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)
        
        # Check None values are preserved
        self.assertIsNone(details['command_write_folder'])
        self.assertIsNone(details['telemetry_read_folder'])
        self.assertIsNone(details['telemetry_archive_folder'])
        self.assertEqual(details['file_read_size'], 65536)  # default value
        self.assertTrue(details['stored'])  # default value

    def test_details_with_current_file(self):
        """Test details includes current file path when file is open"""
        filename = os.path.join(self.telemetry_dir, 'test.bin')
        with open(filename, 'wb') as file:
            file.write(b'\x01\x02\x03\x04')
            
        self.interface = FileInterface(self.command_dir, self.telemetry_dir, self.archive_dir)
        self.interface.file_path = filename
        details = self.interface.details()
        
        # Verify the filename is included
        self.assertEqual(details['filename'], filename)


if __name__ == '__main__':
    unittest.main()