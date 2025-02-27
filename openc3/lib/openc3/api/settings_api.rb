# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

begin
  require 'openc3-enterprise/version'
  VERSION = OPENC3_ENTERPRISE_VERSION
  ENTERPRISE = true
rescue LoadError
  require 'openc3/version'
  VERSION = OPENC3_VERSION
  ENTERPRISE = false
end
require 'openc3/models/setting_model'
require 'openc3/models/news_model'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
                       'list_settings',
                       'get_all_settings',
                       'get_setting',
                       'get_settings',
                       'set_setting',
                       'save_setting', # DEPRECATED
                       'update_news',
                     ])

    def list_settings(manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      SettingModel.names(scope: scope)
    end

    def get_all_settings(manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      SettingModel.all(scope: scope)
    end

    def get_setting(name, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      setting = SettingModel.get(name: name, scope: scope)
      if setting
        setting['data']
      else
        nil
      end
    end

    def get_settings(*settings, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      result = []
      settings.each { |name| result << get_setting(name, scope: scope, token: token) }
      result
    end

    def set_setting(name, data, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'admin', manual: manual, scope: scope, token: token)
      SettingModel.set({ name: name, data: data }, scope: scope)
      LocalMode.save_setting(scope, name, data)
    end
    # save_setting is DEPRECATED
    alias save_setting set_setting

    # Update the news feed on demand to respond to frontend setting changes
    def update_news(manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'admin', manual: manual, scope: scope, token: token)
      conn = Faraday.new(
        url: 'https://news.openc3.com',
        params: {version: VERSION, enterprise: ENTERPRISE},
      )
      response = conn.get('/news')
      if response.success?
        NewsModel.set(response.body)
      else
        NewsModel.news_error("Error contacting OpenC3 news feed (status: #{response.status})")
      end

      # Test code to update the news feed with a dummy message
      # data = NewsModel.all()
      # json = JSON.parse(data)
      # json.unshift( { date: Time.now.utc.iso8601, title: "News at #{Time.now}", body: "The news feed has been updated at #{Time.now}." })
      # json.pop if json.length > 5
      # NewsModel.set(json.to_json)
    rescue Exception => e
      NewsModel.news_error("Error contacting OpenC3 news feed. #{e.message})")
    end
  end
end
