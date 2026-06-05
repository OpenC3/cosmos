# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# This file sets up using the OpenC3 framework

# Improve DNS (especially on Alpine)
require 'resolv-replace'

# Set default encodings
saved_verbose = $VERBOSE; $VERBOSE = nil
Encoding.default_external = Encoding::ASCII_8BIT
# NOTE: Do NOT set Encoding.default_internal = ASCII_8BIT. Doing so makes every
# read that specifies an encoding (e.g. File.read(path, encoding: 'UTF-8'))
# transcode into ASCII-8BIT, which raises Encoding::UndefinedConversionError on
# any non-ASCII byte. On Ruby 3.4 this breaks bootsnap's compile cache (it reads
# source as UTF-8 to work around Ruby bug #22023) for any file containing
# non-ASCII characters, including stdlib files like 'matrix'. Leave it nil.
$VERBOSE = saved_verbose

# Add OpenC3 bin folder to PATH
require 'openc3/core_ext/kernel'
if Kernel.is_windows?
  ENV['PATH'] = File.join(File.dirname(__FILE__), '../bin') + ';' + ENV['PATH']
else
  ENV['PATH'] = File.join(File.dirname(__FILE__), '../bin') + ':' + ENV['PATH']
end
require 'openc3/ext/platform' if RUBY_ENGINE == 'ruby' and !ENV['OPENC3_NO_EXT']
require 'openc3/version'
require 'openc3/top_level'
require 'openc3/core_ext'
require 'openc3/utilities'
require 'openc3/accessors'
require 'openc3/conversions'
require 'openc3/interfaces'
require 'openc3/processors'
require 'openc3/packets/packet'
require 'openc3/logs'
require 'openc3/system'

# OpenC3 services need to die if something goes wrong so they can be restarted
require 'thread'
Thread.abort_on_exception = true
Thread.report_on_exception = true
