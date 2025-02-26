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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/models/timeline_model'
require 'openc3/models/activity_model'

module OpenC3
  describe TimelineModel do
    before(:each) do
      mock_redis()
    end

    def generate_activity(name:, scope:, start:)
      t = Time.now
      start_time = t + (start * 60)
      end_time = t + ((start + 10) * 60)
      start = start_time.to_i
      stop = end_time.to_i
      kind = "COMMAND"
      data = { "test" => "test" }
      ActivityModel.new(
        name: name,
        scope: scope,
        start: start,
        stop: stop,
        kind: kind,
        data: data
      )
    end

    describe "initialize" do
      it "only accepts color as hex" do
        expect { TimelineModel.new(name: "foo", scope: "scope", color: "red") }.to raise_error(TimelineError)
        expect { TimelineModel.new(name: "foo", scope: "scope", color: "#FF0000") }.to_not raise_error
      end
    end

    describe "self.get" do
      it "returns a timeline model" do
        scope = "scope"
        model = TimelineModel.new(name: "foo", scope: scope)
        model.create()
        model = TimelineModel.new(name: "bar", scope: scope)
        model.create()
        timeline = TimelineModel.get(name: "foo", scope: scope)
        expect(timeline.name).to_not be_nil()
        expect(timeline.scope).to_not be_nil()
        expect(timeline.updated_at).to_not be_nil()
      end
    end

    describe "self.all" do
      it "returns all the timeline and values" do
        scope = "scope"
        model = TimelineModel.new(name: "foo", scope: scope)
        model.create()
        model = TimelineModel.new(name: "bar", scope: scope)
        model.create()
        all = TimelineModel.all()
        expect(all.empty?).to eql(false)
        expect(all.length).to eql(2)
        expect(all).to have_key("scope__TIMELINE__foo")
        expect(all).to have_key("scope__TIMELINE__bar")
      end
    end

    describe "self.all" do
      it "returns all the timeline and values" do
        model = TimelineModel.new(name: "test", scope: "a")
        model.create()
        model = TimelineModel.new(name: "test", scope: "b")
        model.create()
        all = TimelineModel.all()
        expect(all.empty?).to eql(false)
        expect(all.length).to eql(2)
        expect(all).to have_key("a__TIMELINE__test")
        expect(all).to have_key("b__TIMELINE__test")
      end
    end

    describe "self.names" do
      it "returns all the timeline names" do
        model = TimelineModel.new(name: "foo", scope: "SCOPE")
        model.create()
        model = TimelineModel.new(name: "bar", scope: "DEFAULT")
        model.create()
        names = TimelineModel.names()
        expect(names.empty?).to eql(false)
        expect(names.length).to eql(2)
        expect(names[0]).to include("bar")
        expect(names[1]).to include("foo")
      end
    end

    describe "self.delete" do
      it "delete force timeline" do
        name = "foobar"
        scope = "scope"
        activity = generate_activity(name: name, scope: scope, start: 1)
        activity.create()
        ret = TimelineModel.delete(name: name, scope: scope, force: true)
        expect(ret).to eql(name)
        all = TimelineModel.all
        expect(all.empty?).to eql(true)
        expect(all.length).to eql(0)
      end
    end

    describe "self.delete" do
      it "delete an empty timeline" do
        name = "foobar"
        scope = "scope"
        ret = TimelineModel.delete(name: name, scope: scope)
        expect(ret).to eql(name)
        activity = generate_activity(name: name, scope: scope, start: 1)
        activity.create()
        score = activity.start
        ret = ActivityModel.destroy(name: name, scope: scope, score: score, uuid: activity.uuid)
        expect(ret).to eql(1)
        ret = TimelineModel.delete(name: name, scope: scope)
        expect(ret).to eql(name)
        all = TimelineModel.all
        expect(all.empty?).to eql(true)
        expect(all.length).to eql(0)
      end
    end

    describe "self.delete error" do
      it "tries to delete a timeline with activities on it" do
        name = "foobar"
        scope = "scope"
        TimelineModel.delete(name: name, scope: scope)
        activity = generate_activity(name: name, scope: scope, start: 1)
        activity.create()
        expect {
          TimelineModel.delete(name: name, scope: scope)
        }.to raise_error(TimelineError)
      end
    end

    describe "notify" do
      it "adds a message to notify of a new timeline" do
        name = "foobar"
        scope = "scope"
        model = TimelineModel.new(name: name, scope: scope)
        model.create()
        model.notify(kind: "SCRIPT")
      end
    end

    describe "deploy" do
      it "generates a new microservice and topic" do
        s3 = instance_double("Aws::S3::Client")
        allow(Aws::S3::Client).to receive(:new).and_return(s3)
        name = "foobar"
        scope = "scope"
        model = TimelineModel.new(name: name, scope: scope)
        model.create()
        model.deploy()
      end
    end
  end
end
