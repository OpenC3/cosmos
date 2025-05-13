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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'fileutils'
require 'json'
require 'openc3/utilities/local_mode'
require 'openc3/utilities/bucket'

module OpenC3
  class TargetFile
    # Matches ScriptRunner.vue const TEMP_FOLDER
    TEMP_FOLDER = '__TEMP__'

    def self.all(scope, path_matchers, target: nil)
      target = target.upcase if target

      include_temp = true
      bucket = Bucket.getClient()
      if target
        prefix = "#{scope}/targets/#{target}/"
        modified_prefix = "#{scope}/targets_modified/#{target}/"
        if target != TEMP_FOLDER
          include_temp = false
        end
      else
        prefix = "#{scope}/targets/"
        modified_prefix = "#{scope}/targets_modified/"
      end
      result, _ = remote_target_files(bucket_client: bucket, prefix: prefix, include_temp: false, path_matchers: path_matchers)
      modified, temp = remote_target_files(bucket_client: bucket, prefix: modified_prefix, include_temp: include_temp, path_matchers: path_matchers)

      # Add in local targets_modified if present
      if ENV['OPENC3_LOCAL_MODE']
        local_modified = OpenC3::LocalMode.local_target_files(scope: scope, target: target, path_matchers: path_matchers, include_temp: include_temp)
        local_modified.each do |filename|
          if include_temp and filename.include?(TEMP_FOLDER)
            temp << filename
          else
            modified << filename unless modified.include?(filename)
            result << filename unless result.include?(filename)
          end
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
      result = result.merge(modified)
      result = result.merge(temp.uniq)
      result.sort
    end

    def self.delete_temp(scope)
      bucket = Bucket.getClient()
      resp = bucket.list_objects(
        bucket: ENV['OPENC3_CONFIG_BUCKET'],
        prefix: "#{scope}/targets_modified/#{TEMP_FOLDER}",
      )
      files = []
      resp.each do |object|
        files << object.key
        bucket.delete_object(
          bucket: ENV['OPENC3_CONFIG_BUCKET'],
          key: object.key,
        )
        if ENV['OPENC3_LOCAL_MODE']
          OpenC3::LocalMode.delete_local(object.key)
        end
      end
      files
    end

    def self.body(scope, name)
      name = name.split('*')[0] # Split '*' that indicates modified
      # First try opening a potentially modified version by looking for the modified target
      if ENV['OPENC3_LOCAL_MODE']
        local_file = OpenC3::LocalMode.open_local_file(name, scope: scope)
        if local_file
          if File.extname(name) == ".bin"
            return local_file.read
          else
            return local_file.read.force_encoding('UTF-8')
          end
        end
      end

      bucket = Bucket.getClient()
      resp = bucket.get_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: "#{scope}/targets_modified/#{name}")
      unless resp
        # Now try the original
        resp = bucket.get_object(bucket: ENV['OPENC3_CONFIG_BUCKET'], key: "#{scope}/targets/#{name}")
      end
      if resp && resp.body
        if File.extname(name) == ".bin"
          resp.body.binmode
          return resp.body.read
        else
          return resp.body.read.force_encoding('UTF-8')
        end
      else
        nil
      end
    end

    def self.create(scope, name, text, content_type: 'text/plain')
      return false unless text
      if ENV['OPENC3_LOCAL_MODE']
        OpenC3::LocalMode.put_target_file("#{scope}/targets_modified/#{name}", text, scope: scope)
      end
      client = Bucket.getClient()
      client.put_object(
        # Use targets_modified to save modifications
        # This keeps the original target clean (read-only)
        bucket: ENV['OPENC3_CONFIG_BUCKET'],
        key: "#{scope}/targets_modified/#{name}",
        body: text,
        content_type: content_type,
      )
      # Wait for the object to exist
      if client.check_object(
        bucket: ENV['OPENC3_CONFIG_BUCKET'],
        key: "#{scope}/targets_modified/#{name}",
      )
        true
      else
        false
      end
    end

    def self.destroy(scope, name)
      if ENV['OPENC3_LOCAL_MODE']
        OpenC3::LocalMode.delete_local("#{scope}/targets_modified/#{name}")
      end

      # Only delete file from the modified target directory
      Bucket.getClient.delete_object(
        bucket: ENV['OPENC3_CONFIG_BUCKET'],
        key: "#{scope}/targets_modified/#{name}",
      )
      true
    end

    # protected

    def self.remote_target_files(bucket_client:, prefix:, include_temp: false, path_matchers: nil)
      result = Set.new
      temp = Set.new
      resp = bucket_client.list_objects(
        bucket: ENV['OPENC3_CONFIG_BUCKET'],
        prefix: prefix,
      )
      resp.each do |object|
        split_key = object.key.split('/')
        # DEFAULT/targets_modified/__TEMP__/YYYY_MM_DD_HH_MM_SS_mmm_temp.rb
        if split_key[2] == TEMP_FOLDER
          temp << split_key[2..-1].join('/') if include_temp
          next
        end

        if path_matchers
          found = false
          path_matchers.each do |path|
            if split_key.include?(path)
              found = true
              break
            end
          end
          next unless found
        end
        result_no_scope_or_target_folder = split_key[2..-1].join('/')
        result << result_no_scope_or_target_folder
      end
      return result, temp
    end
  end
end
