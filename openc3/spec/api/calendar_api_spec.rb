# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/api/calendar_api'

module OpenC3
  describe Api do
    class ApiTest
      include Extract
      include Api
      include Authorization
    end

    before(:each) do
      mock_redis()
      @api = ApiTest.new
    end

    describe "create_timeline" do
      it "creates a timeline" do
        @api.create_timeline('TEST')
        @api.create_timeline('contacts')
        timelines = @api.list_timelines()
        expect(timelines).to eql ['CONTACTS', 'TEST']
      end
    end

    describe "get_timeline" do
      it "gets a timeline" do
        @api.create_timeline('TEST')
        timeline = @api.get_timeline('TEST')
        expect(timeline['name']).to eql 'TEST'
        expect(timeline['scope']).to eql 'DEFAULT'
        expect(timeline['color']).to match(/#[0-9a-fA-F]{6}/)
      end
    end

    describe "set_timeline_color" do
      it "updates a timeline color" do
        @api.create_timeline('TEST')
        @api.set_timeline_color('TEST', '#123456')
        timeline = @api.get_timeline('TEST')
        expect(timeline['name']).to eql 'TEST'
        expect(timeline['scope']).to eql 'DEFAULT'
        expect(timeline['color']).to eql('#123456')
      end
    end

    describe "create_timeline_activity, get_timeline_activities" do
      it "creates a timeline activity" do
        @api.create_timeline('TEST')
        now = Time.now.to_i
        @api.create_timeline_activity('TEST', kind: "RESERVE", start: now + 30, stop: now + 60)
        activities = @api.get_timeline_activities('TEST')
        expect(activities).to be_a Array
        expect(activities[0]['name']).to eql 'TEST'
        expect(activities[0]['start']).to eql (now + 30)
        expect(activities[0]['stop']).to eql (now + 60)
        expect(activities[0]['duration']).to eql 30
        expect(activities[0]['kind']).to eql 'RESERVE'
      end

      it "raises when creating activity in the past" do
        @api.create_timeline('TEST')
        now = Time.now.to_i
        expect { @api.create_timeline_activity('TEST', kind: "RESERVE", start: now -1, stop: now + 60) }.to raise_error(/activity must be in the future/)
      end
    end
  end
end
