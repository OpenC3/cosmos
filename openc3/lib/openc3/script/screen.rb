# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

module OpenC3
  module Script
    private

    def get_screen_list(scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/screens"
        # Pass the name of the ENV variable name where we pull the actual bucket name
        response = $api_server.request('get', endpoint, scope: scope)
        if response.nil? || response.status != 200
          raise "Unexpected response to get_screen_list: #{response.inspect}"
        end
        screen_list = {}
        filenames = JSON.parse(response.body)
        filenames.each do |filename|
          # TARGET/screens/filename.txt
          split_filename = filename.split('/')
          target_name = split_filename[0]
          screen_name = File.basename(filename, '.txt').to_s.upcase
          screen_list[target_name] ||= []
          screen_list[target_name] << screen_name
        end
        return screen_list
      rescue => error
        raise "get_screen_list failed due to #{error.formatted}"
      end
    end

    def get_screen_definition(target_name, screen_name, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/screen/#{target_name.upcase}/#{screen_name.upcase}"
        response = $api_server.request('get', endpoint, headers: {
          Accept: 'text/plain',
        }, scope: scope)
        if response.nil? || response.status != 200
          raise "Screen definition not found: #{target_name} #{screen_name}"
        end
        return response.body
      rescue => error
        raise "get_screen_definition failed due to #{error.formatted}"
      end
    end

    def create_screen(target_name, screen_name, definition, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/screen"
        data = {
          "target" => target_name,
          "screen" => screen_name,
          "text" => definition
        }
        response = $api_server.request('post', endpoint, :data => data, :json => true, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response)
            raise "create_screen error: #{parsed['error']}"
          else
            raise "create_screen failed"
          end
        end
        return response.body
      rescue => error
        raise "create_screen failed due to #{error.formatted}"
      end
    end

    def delete_screen(target_name, screen_name, scope: $openc3_scope)
      begin
        endpoint = "/openc3-api/screen/#{target_name.upcase}/#{screen_name.upcase}"
        response = $api_server.request('delete', endpoint, scope: scope)
        if response.nil? || response.status != 200
          if response
            parsed = JSON.parse(response)
            raise "delete_screen error: #{parsed['error']}"
          else
            raise "delete_screen failed"
          end
        end
        return response.body
      rescue => error
        raise "delete_screen failed due to #{error.formatted}"
      end
    end

    def display_screen(target_name, screen_name, x = nil, y = nil, scope: $openc3_scope)
      # Noop outside of ScriptRunner
    end

    def clear_screen(target_name, screen_name)
      # Noop outside of ScriptRunner
    end

    def clear_all_screens
      # Noop outside of ScriptRunner
    end

    def local_screen(screen_name, definition, x = nil, y = nil)
      # Noop outside of ScriptRunner
    end
  end
end
