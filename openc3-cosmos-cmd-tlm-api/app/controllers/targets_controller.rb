# encoding: utf-8

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/target_model'

class TargetsController < ModelController
  def initialize
    @model_class = OpenC3::TargetModel
  end

  # All targets with indication of modified targets
  def all_modified
    return unless authorization('system')
    scope = sanitize_params([:scope], require_params: true)
    return unless scope
    scope = scope[0]
    render json: @model_class.all_modified(scope: scope)
  end

  def modified_files
    return unless authorization('system')
    scope, id = sanitize_params([:scope, :id], require_params: true)
    return unless scope
    begin
      render json: @model_class.modified_files(id, scope: scope)
    rescue Exception => e
      log_error(e)
      OpenC3::Logger.info("Target '#{id} modified_files failed: #{e.message}", user: username())
      head :internal_server_error
    end
  end

  def delete_modified
    return unless authorization('system')
    scope, id = sanitize_params([:scope, :id], require_params: true)
    return unless scope
    begin
      @model_class.delete_modified(id, scope: scope)
      head :ok
    rescue Exception => e
      log_error(e)
      OpenC3::Logger.info("Target '#{id} delete_modified failed: #{e.message}", user: username())
      head :internal_server_error
    end
  end

  def download
    return unless authorization('system')
    scope, id = sanitize_params([:scope, :id], require_params: true)
    return unless scope
    begin
      file = @model_class.download(id, scope: scope)
      if file
        results = { filename: file.filename, contents: Base64.encode64(file.contents) }
        render json: results
      else
        head :not_found
      end
    rescue Exception => e
      log_error(e)
      OpenC3::Logger.info("Target '#{id} download failed: #{e.message}", user: username())
      render json: { status: 'error', message: e.message }, status: 500
    end
  end
end
