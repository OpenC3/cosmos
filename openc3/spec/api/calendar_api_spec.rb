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
require 'openc3/api/calendar_api'
require 'openc3/models/timeline_model'
require 'openc3/models/activity_model'

module OpenC3
  describe Api do
    class CalendarApiTest
      include Api
    end

    let(:scope) { 'DEFAULT' }
    let(:timeline) { 'cal_test' }

    before(:each) do
      mock_redis()
      local_s3()
      @api = CalendarApiTest.new
      # MicroserviceModel.destroy in undeploy can be a no-op; stub it.
      allow_any_instance_of(MicroserviceModel).to receive(:destroy).and_return(nil)
    end

    def make_timeline(name: timeline, scope: 'DEFAULT')
      @api.create_timeline(name, scope: scope)
    end

    def future_window(offset_hours: 1, duration_hours: 1)
      now = DateTime.now.new_offset(0)
      start_dt = now + (offset_hours / 24.0)
      stop_dt = now + ((offset_hours + duration_hours) / 24.0)
      [start_dt, stop_dt]
    end

    describe 'list_timelines' do
      it 'returns an empty array when no timelines exist' do
        expect(@api.list_timelines(scope: scope)).to eql([])
      end

      it 'returns only timelines in the requested scope' do
        @api.create_timeline('alpha', scope: 'DEFAULT')
        @api.create_timeline('beta', scope: 'DEFAULT')
        @api.create_timeline('alpha', scope: 'OTHER')
        result = @api.list_timelines(scope: 'DEFAULT')
        names = result.map { |t| t['name'] }.sort
        expect(names).to eql(%w[alpha beta])
      end
    end

    describe 'create_timeline' do
      it 'creates and returns a timeline hash' do
        result = @api.create_timeline(timeline, scope: scope)
        expect(result['name']).to eql(timeline)
        expect(result['scope']).to eql(scope)
        expect(result['execute']).to be true
        expect(result['color']).to match(/\A#[0-9a-fA-F]{6}\z/)
      end

      it 'honors a supplied color' do
        result = @api.create_timeline(timeline, color: '#A0B1C2', scope: scope)
        expect(result['color']).to eql('#A0B1C2')
      end

      it 'rejects an invalid color' do
        expect {
          @api.create_timeline(timeline, color: 'not-a-color', scope: scope)
        }.to raise_error(TimelineInputError)
      end
    end

    describe 'get_timeline' do
      it 'returns nil when the timeline does not exist' do
        expect(@api.get_timeline('missing', scope: scope)).to be_nil
      end

      it 'returns the timeline hash when it exists' do
        @api.create_timeline(timeline, color: '#112233', scope: scope)
        result = @api.get_timeline(timeline, scope: scope)
        expect(result['name']).to eql(timeline)
        expect(result['color']).to eql('#112233')
      end
    end

    describe 'set_timeline_color' do
      it 'returns nil when the timeline does not exist' do
        expect(@api.set_timeline_color('missing', '#FF0000', scope: scope)).to be_nil
      end

      it 'updates the color' do
        @api.create_timeline(timeline, scope: scope)
        result = @api.set_timeline_color(timeline, '#445566', scope: scope)
        expect(result['color']).to eql('#445566')
        expect(@api.get_timeline(timeline, scope: scope)['color']).to eql('#445566')
      end

      it 'raises on invalid color values' do
        @api.create_timeline(timeline, scope: scope)
        expect {
          @api.set_timeline_color(timeline, 'red', scope: scope)
        }.to raise_error(TimelineInputError)
      end
    end

    describe 'set_timeline_execute' do
      it 'returns nil when the timeline does not exist' do
        expect(@api.set_timeline_execute('missing', false, scope: scope)).to be_nil
      end

      it 'toggles execute true/false using string values' do
        @api.create_timeline(timeline, scope: scope)
        expect(@api.set_timeline_execute(timeline, 'FALSE', scope: scope)['execute']).to be false
        expect(@api.set_timeline_execute(timeline, 'true', scope: scope)['execute']).to be true
      end
    end

    describe 'delete_timeline' do
      it 'returns nil when the timeline does not exist' do
        expect(@api.delete_timeline('missing', scope: scope)).to be_nil
      end

      it 'deletes an empty timeline' do
        @api.create_timeline(timeline, scope: scope)
        result = @api.delete_timeline(timeline, scope: scope)
        expect(result).to eql({ 'name' => timeline })
        expect(@api.get_timeline(timeline, scope: scope)).to be_nil
      end

      it 'refuses to delete a timeline with activities unless forced' do
        @api.create_timeline(timeline, scope: scope)
        start_dt, stop_dt = future_window
        @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt, scope: scope,
        )
        expect {
          @api.delete_timeline(timeline, scope: scope)
        }.to raise_error(TimelineError)
      end

      it 'force-deletes a timeline along with its activities' do
        @api.create_timeline(timeline, scope: scope)
        start_dt, stop_dt = future_window
        @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt, scope: scope,
        )
        result = @api.delete_timeline(timeline, force: true, scope: scope)
        expect(result).to eql({ 'name' => timeline })
      end
    end

    describe 'create_timeline_activity' do
      before(:each) { make_timeline }

      it 'creates an activity, accepting DateTime start/stop' do
        start_dt, stop_dt = future_window
        result = @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt,
          data: { 'cmd' => 'INST ABORT' }, scope: scope,
        )
        expect(result['kind']).to eql('command')
        expect(result['start']).to eql(start_dt.strftime('%s').to_i)
        expect(result['stop']).to eql(stop_dt.strftime('%s').to_i)
        expect(result['data']).to eql({ 'cmd' => 'INST ABORT' })
      end

      it 'accepts ISO-format strings for start/stop' do
        start_dt, stop_dt = future_window
        result = @api.create_timeline_activity(
          timeline, kind: 'SCRIPT', start: start_dt.iso8601, stop: stop_dt.iso8601,
          data: { 'script' => 'INST/foo.rb' }, scope: scope,
        )
        expect(result['kind']).to eql('script')
        expect(result['start']).to eql(start_dt.strftime('%s').to_i)
      end

      it 'accepts integer epoch values for start/stop' do
        start_dt, stop_dt = future_window
        result = @api.create_timeline_activity(
          timeline, kind: 'reserve',
          start: start_dt.strftime('%s').to_i, stop: stop_dt.strftime('%s').to_i,
          scope: scope,
        )
        expect(result['kind']).to eql('reserve')
      end

      it 'records the username from data on the audit event' do
        start_dt, stop_dt = future_window
        result = @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt,
          data: { 'username' => 'alice' }, scope: scope,
        )
        expect(result['events'].first['username']).to eql('alice')
      end

      it 'creates a recurring set of activities' do
        start_t = Time.now + 60
        stop_t = start_t + 1800
        recurring_end = start_t + (86400 * 3)
        recurring = { 'frequency' => '1', 'span' => 'days', 'end' => recurring_end.to_i }
        @api.create_timeline_activity(
          timeline, kind: 'COMMAND',
          start: start_t.to_i, stop: stop_t.to_i,
          data: { 'cmd' => 'INST ABORT' },
          recurring: recurring,
          scope: scope,
        )
        all = ActivityModel.all(name: timeline, scope: scope)
        expect(all.length).to eql(4)
      end

      it 'rejects activities with start in the past' do
        now = DateTime.now.new_offset(0)
        expect {
          @api.create_timeline_activity(
            timeline, kind: 'COMMAND',
            start: now - (1.0 / 24.0), stop: now,
            scope: scope,
          )
        }.to raise_error(ActivityInputError)
      end

      it 'rejects activities longer than MAX_DURATION' do
        now = DateTime.now.new_offset(0)
        expect {
          @api.create_timeline_activity(
            timeline, kind: 'COMMAND',
            start: now + (1.0 / 24.0), stop: now + 2.0,
            scope: scope,
          )
        }.to raise_error(ActivityInputError)
      end
    end

    describe 'update_timeline_activity' do
      before(:each) { make_timeline }

      it 'returns nil when the activity does not exist' do
        result = @api.update_timeline_activity(
          timeline, id: 0, kind: 'COMMAND', start: 0, stop: 0,
          uuid: 'no-such-uuid', scope: scope,
        )
        expect(result).to be_nil
      end

      it 'updates the activity start, stop, and kind' do
        start_dt, stop_dt = future_window(offset_hours: 1)
        created = @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt, scope: scope,
        )
        new_start, new_stop = future_window(offset_hours: 4)
        updated = @api.update_timeline_activity(
          timeline,
          id: created['start'],
          kind: 'SCRIPT',
          start: new_start, stop: new_stop,
          uuid: created['uuid'],
          data: { 'script' => 'foo.rb' },
          scope: scope,
        )
        expect(updated['kind']).to eql('script')
        expect(updated['start']).to eql(new_start.strftime('%s').to_i)
      end
    end

    describe 'get_timeline_activity' do
      before(:each) { make_timeline }

      it 'returns nil when the activity does not exist' do
        expect(@api.get_timeline_activity(timeline, 0, 'no-such-uuid', scope: scope)).to be_nil
      end

      it 'returns the matching activity' do
        start_dt, stop_dt = future_window
        created = @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt, scope: scope,
        )
        result = @api.get_timeline_activity(timeline, created['start'], created['uuid'], scope: scope)
        expect(result['uuid']).to eql(created['uuid'])
      end
    end

    describe 'get_timeline_activities' do
      before(:each) { make_timeline }

      it 'returns an empty array when no activities exist' do
        expect(@api.get_timeline_activities(timeline, scope: scope)).to eql([])
      end

      it 'returns activities within the default 7-day window' do
        start_dt, stop_dt = future_window(offset_hours: 1)
        @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt, scope: scope,
        )
        result = @api.get_timeline_activities(timeline, scope: scope)
        expect(result.length).to eql(1)
      end

      it 'honors explicit start/stop window arguments' do
        start_dt, stop_dt = future_window(offset_hours: 1)
        @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt, scope: scope,
        )
        # Window in the far future excludes our activity
        far_start = (DateTime.now.new_offset(0) + 30).iso8601
        far_stop = (DateTime.now.new_offset(0) + 31).iso8601
        result = @api.get_timeline_activities(timeline, start: far_start, stop: far_stop, scope: scope)
        expect(result).to eql([])
      end
    end

    describe 'delete_timeline_activity' do
      before(:each) { make_timeline }

      it 'returns 0 when no activity matches' do
        ret = @api.delete_timeline_activity(timeline, 0, 'no-such-uuid', scope: scope)
        expect(ret).to eql(0)
      end

      it 'removes a single activity' do
        start_dt, stop_dt = future_window
        created = @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt, scope: scope,
        )
        ret = @api.delete_timeline_activity(timeline, created['start'], created['uuid'], scope: scope)
        expect(ret).to eql(1)
        expect(@api.count_timeline_activities(timeline, scope: scope)).to eql(0)
      end
    end

    describe 'count_timeline_activities' do
      before(:each) { make_timeline }

      it 'returns 0 when there are none' do
        expect(@api.count_timeline_activities(timeline, scope: scope)).to eql(0)
      end

      it 'increments as activities are added' do
        start_dt, stop_dt = future_window(offset_hours: 1)
        @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt, scope: scope,
        )
        start_dt, stop_dt = future_window(offset_hours: 4)
        @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt, scope: scope,
        )
        expect(@api.count_timeline_activities(timeline, scope: scope)).to eql(2)
      end
    end

    describe 'commit_timeline_activity' do
      before(:each) { make_timeline }

      it 'returns nil when the activity does not exist' do
        result = @api.commit_timeline_activity(timeline, 0, 'no-such-uuid', status: 'done', scope: scope)
        expect(result).to be_nil
      end

      it 'appends an event to the activity' do
        start_dt, stop_dt = future_window
        created = @api.create_timeline_activity(
          timeline, kind: 'COMMAND', start: start_dt, stop: stop_dt, scope: scope,
        )
        result = @api.commit_timeline_activity(
          timeline, created['start'], created['uuid'],
          status: 'completed', message: 'finished', scope: scope,
        )
        expect(result['events'].length).to eql(2)
        last_event = result['events'].last
        expect(last_event['event']).to eql('completed')
        expect(last_event['message']).to eql('finished')
      end
    end

    describe '_cal_to_epoch' do
      it 'returns Integer values unchanged' do
        expect(@api.send(:_cal_to_epoch, 12345)).to eql(12345)
      end

      it 'truncates Floats' do
        expect(@api.send(:_cal_to_epoch, 12345.9)).to eql(12345)
      end

      it 'converts a numeric String to its integer form' do
        expect(@api.send(:_cal_to_epoch, '12345')).to eql(12345)
      end

      it 'converts an ISO-format String to epoch seconds' do
        dt = DateTime.new(2031, 4, 16, 1, 2, 3, '+00:00')
        expect(@api.send(:_cal_to_epoch, dt.iso8601)).to eql(dt.strftime('%s').to_i)
      end

      it 'converts a DateTime to epoch seconds' do
        dt = DateTime.new(2031, 4, 16, 1, 2, 3, '+00:00')
        expect(@api.send(:_cal_to_epoch, dt)).to eql(dt.strftime('%s').to_i)
      end

      it 'raises ArgumentError on unparseable strings' do
        expect { @api.send(:_cal_to_epoch, 'not-a-date') }.to raise_error(ArgumentError)
      end

      it 'raises ArgumentError on nil' do
        expect { @api.send(:_cal_to_epoch, nil) }.to raise_error(ArgumentError)
      end
    end
  end
end
