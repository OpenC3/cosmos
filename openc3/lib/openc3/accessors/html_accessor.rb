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

require 'openc3/accessors/xml_accessor'

module OpenC3
  class HtmlAccessor < XmlAccessor
    def self.buffer_to_doc(buffer)
      Nokogiri.HTML(buffer)
    end

    def self.doc_to_buffer(doc)
      doc.to_html
    end
  end
end
