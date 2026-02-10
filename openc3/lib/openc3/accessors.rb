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

module OpenC3
  autoload(:Accessor, 'openc3/accessors/accessor.rb')
  autoload(:BinaryAccessor, 'openc3/accessors/binary_accessor.rb')
  autoload(:CborAccessor, 'openc3/accessors/cbor_accessor.rb')
  autoload(:FormAccessor, 'openc3/accessors/form_accessor.rb')
  autoload(:HtmlAccessor, 'openc3/accessors/html_accessor.rb')
  autoload(:HttpAccessor, 'openc3/accessors/http_accessor.rb')
  autoload(:JsonAccessor, 'openc3/accessors/json_accessor.rb')
  autoload(:XmlAccessor, 'openc3/accessors/xml_accessor.rb')
  autoload(:TemplateAccessor, 'openc3/accessors/template_accessor.rb')
end
