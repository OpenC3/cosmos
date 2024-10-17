# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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
ENV['OPENC3_NO_MIGRATE'] = 'true'
require 'openc3/migrations/20240915000000_activity_uuid'

module OpenC3
  describe ActivityUuid do
    before(:each) do
      mock_redis()
    end

    it 'should add uuid to activities' do
      scopes = %w(DEFAULT OTHER)
      timelines = %w(timeline1 timeline2)
      scopes.each do |scope|
        model = ScopeModel.new(name: scope)
        model.create()

        timelines.each do |name|
          model = TimelineModel.new(name: name, scope: scope)
          model.create()

          start = Time.now.to_i + 10
          model1 = ActivityModel.new(
            name: name,
            scope: scope,
            start: start,
            stop: start + 10,
            kind: 'RESERVE',
            data: {}
          )
          model1.create()
          # Create another activity with the same start time
          model2 = ActivityModel.new(
            name: name,
            scope: scope,
            start: start,
            stop: start + 10,
            kind: 'COMMAND',
            data: {'key' => 'val2'}
          )
          model2.create()
          # Duplicate the activities without a uuid
          ActivityModel.all(name: name, scope: scope).each do |activity|
            activity.delete('uuid')
            Store.zadd("#{scope}#{ActivityModel::PRIMARY_KEY}__#{name}", activity['start'], JSON.generate(activity))
          end
          expect(ActivityModel.all(name: name, scope: scope).length).to eql 4
        end
      end

      before = []
      scopes.each do |scope|
        timelines.each do |name|
          before.concat(ActivityModel.all(name: name, scope: scope))
        end
      end
      expect(before.length).to eql(scopes.length * timelines.length * 4)

      # Run the migration
      ActivityUuid.run()

      after = []
      scopes.each do |scope|
        timelines.each do |name|
          after.concat(ActivityModel.all(name: name, scope: scope))
        end
      end
      # Check that the activities have not been changed
      before.each_with_index do |activity, index|
        activity.keys.each do |key|
          expect(activity[key]).to eql after[index][key]
        end
      end
      # Check that the activities have been updated with a uuid
      after.each do |activity|
        expect(activity['uuid']).not_to be_nil
      end
    end
  end
end
