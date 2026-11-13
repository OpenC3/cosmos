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

require 'rails_helper'

RSpec.describe 'TSDB partition routes', type: :routing do
  # The route table is inspected directly because core resolves the controller
  # to an empty stub class that the Rails route recognizers cannot introspect
  def recognize(verb, path)
    route = Rails.application.routes.routes.find do |r|
      r.verb == verb.to_s.upcase && r.path.spec.to_s.delete_suffix("(.:format)") == "/openc3-api#{path}"
    end
    route && route.requirements.slice(:controller, :action)
  end

  {
    [:get, '/tsdb/partitions/destinations'] => 'destinations',
    [:get, '/tsdb/partitions/settings'] => 'settings',
    [:put, '/tsdb/partitions/settings'] => 'update_settings',
    [:get, '/tsdb/partitions/schedule/preview'] => 'preview',
    [:get, '/tsdb/partitions/status'] => 'status',
    [:get, '/tsdb/partitions/archived'] => 'archived',
    [:post, '/tsdb/partitions/run'] => 'run',
    [:post, '/tsdb/partitions/restore'] => 'restore',
    [:post, '/tsdb/partitions/release'] => 'release',
    [:post, '/tsdb/partitions/rescan'] => 'rescan',
    [:post, '/tsdb/partitions/unblock'] => 'unblock',
  }.each do |(verb, path), action|
    it "routes #{verb.upcase} #{path} to tsdb_partitions##{action}" do
      expect(recognize(verb, path)).to eq(controller: 'tsdb_partitions', action: action)
    end
  end

  it 'routes GET /tsdb/partitions/jobs/:id to tsdb_partitions#job' do
    expect(recognize(:get, '/tsdb/partitions/jobs/:id')).to eq(controller: 'tsdb_partitions', action: 'job')
  end

  it 'routes POST /tsdb/partitions/jobs/:id/cancel to tsdb_partitions#cancel' do
    expect(recognize(:post, '/tsdb/partitions/jobs/:id/cancel')).to eq(controller: 'tsdb_partitions', action: 'cancel')
  end
end
