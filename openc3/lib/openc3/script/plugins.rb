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

    def plugin_list(scope: $openc3_scope)
      response_body = nil
      begin
        endpoint = "/openc3-api/plugins?scope=#{scope}"
        uri = URI.parse($api_server.generate_url + endpoint)
        auth = $api_server.generate_auth

        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = JsonDRbObject::USER_AGENT
        request['Content-Type'] = 'application/json'
        request['Authorization'] = auth.token
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request) do |response|
            response_body = response.body
            response.value() # Raises an HTTP error if the response is not 2xx (success)
            return JSON.parse(response.body, allow_nan: true, create_additions: true)
          end
        end
      rescue => error
        raise "get_plugin_list failed due to #{error.formatted}\nResponse:\n#{response_body}"
      end
    end

    def plugin_get(plugin_name, scope: $openc3_scope)
      response_body = nil
      begin
        endpoint = "/openc3-api/plugins/#{plugin_name}?scope=#{scope}"
        uri = URI.parse($api_server.generate_url + endpoint)
        auth = $api_server.generate_auth

        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = JsonDRbObject::USER_AGENT
        request['Content-Type'] = 'application/json'
        request['Authorization'] = auth.token
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request) do |response|
            response_body = response.body
            response.value() # Raises an HTTP error if the response is not 2xx (success)
            return JSON.parse(response.body, allow_nan: true, create_additions: true)
          end
        end
      rescue => error
        raise "get_plugin failed due to #{error.formatted}\nResponse:\n#{response_body}"
      end
    end

    def plugin_install_phase1(file_path, update: false, existing_plugin_name: nil, scope: $openc3_scope)
      response_body = nil
      begin
        if update
          endpoint = "/openc3-api/plugins/#{existing_plugin_name}?scope=#{scope}"
        else
          endpoint = "/openc3-api/plugins?scope=#{scope}"
        end
        uri = URI.parse($api_server.generate_url + endpoint)
        auth = $api_server.generate_auth

        File.open(file_path, 'rb') do |file|
          if update
            request = Net::HTTP::Put.new(uri)
          else
            request = Net::HTTP::Post.new(uri)
          end
          form_data = [["plugin", file]]
          request.set_form(form_data, "multipart/form-data")
          request['User-Agent'] = JsonDRbObject::USER_AGENT
          request['Authorization'] = auth.token
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(request) do |response|
              response_body = response.body
              response.value() # Raises an HTTP error if the response is not 2xx (success)
              return JSON.parse(response.body, allow_nan: true, create_additions: true)
            end
          end
        end
      rescue => error
        raise "plugin_install_phase1 failed due to #{error.formatted}\nResponse:\n#{response_body}"
      end
    end

    def plugin_install_phase2(plugin_hash, update: false, scope: $openc3_scope)
      response_body = nil
      begin
        plugin_name = plugin_hash['name']
        if update
          endpoint = "/openc3-api/plugins/#{plugin_name}?scope=#{scope}"
        else
          endpoint = "/openc3-api/plugins/install/#{plugin_name}?scope=#{scope}"
        end
        uri = URI.parse($api_server.generate_url + endpoint)
        auth = $api_server.generate_auth

        if update
          request = Net::HTTP::Put.new(uri)
        else
          request = Net::HTTP::Post.new(uri)
        end
        form_data = [["plugin_hash", JSON.generate(plugin_hash, allow_nan: true)]]
        request.set_form(form_data)
        request['User-Agent'] = JsonDRbObject::USER_AGENT
        request['Content-Type'] = 'application/json'
        request['Authorization'] = auth.token
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request) do |response|
            response_body = response.body
            response.value() # Raises an HTTP error if the response is not 2xx (success)
            return response_body.remove_quotes
          end
        end
      rescue => error
        raise "plugin_install_phase2 failed due to #{error.formatted}\nResponse:\n#{response_body}"
      end
    end

    def plugin_update_phase1(file_path, existing_plugin_name, scope: $openc3_scope)
      return plugin_install_phase1(file_path, existing_plugin_name: existing_plugin_name, update: true, scope: scope)
    end

    def plugin_uninstall(plugin_name, scope: $openc3_scope)
      response_body = nil
      begin
        endpoint = "/openc3-api/plugins/#{plugin_name}?scope=#{scope}"
        uri = URI.parse($api_server.generate_url + endpoint)
        auth = $api_server.generate_auth
        request = Net::HTTP::Delete.new(uri)
        request['User-Agent'] = JsonDRbObject::USER_AGENT
        request['Authorization'] = auth.token
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request) do |response|
            response_body = response.body
            response.value() # Raises an HTTP error if the response is not 2xx (success)
            return response_body.remove_quotes
          end
        end
      rescue => error
        raise "plugin_uninstall failed due to #{error.formatted}\nResponse:\n#{response_body}"
      end
    end

    def plugin_status(process_name, scope: $openc3_scope)
      response_body = nil
      begin
        endpoint = "/openc3-api/process_status/#{process_name}?scope=#{scope}"
        uri = URI.parse($api_server.generate_url + endpoint)
        auth = $api_server.generate_auth

        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = JsonDRbObject::USER_AGENT
        request['Content-Type'] = 'application/json'
        request['Authorization'] = auth.token
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request) do |response|
            response_body = response.body
            response.value() # Raises an HTTP error if the response is not 2xx (success)
            return JSON.parse(response.body, allow_nan: true, create_additions: true)
          end
        end
      rescue => error
        raise "plugin_status failed due to #{error.formatted}\nResponse:\n#{response_body}"
      end
    end

  end
end
