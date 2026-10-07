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

class DashboardsController < ApplicationController
  def index
    return unless authorization('system')
    scope = sanitize_params([:scope])
    return unless scope
    scope = scope[0]
    render json: Dashboard.all(scope)
  end

  def show
    return unless authorization('system')
    result = sanitize_params([:scope, :target, :dashboard])
    return unless result
    dashboard = Dashboard.find(*result)
    if dashboard
      render json: dashboard
    else
      head :not_found
    end
  end

  def create
    return unless authorization('system_set')
    result = sanitize_params([:scope, :target, :dashboard])
    return unless result
    text = params.require([:text])[0]
    result << text
    dashboard = Dashboard.create(*result)
    OpenC3::Logger.info("Dashboard saved: #{params[:target]} #{params[:dashboard]}", scope: params[:scope], user: username())
    render json: dashboard
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def destroy
    return unless authorization('system_set')
    result = sanitize_params([:scope, :target, :dashboard])
    return unless result
    Dashboard.destroy(*result)
    OpenC3::Logger.info("Dashboard deleted: #{params[:target]} #{params[:dashboard]}", scope: params[:scope], user: username())
    head :ok
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end
end
