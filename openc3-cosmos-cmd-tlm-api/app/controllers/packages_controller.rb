# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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

require 'openc3/models/gem_model'
require 'openc3/models/python_package_model'

class PackagesController < ApplicationController
  # List the installed packages
  def index
    return unless authorization('system')
    gems = OpenC3::GemModel.names
    packages = OpenC3::PythonPackageModel.names
    render json: { ruby: gems, python: packages }
  end

  # Add a new package
  def create
    return unless authorization('admin')
    file = params[:package]
    if file
      temp_dir = Dir.mktmpdir
      result = false
      begin
        package_file_path = temp_dir + '/' + file.original_filename
        FileUtils.cp(file.tempfile.path, package_file_path)
        if File.extname(package_file_path) == '.gem'
          process_name = OpenC3::GemModel.put(package_file_path, gem_install: true, scope: params[:scope])
        else
          process_name = OpenC3::PythonPackageModel.put(package_file_path, package_install: true, scope: params[:scope])
        end
        OpenC3::Logger.info("Package created: #{params[:package]}", scope: params[:scope], user: username())
        render json: process_name
      rescue => e
        OpenC3::Logger.error("Error installing package: #{file.original_filename}:#{e.formatted}", scope: params[:scope], user: username())
        render json: { status: 'error', message: e.message, type: e.class }, status: 400
      ensure
        FileUtils.remove_entry(temp_dir) if temp_dir and File.exist?(temp_dir)
      end
    else
      OpenC3::Logger.error("Error installing package: Package file as params[:package] is required", scope: params[:scope], user: username())
      render json: { status: 'error', message: "Package file as params[:package] is required" }, status: 400
    end
  end

  # Remove a package
  def destroy
    return unless authorization('admin')
    if params[:id]
      begin
        if params[:id] =~ /\.gem/
          OpenC3::GemModel.destroy(params[:id])
        else
          OpenC3::PythonPackageModel.destroy(params[:id], scope: params[:scope])
        end
        OpenC3::Logger.info("Package destroyed: #{params[:id]}", scope: params[:scope], user: username())
        head :ok
      rescue => e
        OpenC3::Logger.error("Error destroying package: #{params[:id]}:#{e.formatted}", scope: params[:scope], user: username())
        render json: { status: 'error', message: e.message, type: e.class }, status: 400
      end
    else
      OpenC3::Logger.error("Error destroying package: Package name as params[:id] is required", scope: params[:scope], user: username())
      render json: { status: 'error', message: "Package name as params[:id] is required" }, status: 400
    end
  end

  def download
    return unless authorization('admin')
    begin
      package_name = File.basename(params[:id]).split("__")[0]
      if package_name =~ /\.gem/
        package_file_path = OpenC3::GemModel.get(package_name)
      else
        package_file_path = OpenC3::PythonPackageModel.get(package_name)
      end
      file = File.read(package_file_path, mode: 'rb')
      render json: { filename: package_name, contents: Base64.encode64(file) }
    rescue Exception => e
      OpenC3::Logger.info("Package '#{params[:id]}' download failed: #{e.message}", user: username())
      render json: { status: 'error', message: e.message }, status: 500
    end
  end
end
