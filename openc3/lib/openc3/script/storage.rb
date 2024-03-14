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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'tempfile'
require 'net/http'

ENV['OPENC3_CLOUD'] ||= 'local'

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
        puts "Deleting #{delete_path}"
        # Pass the name of the ENV variable name where we pull the actual bucket name
        response = $api_server.request('delete', endpoint, query: { bucket: 'OPENC3_CONFIG_BUCKET' }, scope: scope)
        if response.nil? || response.status != 200
          raise "Failed to delete #{delete_path}"
        end
      rescue => e
        raise "Failed deleting #{path} due to #{e.message}"
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
      puts "Writing #{upload_path}"

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
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.request(request) do |response|
              response.value() # Raises an HTTP error if the response is not 2xx (success)
              return response
            end
          end
        end
      rescue => e
        raise "Failed to write #{upload_path} due to #{e.message}"
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
              puts "Reading local #{scope}/#{part}/#{path}"
              file = Tempfile.new('target', binmode: true)
              file.filename = path
              file.write(local_file.read)
              local_file.close
              file.rewind
              return file
            end
          end

          return _get_storage_file("#{part}/#{path}", scope: scope)
        rescue => e
          if part == "targets_modified"
            part = "targets"
            redo
          else
            raise e
          end
        end
        break
      end
    end

    def get_download_url(path, scope: $openc3_scope)
      targets = "targets_modified" # First try targets_modified
      response = $api_server.request('get', "/openc3-api/storage/exists/#{scope}/#{targets}/#{path}", query: { bucket: 'OPENC3_CONFIG_BUCKET' }, scope: scope)
      if response.status != 200
        targets = "targets" # Next try targets
        response = $api_server.request('get', "/openc3-api/storage/exists/#{scope}/#{targets}/#{path}", query: { bucket: 'OPENC3_CONFIG_BUCKET' }, scope: scope)
        if response.status != 200
          raise "File not found: #{path} in scope: #{scope}"
        end
      end
      endpoint = "/openc3-api/storage/download/#{scope}/#{targets}/#{path}"
      # external must be true because we're using this URL from the frontend
      result = _get_presigned_request(endpoint, external: true, scope: scope)
      return result['url']
    end

    # These are helper methods ... should not be used directly

    def _get_storage_file(path, scope: $openc3_scope)
      # Create Tempfile to store data
      file = Tempfile.new('target', binmode: true)
      file.filename = path

      endpoint = "/openc3-api/storage/download/#{scope}/#{path}"
      result = _get_presigned_request(endpoint, scope: scope)
      puts "Reading #{scope}/#{path}"

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
          bucket_url = ENV["OPENC3_BUCKET_URL"] || "openc3-minio:9000"
          # TODO: Bucket schema for http vs https
          URI.parse("http://#{bucket_url}#{url}")
        when 'aws'
          URI.parse("https://s3.#{ENV['AWS_REGION']}.amazonaws.com" + url)
        when 'gcp'
          URI.parse("https://storage.googleapis.com" + url)
        # when 'azure'
        else
          raise "Unknown cloud #{ENV['OPENC3_CLOUD']}"
        end
      else
        URI.parse($api_server.generate_url + url)
      end
    end

    def _get_presigned_request(endpoint, external: nil, scope: $openc3_scope)
      if external or !$openc3_in_cluster
        response = $api_server.request('get', endpoint, query: { bucket: 'OPENC3_CONFIG_BUCKET' }, scope: scope)
      else
        response = $api_server.request('get', endpoint, query: { bucket: 'OPENC3_CONFIG_BUCKET', internal: true }, scope: scope)
      end
      if response.nil? || response.status != 201
        raise "Failed to get presigned URL for #{endpoint}"
      end
      JSON.parse(response.body, :allow_nan => true, :create_additions => true)
    end
  end
end
