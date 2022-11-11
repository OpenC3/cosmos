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

class ScreensController < ApplicationController
  def index
    return unless authorization('system')
    render :json => Screen.all(*params.require([:scope, :target]))
  end

  def show
    return unless authorization('system')
    screen = Screen.find(*params.require([:scope, :target, :screen]))
    if screen
      render :json => screen
    else
      head :not_found
    end
  end

  def create
    return unless authorization('system_set')
    screen = Screen.create(*params.require([:scope, :target, :screen, :text]))
    OpenC3::Logger.info("Screen saved: #{params[:target]} #{params[:screen]}", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
    render :json => screen
  rescue => e
    render(json: { status: 'error', message: e.message }, status: 500)
  end

  def destroy
    return unless authorization('system_set')
    screen = Screen.destroy(*params.require([:scope, :target, :screen]))
    OpenC3::Logger.info("Screen deleted: #{params[:target]} #{params[:screen]}", scope: params[:scope], user: user_info(request.headers['HTTP_AUTHORIZATION']))
    head :ok
  rescue => e
    render(json: { status: 'error', message: e.message }, status: 500)
  end
end
