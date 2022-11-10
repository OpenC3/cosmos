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

class GemsController < ApplicationController
  # List the installed gems
  def index
    return unless authorization('system')
    render :json => OpenC3::GemModel.names
  end

  # Add a new gem
  def create
    return unless authorization('admin')
    file = params[:gem]
    if file
      temp_dir = Dir.mktmpdir
      result = false
      begin
        gem_file_path = temp_dir + '/' + file.original_filename
        FileUtils.cp(file.tempfile.path, gem_file_path)
        OpenC3::GemModel.put(gem_file_path, gem_install: true, scope: params[:scope])
        OpenC3::Logger.info("Gem created: #{params[:gem]}", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
        head :ok
      rescue => e
        OpenC3::Logger.error("Error installing gem: #{file.original_filename}:#{e.formatted}", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
        render :json => { :status => 'error', :message => e.message, 'type' => e.class }, :status => 400
      ensure
        FileUtils.remove_entry(temp_dir) if temp_dir and File.exist?(temp_dir)
      end
    else
      OpenC3::Logger.error("Error installing gem: Gem file as params[:gem] is required", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
      render :json => { :status => 'error', :message => "Gem file as params[:gem] is required" }, :status => 400
    end
  end

  # Remove a gem
  def destroy
    return unless authorization('admin')
    if params[:id]
      begin
        OpenC3::GemModel.destroy(params[:id])
        OpenC3::Logger.info("Gem destroyed: #{params[:id]}", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
        head :ok
      rescue => e
        OpenC3::Logger.error("Error destroying gem: #{params[:id]}:#{e.formatted}", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
        render :json => { :status => 'error', :message => e.message, 'type' => e.class }, :status => 400
      end
    else
      OpenC3::Logger.error("Error destroying gem: Gem name as params[:id] is required", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
      render :json => { :status => 'error', :message => "Gem name as params[:id] is required" }, :status => 400
    end
  end
end
