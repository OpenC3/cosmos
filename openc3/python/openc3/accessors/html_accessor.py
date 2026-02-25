# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

# XmlAccessor uses lxml.etree
import lxml.html as HTML  # noqa: N812

from openc3.accessors.xml_accessor import XmlAccessor


class HtmlAccessor(XmlAccessor):
    @classmethod
    def _buffer_to_doc(cls, buffer):
        # Override the XML implementation to use the HTML parser
        return HTML.fromstring(bytes(buffer))

    @classmethod
    def _doc_to_buffer(cls, doc):
        return bytearray(HTML.tostring(doc))
