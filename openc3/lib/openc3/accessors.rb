# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

module OpenC3
  autoload(:Accessor, 'openc3/accessors/accessor.rb')
  autoload(:BinaryAccessor, 'openc3/accessors/binary_accessor.rb')
  autoload(:CborAccessor, 'openc3/accessors/cbor_accessor.rb')
  autoload(:HtmlAccessor, 'openc3/accessors/html_accessor.rb')
  autoload(:JsonAccessor, 'openc3/accessors/json_accessor.rb')
  autoload(:XmlAccessor, 'openc3/accessors/xml_accessor.rb')
end
