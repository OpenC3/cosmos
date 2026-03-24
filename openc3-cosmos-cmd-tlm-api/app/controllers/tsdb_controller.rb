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

require 'openc3/utilities/questdb_client'

class TsdbController < ApplicationController
  def execute_raw
    return unless authorization('admin')

    sql = request.body.read
    if sql.blank?
      render json: { status: 'error', message: 'No SQL query provided.' }, status: :unprocessable_entity
      return
    end

    begin
      conn = OpenC3::QuestDBClient.connection
      result = conn.exec(sql)
      columns = result.fields
      rows = result.values
      OpenC3::Logger.info("TSDB query executed: #{sql}", user: username())
      render json: { columns: columns, rows: rows }, status: :ok
    rescue => e
      OpenC3::QuestDBClient.disconnect
      render json: { status: 'error', message: e.message }, status: :unprocessable_entity
    end
  end
end
