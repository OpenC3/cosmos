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

require 'openc3/script/plugins'

module OpenC3
  module Script
    private

    def package_list(scope: $openc3_scope)
      response_body = nil
      begin
        endpoint = "/openc3-api/packages?scope=#{scope}"
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
        raise "package_list failed due to #{error.formatted}\nResponse:\n#{response_body}"
      end
    end

    def package_install(file_path, scope: $openc3_scope)
      response_body = nil
      begin
        endpoint = "/openc3-api/packages?scope=#{scope}"
        uri = URI.parse($api_server.generate_url + endpoint)
        auth = $api_server.generate_auth

        File.open(file_path, 'rb') do |file|
          request = Net::HTTP::Post.new(uri)
          form_data = [["package", file]]
          request.set_form(form_data, "multipart/form-data")
          request['User-Agent'] = JsonDRbObject::USER_AGENT
          request['Authorization'] = auth.token
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(request) do |response|
              response_body = response.body
              response.value() # Raises an HTTP error if the response is not 2xx (success)
              return response_body.remove_quotes
            end
          end
        end
      rescue => error
        raise "package_install failed due to #{error.formatted}\nResponse:\n#{response_body}"
      end
    end

    def package_uninstall(package_name, scope: $openc3_scope)
      response_body = nil
      begin
        endpoint = "/openc3-api/packages/#{package_name}?scope=#{scope}"
        uri = URI.parse($api_server.generate_url + endpoint)
        auth = $api_server.generate_auth
        request = Net::HTTP::Delete.new(uri)
        request['User-Agent'] = JsonDRbObject::USER_AGENT
        request['Authorization'] = auth.token
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request) do |response|
            response_body = response.body
            response.value() # Raises an HTTP error if the response is not 2xx (success)
            return true
          end
        end
      rescue => error
        raise "package_uninstall failed due to #{error.formatted}\nResponse:\n#{response_body}"
      end
    end

    def package_status(process_name, scope: $openc3_scope)
      return plugin_status(process_name, scope: scope)
    end

    def package_download(package_name, local_file_path, scope: $openc3_scope)
      response_body = nil
      begin
        endpoint = "/openc3-api/packages/#{package_name}/download?scope=#{scope}"
        uri = URI.parse($api_server.generate_url + endpoint)
        auth = $api_server.generate_auth
        request = Net::HTTP::Post.new(uri)
        request['User-Agent'] = JsonDRbObject::USER_AGENT
        request['Authorization'] = auth.token
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request) do |response|
            response_body = response.body
            response.value() # Raises an HTTP error if the response is not 2xx (success)
            parsed = JSON.parse(response.body, allow_nan: true, create_additions: true)
            File.open(local_file_path, 'wb') do |file|
              file.write(Base64.decode64(parsed['contents']))
            end
            return local_file_path
          end
        end
      rescue => error
        raise "package_uninstall failed due to #{error.formatted}\nResponse:\n#{response_body}"
      end
    end

  end
end
