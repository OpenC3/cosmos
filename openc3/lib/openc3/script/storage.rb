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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved

require 'tempfile'
require 'net/http'

module OpenC3
  module Script
    private

    # Delete a file on a target
    #
    # @param [String] Path to a file in a target directory
    def delete_target_file(path, scope: $openc3_scope)
      begin
        # Only delete from the targets_modified
        delete_path = "#{scope}/targets_modified/#{path}"
        endpoint = "/openc3-api/storage/delete/#{delete_path}"
        OpenC3::Logger.info "Deleting #{delete_path}"
        # Pass the name of the ENV variable name where we pull the actual bucket name
        response = $api_server.request('delete', endpoint, query: { bucket: 'OPENC3_CONFIG_BUCKET' }, scope: scope)
        if response.nil? || response.code != 200
          raise "Failed to delete #{delete_path}"
        end
      rescue => error
        raise "Failed deleting #{path} due to #{error.message}"
      end
      nil
    end

    # Get a handle to write a target file
    #
    # @param path [String] Path to a file in a target directory
    # @param io_or_string [Io or String] IO object
    def put_target_file(path, io_or_string, scope: $openc3_scope)
      raise "Disallowed path modifier '..' found in #{path}" if path.include?('..')

      upload_path = "#{scope}/targets_modified/#{path}"

      if ENV['OPENC3_LOCAL_MODE'] and $openc3_in_cluster
        OpenC3::LocalMode.put_target_file(upload_path, io_or_string, scope: scope)
        io_or_string.rewind if io_or_string.respond_to?(:rewind)
      end

      endpoint = "/openc3-api/storage/upload/#{upload_path}"
      result = _get_presigned_request(endpoint, scope: scope)
      OpenC3::Logger.info "Writing #{upload_path} at #{result['url']}"

      # Try to put the file
      begin
        uri = _get_uri(result['url'])
        Net::HTTP.start(uri.host, uri.port) do
          request = Net::HTTP::Put.new(uri, {'Content-Length' => io_or_string.length.to_s})
          if String === io_or_string
            request.body = io_or_string
          else
            request.body_stream = io_or_string
          end
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(request) do |response|
              response.value() # Raises an HTTP error if the response is not 2xx (success)
              return response
            end
          end
        end
      rescue => error
        raise "Failed to write #{upload_path} due to #{error.message}"
      end
      nil
    end

    # Get a handle to access a target file
    #
    # @param path [String] Path to a file in a target directory, e.g. "INST/procedures/test.rb"
    # @param original [Boolean] Whether to get the original or modified file
    # @return [File|nil]
    def get_target_file(path, original: false, scope: $openc3_scope)
      part = "targets"
      part += "_modified" unless original
      # Loop to allow redo when switching from modified to original
      loop do
        begin
          if part == "targets_modified" and ENV['OPENC3_LOCAL_MODE']
            local_file = OpenC3::LocalMode.open_local_file(path, scope: scope)
            if local_file
              file = Tempfile.new('target', binmode: true)
              file.write(local_file.read)
              local_file.close
              file.rewind
              return file if local_file
            end
          end

          return _get_storage_file("#{part}/#{path}", scope: scope)
        rescue => error
          if part == "targets_modified"
            part = "targets"
            redo
          else
            raise error
          end
        end
        break
      end
    end

    # These are helper methods ... should not be used directly

    def _get_storage_file(path, scope: $openc3_scope)
      # Create Tempfile to store data
      file = Tempfile.new('target', binmode: true)

      endpoint = "/openc3-api/storage/download/#{scope}/#{path}"
      result = _get_presigned_request(endpoint, scope: scope)
      OpenC3::Logger.info "Reading #{scope}/#{path} at #{result['url']}"

      # Try to get the file
      uri = _get_uri(result['url'])
      Net::HTTP.start(uri.host, uri.port) do
        request = Net::HTTP::Get.new uri
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request) do |response|
            response.value() # Raises an HTTP error if the response is not 2xx (success)
            response.read_body do |chunk|
              file.write chunk
            end
          end
        end
        file.rewind
      end
      return file
    end

    def _get_uri(url)
      if $openc3_in_cluster
        case ENV['OPENC3_CLOUD']
        when 'local'
          uri = URI.parse("http://openc3-minio:9000" + url)
        # when 'aws'
        when 'gcp'
          uri = URI.parse("https://storage.googleapis.com" + url)
        # when 'azure'
        else
          raise "Unknown cloud #{ENV['OPENC3_CLOUD']}"
        end
      else
        uri = URI.parse($api_server.generate_url + url)
      end
    end

    def _get_presigned_request(endpoint, scope: $openc3_scope)
      if $openc3_in_cluster
        response = $api_server.request('get', endpoint, query: { bucket: 'OPENC3_CONFIG_BUCKET', internal: true }, scope: scope)
      else
        response = $api_server.request('get', endpoint, query: { bucket: 'OPENC3_CONFIG_BUCKET' }, scope: scope)
      end
      if response.nil? || response.code != 201
        raise "Failed to get presigned URL for #{endpoint}"
      end
      JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end
  end
end
