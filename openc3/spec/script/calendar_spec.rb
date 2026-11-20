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

require 'spec_helper'
require 'openc3/script'

module OpenC3
  describe Script do
    describe "calendar" do
      before(:each) do
        @orig_api_server = $api_server
        $api_server = double("ApiServer")
        @response = double("Response", status: 200, body: '[]')
      end

      after(:each) do
        $api_server = @orig_api_server
      end

      describe "get_timeline_activities" do
        it "joins start, stop and limit with &" do
          expect($api_server).to receive(:request).with('get', "/openc3-api/timeline/TL/activities?start=1700000000&stop=1800000000&limit=5", scope: 'DEFAULT').and_return(@response)
          get_timeline_activities('TL', start: 1700000000, stop: 1800000000, limit: 5, scope: 'DEFAULT')
        end

        it "sends only limit" do
          expect($api_server).to receive(:request).with('get', "/openc3-api/timeline/TL/activities?limit=5", scope: 'DEFAULT').and_return(@response)
          get_timeline_activities('TL', limit: 5, scope: 'DEFAULT')
        end

        it "sends no query without parameters" do
          expect($api_server).to receive(:request).with('get', "/openc3-api/timeline/TL/activities", scope: 'DEFAULT').and_return(@response)
          get_timeline_activities('TL', scope: 'DEFAULT')
        end
      end

      describe "delete_timeline_activity" do
        it "deletes a single activity by default" do
          expect($api_server).to receive(:request).with('delete', "/openc3-api/timeline/TL/activity/100/UUID", scope: 'DEFAULT').and_return(@response)
          delete_timeline_activity('TL', 100, 'UUID', scope: 'DEFAULT')
        end

        it "deletes the recurring group when recurring is true" do
          expect($api_server).to receive(:request).with('delete', "/openc3-api/timeline/TL/activity/100/UUID?recurring=true", scope: 'DEFAULT').and_return(@response)
          delete_timeline_activity('TL', 100, 'UUID', recurring: true, scope: 'DEFAULT')
        end
      end
    end
  end
end
