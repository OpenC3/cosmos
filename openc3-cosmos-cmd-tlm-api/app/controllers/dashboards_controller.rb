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
    # ?summary=true: each dashboard's title, icon, color and panel count too,
    # for the Dashboards navigator
    if params[:summary].to_s == 'true'
      render json: Dashboard.summaries(scope)
    else
      render json: Dashboard.all(scope)
    end
  end

  def show
    return unless authorization('system')
    scope, target, name = sanitize_params([:scope, :target, :dashboard])
    return unless scope
    path = Dashboard.path(target, name)
    dashboard = Dashboard.find(scope, target, name)
    if dashboard
      # Enterprise-only (constant loaded by the openc3-enterprise gem): give
      # dashboards installed by a plugin a baseline version before any edit
      if defined?(::VersionStore)
        plugin = OpenC3::TargetModel.plugin_version_label(target, scope: scope)
        ::VersionStore.seed_initial_if_empty(scope: scope, name: path, body: dashboard, plugin: plugin)
      end
      render json: dashboard
    else
      head :not_found
    end
  rescue ArgumentError => e
    render json: { status: 'error', message: e.message }, status: :bad_request
  end

  def create
    return unless authorization('system_set')
    scope, target, name = sanitize_params([:scope, :target, :dashboard])
    return unless scope
    text = params.require([:text])[0]
    path = Dashboard.path(target, name)
    Dashboard.create(scope, target, name, text)
    results = {}
    # Enterprise-only: record who saved what as a version in git history
    if defined?(::VersionStore)
      sha = ::VersionStore.commit(scope: scope, name: path, text: text, username: username())
      results['version_id'] = sha if sha
    end
    OpenC3::Logger.info("Dashboard saved: #{path}", scope: scope, user: username())
    render json: results
  rescue ArgumentError => e
    render json: { status: 'error', message: e.message }, status: :bad_request
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end

  def destroy
    return unless authorization('system_set')
    scope, target, name = sanitize_params([:scope, :target, :dashboard])
    return unless scope
    path = Dashboard.path(target, name)
    Dashboard.destroy(scope, target, name)
    # Enterprise-only: record the deletion in git history
    ::VersionStore.delete(scope: scope, name: path, username: username()) if defined?(::VersionStore)
    OpenC3::Logger.info("Dashboard deleted: #{path}", scope: scope, user: username())
    head :ok
  rescue ArgumentError => e
    render json: { status: 'error', message: e.message }, status: :bad_request
  rescue => e
    log_error(e)
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end
end
