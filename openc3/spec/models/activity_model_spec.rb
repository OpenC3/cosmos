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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/models/activity_model'

module OpenC3
  describe ActivityModel do
    before(:each) do
      mock_redis()
    end

    def generate_activity(name:, scope:, start:, kind: "COMMAND", stop: 1.0, data: { "test" => "test" })
      dt = DateTime.now.new_offset(0)
      start_time = dt + (start / 24.0)
      end_time = dt + ((start + stop) / 24.0)
      ActivityModel.new(
        name: name,
        scope: scope,
        start: start_time.strftime("%s").to_i,
        stop: end_time.strftime("%s").to_i,
        kind: kind,
        data: data
      )
    end

    context "recurring" do
      describe "self.create" do
        it "creates a recurring activity" do
          start = Time.now + 60 # 1 min
          stop = start + 1800 # 30 min
          data = { "test" => "test" }
          recurring_end = start + (86400 * 5) # 5 days
          # Create a recurring every day
          recurring = { 'frequency' => '1', 'span' => 'days', 'end' => recurring_end.to_i }
          activity = ActivityModel.new(
            name: 'recurring',
            scope: 'DEFAULT',
            start: start.to_i,
            stop: stop.to_i,
            kind: "COMMAND",
            data: data,
            recurring: recurring
          )
          activity.create()
          array = ActivityModel.all(name: 'recurring', scope: 'DEFAULT')
          expect(array.length).to eql(6)
          array.each do |item|
            expect(item['start']).to eql(start.to_i)
            expect(item['stop']).to eql(stop.to_i)
            start += 86400
            stop += 86400
          end
        end

        it "creates only 1 if that fits" do
          start = Time.now + 60 # 1 min
          stop = start + 1800 # 30 min
          data = { "test" => "test" }
          recurring_end = start + 3500
          # Create a recurring every 1 hr
          recurring = { 'frequency' => '1', 'span' => 'hours', 'end' => recurring_end.to_i }
          activity = ActivityModel.new(
            name: 'recurring',
            scope: 'DEFAULT',
            start: start.to_i,
            stop: stop.to_i,
            kind: "COMMAND",
            data: data,
            recurring: recurring
          )
          activity.create()
          array = ActivityModel.all(name: 'recurring', scope: 'DEFAULT')
          expect(array.length).to eql(1)
          expect(array[0]['start']).to eql(start.to_i)
          expect(array[0]['stop']).to eql(stop.to_i)
        end

        it "raises if recurring overlap" do
          start = Time.now + 60 # 1 min
          stop = start + 1800 # 30 min
          data = { "test" => "test" }
          recurring_end = start + 7200
          # Create a recurring every 20 min
          recurring = { 'frequency' => '20', 'span' => 'minutes', 'end' => recurring_end.to_i }
          activity = ActivityModel.new(
            name: 'recurring',
            scope: 'DEFAULT',
            start: start.to_i,
            stop: stop.to_i,
            kind: "COMMAND",
            data: data,
            recurring: recurring
          )
          expect { activity.create() }.to raise_error(ActivityOverlapError, /Recurring activity overlap/)
          array = ActivityModel.all(name: 'recurring', scope: 'DEFAULT')
          expect(array.length).to eql(0)
        end

        it "creates adjacent recurring" do
          start = Time.now + 60 # 1 min
          stop = start + 1800 # 30 min
          data = { "test" => "test" }
          recurring_end = start + 7200 # 2 hrs
          # Create a recurring every 60 min
          recurring = { 'frequency' => '60', 'span' => 'minutes', 'end' => recurring_end.to_i }
          activity = ActivityModel.new(
            name: 'recurring',
            scope: 'DEFAULT',
            start: start.to_i,
            stop: stop.to_i,
            kind: "COMMAND",
            data: data,
            recurring: recurring
          )
          activity.create()

          start += 1800 # 30 min
          stop += 1800 # 30 min
          recurring_end = start + 7200 # 2 hrs
          # Create a recurring every 60 min
          recurring = { 'frequency' => '60', 'span' => 'minutes', 'end' => recurring_end.to_i }
          activity = ActivityModel.new(
            name: 'recurring',
            scope: 'DEFAULT',
            start: start.to_i,
            stop: stop.to_i,
            kind: "COMMAND",
            data: data,
            recurring: recurring
          )
          activity.create()
        end

        it "can abort if recurring overlaps existing" do
          # Create a normal activity 1 hrs out
          now = Time.now + 10
          start = now + 3600 # 1 hr
          stop = start + 300 # 5 min
          data = { "test" => "test" }
          activity = ActivityModel.new(
            name: 'recurring',
            scope: 'DEFAULT',
            start: start.to_i,
            stop: stop.to_i,
            kind: "COMMAND",
            data: data,
          )
          activity.create()

          start = now # Back up to now
          stop = start + 1800 # 30 min
          recurring_end = start + 7200 # 2 hrs
          # Create a recurring every 30 min (fill it up)
          recurring = { 'frequency' => '30', 'span' => 'minutes', 'end' => recurring_end.to_i }
          activity = ActivityModel.new(
            name: 'recurring',
            scope: 'DEFAULT',
            start: start.to_i,
            stop: stop.to_i,
            kind: "COMMAND",
            data: data,
            recurring: recurring
          )
          expect { activity.create(overlap: false) }.to raise_error(ActivityOverlapError, /activity overlaps existing/)
          array = ActivityModel.all(name: 'recurring', scope: 'DEFAULT')
          expect(array.length).to eql(1)

          activity.create() # overlap: true is the default
          array = ActivityModel.all(name: 'recurring', scope: 'DEFAULT')
          expect(array.length).to eql(4)
        end
      end

      describe "self.destroy" do
        it "removes all associated recurring entries" do
          start = Time.now + 60 # 1 min
          stop = start + 1800 # 30 min
          data = { "test" => "test" }
          recurring_end = start + 7200 # 2 hours
          # Create a recurring every 30 min
          recurring = { 'frequency' => '30', 'span' => 'minutes', 'end' => recurring_end.to_i }
          ActivityModel.new(
            name: 'recurring',
            scope: 'DEFAULT',
            start: start.to_i,
            stop: stop.to_i,
            kind: "COMMAND",
            data: data,
            recurring: recurring
          ).create()
          array = ActivityModel.all(name: 'recurring', scope: 'DEFAULT')
          expect(array.length).to eql(5)
          # Delete one of the activities
          ActivityModel.destroy(name: 'recurring', scope: 'DEFAULT', score: array[0]['start'], uuid: array[0]['uuid'])
          expect(ActivityModel.count(name: 'recurring', scope: 'DEFAULT')).to eql(4)
          ActivityModel.destroy(name: 'recurring', scope: 'DEFAULT', score: array[1]['start'], uuid: array[1]['recurring']['uuid'], recurring: true)
          expect(ActivityModel.count(name: 'recurring', scope: 'DEFAULT')).to eql(0)
        end
      end
    end

    describe "self.activities" do
      it "returns activities for the next hour" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1)
        activity.create()
        activity = generate_activity(name: name, scope: scope, start: 10)
        activity.create()
        array = ActivityModel.activities(name: name, scope: scope)
        expect(array.empty?).to eql(false)
        expect(array.length).to eql(1)
        expect(array[0].kind).to eql("command")
        expect(array[0].start).not_to be_nil
        expect(array[0].stop).not_to be_nil
      end
    end

    describe "self.get" do
      it "returns all activities between X and Y" do
        name = "foobar"
        scope = "scope"
        activity1 = generate_activity(name: name, scope: scope, start: 1.5, kind: 'SCRIPT')
        activity1.create()
        activity2 = generate_activity(name: name, scope: scope, start: 5.0, kind: 'SCRIPT')
        activity2.create()
        dt = DateTime.now.new_offset(0)
        start = (dt + (1 / 24.0)).strftime("%s").to_i
        stop = (dt + (3 / 24.0)).strftime("%s").to_i
        array = ActivityModel.get(name: name, scope: scope, start: start, stop: stop)
        expect(array.empty?).to eql(false)
        expect(array.length).to eql(1)
        expect(array[0]["kind"]).to eql("script")
        expect(array[0]["start"]).to eql(activity1.start)
        expect(array[0]["stop"]).to eql(activity1.stop)
      end

      it "verifies start > stop" do
        expect {
          ActivityModel.get(name: 'test', scope: 'DEFAULT', start: 101, stop: 100)
        }.to raise_error(ActivityInputError, "start: 101 must be <= stop: 100")
      end
    end

    describe "self.all" do
      it "returns all the activities" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 2.0)
        activity.create()
        activity = generate_activity(name: name, scope: scope, start: 4.0)
        activity.create()
        all = ActivityModel.all(name: name, scope: scope)
        expect(all.empty?).to eql(false)
        expect(all.length).to eql(2)
        expect(all[0]["kind"]).to eql("command")
        expect(all[0]["start"]).not_to be_nil
        expect(all[0]["stop"]).not_to be_nil
        expect(all[1]["kind"]).not_to be_nil
        expect(all[1]["start"]).not_to be_nil
        expect(all[1]["stop"]).not_to be_nil
      end
    end

    describe "self.start" do
      it "returns a ActivityModel at the start" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0)
        activity.create()
        model = ActivityModel.score(name: name, scope: scope, score: activity.start)
        expect(model.fulfillment).to eql(false)
        expect(model.start).to eql(activity.start)
        expect(model.stop).to eql(activity.stop)
        expect(model.data).to include("test")
        expect(model.events.empty?).to eql(false)
        expect(model.events.length).to eql(1)
      end

      it "supports floating point start and stop" do
        name = "foobar"
        scope = "scope"
        activity = ActivityModel.new(
          name: name,
          scope: scope,
          start: (Time.now + 1).to_f,
          stop: (Time.now + 1.5).to_f,
          kind: "COMMAND",
          data: {}
        )
        activity.create()
        model = ActivityModel.score(name: name, scope: scope, score: activity.start)
        expect(model.fulfillment).to eql(false)
        expect(model.start).to eql(activity.start)
        expect(model.stop).to eql(activity.stop)
        expect(model.events.empty?).to eql(false)
        expect(model.events.length).to eql(1)
      end
    end

    describe "self.count" do
      it "returns the count of the timeline" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0)
        activity.create()
        activity = generate_activity(name: name, scope: scope, start: 2.5)
        activity.create()
        count = ActivityModel.count(name: name, scope: scope)
        expect(count).to eql(2)
      end
    end

    describe "self.destroy" do
      it "removes the activity" do
        start = Time.now.to_i + 10
        model1 = ActivityModel.new(
          name: 'timeline',
          scope: 'DEFAULT',
          start: start,
          stop: start + 10,
          kind: 'COMMAND',
          data: {'key' => 'val1'}
        )
        model1.create()
        # Create another activity with the same start time
        model2 = ActivityModel.new(
          name: 'timeline',
          scope: 'DEFAULT',
          start: start,
          stop: start + 10,
          kind: 'COMMAND',
          data: {'key' => 'val2'}
        )
        model2.create()
        expect(ActivityModel.count(name: 'timeline', scope: 'DEFAULT')).to eql 2
        ActivityModel.destroy(name: 'timeline', scope: 'DEFAULT', score: start, uuid: model1.uuid)
        # expect(ret).to eql(1) # TODO: mock_redis 0.45 not returning the correct value (Redis v4 vs v5 behavior)
        expect(ActivityModel.count(name: 'timeline', scope: 'DEFAULT')).to eql 1
        ActivityModel.destroy(name: 'timeline', scope: 'DEFAULT', score: start, uuid: model2.uuid)
        # expect(ret).to eql(1) # TODO: mock_redis 0.45 not returning the correct value (Redis v4 vs v5 behavior)
        expect(ActivityModel.count(name: 'timeline', scope: 'DEFAULT')).to eql 0
      end
    end

    describe "self.range_destroy" do
      it "removes multiple members form of the timeline" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 0.5)
        activity.create()
        activity = generate_activity(name: name, scope: scope, start: 2.0)
        activity.create()
        dt = DateTime.now.new_offset(0)
        min_score = (dt + (0.5 / 24.0)).strftime("%s").to_i
        max_score = (dt + (3.0 / 24.0)).strftime("%s").to_i
        ret = ActivityModel.range_destroy(name: name, scope: scope, min: min_score, max: max_score)
        expect(ret).to eql(2)
        count = ActivityModel.count(name: name, scope: scope)
        expect(count).to eql(0)
      end
    end

    describe "model.create" do
      it "raises due to bad date" do
        name = "foobar"
        scope = "scope"
        expect {
          ActivityModel.new(
            name: name,
            scope: scope,
            start: (Time.now + 10).iso8601(),
            stop: (Time.now + 11).iso8601(),
            kind: "COMMAND",
            data: {}
          )
        }.to raise_error(ActivityInputError, /start and stop must be seconds/)
      end

      it "raises due to bad kind" do
        name = "foobar"
        scope = "scope"
        expect {
          ActivityModel.new(
            name: name,
            scope: scope,
            start: (Time.now + 10).to_i,
            stop: (Time.now + 11).to_i,
            kind: nil,
            data: {}
          )
        }.to raise_error(ActivityInputError, /unknown kind: , must be one of command, script, reserve, expire/)

        expect {
          ActivityModel.new(
            name: name,
            scope: scope,
            start: (Time.now + 10).to_i,
            stop: (Time.now + 11).to_i,
            kind: 'OTHER',
            data: {}
          )
        }.to raise_error(ActivityInputError, /unknown kind: other, must be one of command, script, reserve, expire/)
      end

      it "raises due to bad data" do
        name = "foobar"
        scope = "scope"
        expect {
          ActivityModel.new(
            name: name,
            scope: scope,
            start: (Time.now + 10).to_i,
            stop: (Time.now + 11).to_i,
            kind: 'COMMAND',
            data: nil
          )
        }.to raise_error(ActivityInputError, /data must not be nil/)

        expect {
          ActivityModel.new(
            name: name,
            scope: scope,
            start: (Time.now + 10).to_i,
            stop: (Time.now + 11).to_i,
            kind: 'COMMAND',
            data: 'test'
          )
        }.to raise_error(ActivityInputError, /data must be a json object\/hash/)
      end

      it "raises error due to overlap starts inside A and ends inside A" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0, stop: 1.0)
        activity.create()
        model = generate_activity(name: name, scope: scope, start: 1.1, stop: 0.8)
        expect {
          model.create(overlap: false)
        }.to raise_error(ActivityOverlapError)
      end

      it "raises error due to overlap starts before A and ends before A" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0, stop: 1.0)
        activity.create()
        model = generate_activity(name: name, scope: scope, start: 0.5, stop: 1.0)
        expect {
          model.create(overlap: false)
        }.to raise_error(ActivityOverlapError)
      end

      it "raises error due to overlap starts inside A and ends outside A" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0, stop: 1.0)
        activity.create()
        model = generate_activity(name: name, scope: scope, start: 1.5, stop: 1.5)
        expect {
          model.create(overlap: false)
        }.to raise_error(ActivityOverlapError)
      end

      it "raises error due to overlap starts before A and ends after A" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0, stop: 1.0)
        activity.create()
        model = generate_activity(name: name, scope: scope, start: 0.5, stop: 1.5)
        expect {
          model.create(overlap: false)
        }.to raise_error(ActivityOverlapError)
      end

      it "raises error due to overlap starts before A and ends outside A inside a second activity" do
        name = "foobar"
        scope = "scope"
        foo = generate_activity(name: name, scope: scope, start: 1.0, stop: 0.5)
        foo.create()
        bar = generate_activity(name: name, scope: scope, start: 2.0, stop: 0.5)
        bar.create()
        activity = generate_activity(name: name, scope: scope, start: 0.5, stop: 1.7)
        expect {
          activity.create(overlap: false)
        }.to raise_error(ActivityOverlapError)
      end

      it "allows new activities with start == stop" do
        name = "foobar"
        scope = "scope"
        foo = generate_activity(name: name, scope: scope, start: 1.0, stop: 0.5)
        foo.create()
        bar = generate_activity(name: name, scope: scope, start: 2.0, stop: 0.5)
        bar.create()
        activity = generate_activity(name: name, scope: scope, start: 1.5, stop: 0.5)
        activity.create()
        expect(ActivityModel.all(name: name, scope: scope).length).to eql 3
      end
    end

    describe "time parse" do
      it "raises error due to invalid time" do
        name = "foobar"
        scope = "scope"
        expect {
          ActivityModel.new(name: name, scope: scope, start: "foo", stop: "bar", kind: "COMMAND", data: {})
        }.to raise_error(ActivityInputError)
      end
    end

    describe "time duration" do
      it "raises error due to event start and end are the same time" do
        name = "foobar"
        scope = "scope"
        start = Time.now.to_i
        expect {
          ActivityModel.new(name: name, scope: scope, start: start, stop: start, kind: "COMMAND", data: {})
        }.to raise_error(ActivityInputError)
      end

      it "raises error due to event longer then 24h" do
        name = "foobar"
        scope = "scope"
        dt_now = DateTime.now
        start = (dt_now + (1.0 / 24.0)).strftime("%s").to_i
        stop = (dt_now + (25.0 / 24.0)).strftime("%s").to_i
        ActivityModel.new(name: name, scope: scope, start: start, stop: stop, kind: "COMMAND", data: {})
        expect {
          # Add an extra second to go over 24h
          ActivityModel.new(name: name, scope: scope, start: start, stop: stop + 1, kind: "COMMAND", data: {})
        }.to raise_error(ActivityInputError)
      end
    end

    describe "time entry" do
      it "raises error due to event start is after stop" do
        name = "foobar"
        scope = "scope"
        dt_now = DateTime.now
        start = (dt_now + (1.5 / 24.0)).strftime("%s").to_i
        stop = (dt_now + (1.0 / 24.0)).strftime("%s").to_i
        expect {
          ActivityModel.new(name: name, scope: scope, start: start, stop: stop, kind: "COMMAND", data: {})
        }.to raise_error(ActivityInputError)
      end

      it "raises error due to start before now" do
        name = "foobar"
        scope = "scope"
        dt_now = DateTime.now
        start = (dt_now - (1.5 / 24.0)).strftime("%s").to_i
        stop = (dt_now + (1.0 / 24.0)).strftime("%s").to_i
        expect {
          ActivityModel.new(name: name, scope: scope, start: start, stop: stop, kind: "COMMAND", data: {})
        }.to raise_error(ActivityInputError, /activity must be in the future/)
      end

      it "allows EXPIRE activities with start before now" do
        name = "foobar"
        scope = "scope"
        dt_now = DateTime.now
        start = (dt_now - (1.5 / 24.0)).strftime("%s").to_i
        stop = (dt_now + (1.0 / 24.0)).strftime("%s").to_i
        ActivityModel.new(name: name, scope: scope, start: start, stop: stop, kind: "EXPIRE", data: {})
      end
    end

    describe "update error" do
      it "raises error due to not created yet" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 0.5, stop: 1.0)
        start = activity.start + 10
        stop = activity.stop + 10
        expect {
          activity.update(start: start, stop: stop, kind: "COMMAND", data: {})
        }.to raise_error(ActivityError)
      end

      it "raises error due to update is overlapping time point" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 0.5)
        activity.create()
        model = generate_activity(name: name, scope: scope, start: 2.0)
        model.create()

        # First activity is 0.5 to 1.5 and second is 2.0 to 3.0
        # We add 3600 (1hr) + 1800 (30min) + 100 to the first activity
        # to place it inside the second
        new_start = activity.start + 5500
        new_stop = activity.stop + 5500
        expect {
          activity.update(start: new_start, stop: new_stop, kind: "COMMAND", data: {}, overlap: false)
        }.to raise_error(ActivityOverlapError)

        activity.update(start: new_start, stop: new_stop, kind: "COMMAND", data: {}, overlap: true)
        array = ActivityModel.all(name: name, scope: scope)
        expect(array.length).to eql(2)
        expect(array[0]["start"]).to eql(model.start)
        expect(array[1]["start"]).to eql(new_start)
      end
    end

    describe "update stop" do
      it "update the input parameters" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0)
        activity.create()
        stop = activity.stop + 100
        activity.update(start: activity.start, stop: stop, kind: "SCRIPT", data: {})
        expect(activity.start).to eql(activity.start)
        expect(activity.stop).to eql(stop)
        expect(activity.kind).to eql("script")
        expect(activity.data).not_to be_nil
        expect(activity.data).not_to include("test")
        expect(activity.events.empty?).to eql(false)
        expect(activity.events.length).to eql(2)
      end
    end

    describe "update both start and stop" do
      it "update the input parameters" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0)
        activity.create()
        og_start = activity.start
        new_start = activity.start + 100
        new_stop = activity.stop + 100
        activity.update(start: new_start, stop: new_stop, kind: "COMMAND", data: {})
        expect(activity.start).to eql(new_start)
        expect(activity.stop).to eql(new_stop)
        expect(activity.kind).to eql("command")
        expect(activity.data).not_to include("test")
        ret = ActivityModel.score(name: name, scope: scope, score: og_start)
        expect(ret).to be_nil
      end
    end

    describe "commit" do
      it "update the events and commit them to redis" do
        name = "foobar"
        scope = "scope"
        start = 1.0
        dt = DateTime.now.new_offset(0)
        start_time = dt + (start / 24.0)
        end_time = dt + ((start + 1) / 24.0)
        activity1 = ActivityModel.new(
          name: name,
          scope: scope,
          start: start_time.strftime("%s").to_i,
          stop: end_time.strftime("%s").to_i,
          kind: "RESERVE",
          data: {}
        )
        activity1.create()
        activity2 = ActivityModel.new(
          name: name,
          scope: scope,
          start: start_time.strftime("%s").to_i,
          stop: end_time.strftime("%s").to_i,
          kind: "COMMAND",
          data: {}
        )
        activity2.create()
        activities = ActivityModel.all(name: name, scope: scope)
        expect(activities.length).to eql(2)

        expect(activity1.fulfillment).to eql(false)
        expect(activity2.fulfillment).to eql(false)
        activity1.commit(status: "test", message: "message", fulfillment: true)
        expect(activity1.fulfillment).to eql(true)

        valid_commit = false
        activity1.events.each do |event|
          if event["event"] == "test"
            expect(event["message"]).to eql("message")
            expect(event["commit"]).to eql(true)
            valid_commit = true
          end
        end
        expect(valid_commit).to eql(true)

        activities = ActivityModel.all(name: name, scope: scope)
        expect(activities.length).to eql(2)
        expect(activities[0]["fulfillment"]).to eql(true)
        expect(activities[0]["kind"]).to eql('reserve')
        expect(activities[0]["events"].length).to eql(2)
        expect(activities[1]["fulfillment"]).to eql(false)
        expect(activities[1]["kind"]).to eql('command')
        expect(activities[1]["events"].length).to eql(1)
      end
    end

    describe "notify" do
      it "update the top of a change to the timeline" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0)
        activity.notify(kind: "new")
      end

      it "rescues errors in TimelineTopic" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0)
        allow(TimelineTopic).to receive(:write_activity).and_raise(StandardError)
        expect { activity.notify(kind: "new") }.to raise_error(ActivityError)
      end
    end

    describe "as_json" do
      it "encodes all the input parameters" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0)
        json = activity.as_json(:allow_nan => true)
        expect(json["start"]).to eql(activity.start)
        expect(json["stop"]).to eql(activity.stop)
        expect(json["kind"]).to eql(activity.kind)
        expect(json["data"]).not_to be_nil
      end
    end

    describe "from_json" do
      it "encodes all the input parameters" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1.0)
        model_hash = activity.as_json(:allow_nan => true)
        json = JSON.generate(model_hash)
        new_activity = ActivityModel.from_json(json, name: name, scope: scope)
        expect(activity.start).to eql(new_activity.start)
        expect(activity.stop).to eql(new_activity.stop)
        expect(activity.kind).to eql(new_activity.kind)
        expect(activity.data).to eql(new_activity.data)
      end
    end
  end
end
