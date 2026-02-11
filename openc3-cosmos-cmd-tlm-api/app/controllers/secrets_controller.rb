# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/secrets'

class SecretsController < ApplicationController
  def index
    return unless authorization('admin')
    render json: OpenC3::Secrets.getClient.keys(scope: params[:scope])
  end

  def create
    return unless authorization('admin')

    file = params[:file]
    if file
      value = file.tempfile.read
    else
      value = params[:value]
    end

    OpenC3::Secrets.getClient.set(params[:key], value, scope: params[:scope])
    OpenC3::Logger.info("Secret set: #{params[:key]}", scope: params[:scope], user: username())
    head :ok
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: 500
  end

  def destroy
    return unless authorization('admin')
    OpenC3::Secrets.getClient.delete(params['key'], scope: params[:scope])
    OpenC3::Logger.info("Secret deleted: #{params[:key]}", scope: params[:scope], user: username())
    head :ok
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: 500
  end
end
