# encoding: ascii-8bit

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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/model'
require 'openc3/utilities/store'

module OpenC3
  class NewsModel < Model
    PRIMARY_KEY = 'openc3_news'

    def self.set(news)
      Store.set(PRIMARY_KEY, news)
    end

    def self.all()
      Store.get(PRIMARY_KEY)
    end

    def self.news_error(response)
      Store.set(PRIMARY_KEY, [{ date: Time.now.utc.iso8601, title: 'News Error', body: "Error contacting OpenC3 news feed (status: #{response.status})" }].to_json)
    end
  end
end
