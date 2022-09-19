# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

require 'fileutils'
require 'json'
require 'openc3/utilities/local_mode'
require 'openc3/utilities/s3'

module OpenC3
  class TargetFile

    DEFAULT_BUCKET_NAME = 'config'

    def self.all(scope, path_matchers)
      result = []
      modified = []

      rubys3_client = Aws::S3::Client.new
      token = nil
      while true
        resp = rubys3_client.list_objects_v2({
          bucket: DEFAULT_BUCKET_NAME,
          prefix: "#{scope}/targets",
          max_keys: 1000,
          continuation_token: token
        })

        resp.contents.each do |object|
          split_key = object.key.split('/')
          found = false
          path_matchers.each do |path|
            if split_key.include?(path)
              found = true
              break
            end
          end
          next unless found
          result_no_scope_or_target_folder = split_key[2..-1].join('/')
          if object.key.include?("#{scope}/targets_modified")
            modified << result_no_scope_or_target_folder
          else
            result << result_no_scope_or_target_folder
          end
        end
        break unless resp.is_truncated
        token = resp.next_continuation_token
      end

      # Add in local targets_modified if present
      if ENV['OPENC3_LOCAL_MODE']
        local_modified = OpenC3::LocalMode.local_target_files(scope: scope, path_matchers: path_matchers)
        local_modified.each do |filename|
          modified << filename unless modified.include?(filename)
          result << filename unless result.include?(filename)
        end
      end

      # Determine if there are any modified files and mark them with '*'
      result.map! do |file|
        if modified.include?(file)
          modified.delete(file)
          "#{file}*"
        else
          file
        end
      end

      # Concat any remaining modified files (new files not in original target)
      result.concat(modified)
      result.sort
    end

    def self.temp(scope)
      result = []
      rubys3_client = Aws::S3::Client.new
      token = nil
      while true
        resp = rubys3_client.list_objects_v2({
          bucket: DEFAULT_BUCKET_NAME,
          prefix: "#{scope}/targets_modified",
          max_keys: 1000,
          continuation_token: token
        })

        resp.contents.each do |object|
          split_key = object.key.split('/')
          if split_key[-1].include?('_temp')
            result << split_key[-1]
          end
        end
        break unless resp.is_truncated
        token = resp.next_continuation_token
      end
      result.sort
    end

    def self.delete_temp(scope)
      rubys3_client = Aws::S3::Client.new
      token = nil
      while true
        resp = rubys3_client.list_objects_v2({
          bucket: DEFAULT_BUCKET_NAME,
          prefix: "#{scope}/targets_modified",
          max_keys: 1000,
          continuation_token: token
        })

        resp.contents.each do |object|
          if object.key.split('/')[-1].include?('_temp')
            rubys3_client.delete_object(
              bucket: DEFAULT_BUCKET_NAME,
              key: object.key,
            )
            if ENV['OPENC3_LOCAL_MODE']
              puts "delete_local:#{object.key}"
              OpenC3::LocalMode.delete_local(object.key)
            end
          end
        end
        break unless resp.is_truncated
        token = resp.next_continuation_token
      end
      true
    end

    def self.body(scope, name)
      name = name.split('*')[0] # Split '*' that indicates modified
      rubys3_client = Aws::S3::Client.new
      begin
        # First try opening a potentially modified version by looking for the modified target
        if ENV['OPENC3_LOCAL_MODE']
          local_file = OpenC3::LocalMode.open_local_file(name, scope: scope)
          return local_file.read if local_file
        end

        resp =
          rubys3_client.get_object(
            bucket: DEFAULT_BUCKET_NAME,
            key: "#{scope}/targets_modified/#{name}",
          )
      rescue Aws::S3::Errors::NoSuchKey
        # Now try the original
        resp =
          rubys3_client.get_object(
            bucket: DEFAULT_BUCKET_NAME,
            key: "#{scope}/targets/#{name}",
          )
      end
      if File.extname(name) == ".bin"
        resp.body.binmode
      end
      resp.body.read
    end

    def self.create(scope, name, text, content_type: 'text/plain')
      return false unless text
      if ENV['OPENC3_LOCAL_MODE']
        OpenC3::LocalMode.put_target_file("#{scope}/targets_modified/#{name}", text, scope: scope)
      end
      OpenC3::S3Utilities.put_object_and_check(
        # Use targets_modified to save modifications
        # This keeps the original target clean (read-only)
        key: "#{scope}/targets_modified/#{name}",
        body: text,
        bucket: DEFAULT_BUCKET_NAME,
        content_type: content_type,
      )
      true
    end

    def self.destroy(scope, name)
      rubys3_client = Aws::S3::Client.new

      if ENV['OPENC3_LOCAL_MODE']
        OpenC3::LocalMode.delete_local("#{scope}/targets_modified/#{name}")
      end

      # Only delete file from the modified target directory
      rubys3_client.delete_object(
        key: "#{scope}/targets_modified/#{name}",
        bucket: DEFAULT_BUCKET_NAME,
      )
      true
    end

  end
end