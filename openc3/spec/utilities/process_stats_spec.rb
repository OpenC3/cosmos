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

require "spec_helper"
require "openc3/utilities/process_stats"

module OpenC3
  describe ProcessStats do
    # A realistic /proc/<pid>/stat. proc(5) fields, in order:
    # pid comm state ppid pgrp session tty_nr tpgid flags minflt cminflt majflt
    # cmajflt utime stime cutime cstime priority nice num_threads itrealvalue
    # starttime vsize rss
    def stat_line(comm: '(ruby)', utime: 500, stime: 100, num_threads: 7,
                  starttime: 200_000, vsize: 123_456_789, rss: 4096)
      [
        1234, comm, 'S', 1, 1234, 1234, 0, -1, 4_194_304, 1000, 0, 0, 0,
        utime, stime, 0, 0, 20, 0, num_threads, 0, starttime, vsize, rss,
        # A few trailing fields so the line looks like the real thing
        18_446_744_073_709_551_615, 94_000_000, 94_000_000, 140_000_000
      ].join(' ')
    end

    before(:each) do
      # sysconf and /proc/uptime vary by machine; pin them so the math is checkable
      allow(ProcessStats).to receive(:supported?).and_return(true)
      allow(ProcessStats).to receive(:user_hz).and_return(100.0)
      allow(ProcessStats).to receive(:pagesize).and_return(4096)
      allow(ProcessStats).to receive(:boot_time).and_return(Time.at(1_000_000))
    end

    describe "sample" do
      it "parses cpu, memory and thread count out of /proc/<pid>/stat" do
        allow(File).to receive(:read).with("/proc/1234/stat").and_return(stat_line())
        allow(Time).to receive(:now).and_return(Time.at(1_002_000))

        stats = ProcessStats.new(1234)
        expect(stats.sample).to be true

        values = stats.values
        expect(values['num_threads']['value']).to eql 7
        expect(values['virtual_memory_bytes']['value']).to eql 123_456_789.0
        expect(values['resident_memory_bytes']['value']).to eql(4096 * 4096.0)

        # cpu_time = (utime 500 + stime 100) / 100 Hz = 6s
        # start_time = boot 1_000_000 + (starttime 200_000 / 100 Hz) = 1_002_000
        # elapsed = 1_002_000 - 1_002_000 = 0, so average stays at its initial 0
        expect(values['average_cpu_utilization']['value']).to eql 0.0
      end

      it "computes average cpu over the life of the process" do
        allow(File).to receive(:read).with("/proc/1234/stat").and_return(stat_line())
        # 12s after the process started, having used 6s of cpu => 50%
        allow(Time).to receive(:now).and_return(Time.at(1_002_012))

        stats = ProcessStats.new(1234)
        expect(stats.sample).to be true
        expect(stats.values['average_cpu_utilization']['value']).to be_within(0.001).of(0.5)
      end

      it "computes sample cpu from the delta between two samples" do
        allow(Time).to receive(:now).and_return(Time.at(1_002_010), Time.at(1_002_020))
        allow(File).to receive(:read).with("/proc/1234/stat").and_return(
          stat_line(utime: 500, stime: 100),
          # 250 more ticks of cpu (2.5s) over a 10s wall gap => 25%
          stat_line(utime: 700, stime: 150)
        )

        stats = ProcessStats.new(1234)
        stats.sample
        # No previous sample to diff against yet
        expect(stats.values['sample_cpu_utilization']['value']).to eql 0.0

        stats.sample
        expect(stats.values['sample_cpu_utilization']['value']).to be_within(0.001).of(0.25)
      end

      it "reports a process that has used no cpu at all, then picks up the delta" do
        allow(Time).to receive(:now).and_return(Time.at(1_002_010), Time.at(1_002_020))
        allow(File).to receive(:read).with("/proc/1234/stat").and_return(
          stat_line(utime: 0, stime: 0),
          stat_line(utime: 500, stime: 0)
        )

        stats = ProcessStats.new(1234)
        stats.sample
        expect(stats.values['average_cpu_utilization']['value']).to eql 0.0

        # An idle first sample must not wedge the delta calculation off
        stats.sample
        expect(stats.values['sample_cpu_utilization']['value']).to be_within(0.001).of(0.5)
      end

      it "handles a comm containing spaces and parens" do
        allow(File).to receive(:read).with("/proc/1234/stat")
          .and_return(stat_line(comm: '(my (odd) proc)'))
        allow(Time).to receive(:now).and_return(Time.at(1_002_012))

        stats = ProcessStats.new(1234)
        expect(stats.sample).to be true
        # Field offsets must survive a comm that would fool a naive split
        expect(stats.values['num_threads']['value']).to eql 7
        expect(stats.values['average_cpu_utilization']['value']).to be_within(0.001).of(0.5)
      end

      it "returns false when the process is gone" do
        allow(File).to receive(:read).with("/proc/1234/stat").and_raise(Errno::ENOENT)

        stats = ProcessStats.new(1234)
        expect(stats.sample).to be false
      end

      it "returns false on a truncated stat line" do
        allow(File).to receive(:read).with("/proc/1234/stat").and_return("1234 (ruby) S 1 1234")

        stats = ProcessStats.new(1234)
        expect(stats.sample).to be false
      end
    end

    describe "sysconf fallbacks" do
      it "never lets a failed sysconf produce Infinity or NaN" do
        # The real risk: a user_hz of 0 turns every cpu number into garbage
        allow(Etc).to receive(:sysconf).and_raise(NotImplementedError)
        ProcessStats.instance_variable_set(:@user_hz, nil)
        ProcessStats.instance_variable_set(:@pagesize, nil)
        allow(ProcessStats).to receive(:user_hz).and_call_original
        allow(ProcessStats).to receive(:pagesize).and_call_original

        expect(ProcessStats.user_hz).to eql ProcessStats::DEFAULT_USER_HZ
        expect(ProcessStats.pagesize).to eql ProcessStats::DEFAULT_PAGESIZE
        expect(ProcessStats.user_hz).to be > 0
      ensure
        ProcessStats.instance_variable_set(:@user_hz, nil)
        ProcessStats.instance_variable_set(:@pagesize, nil)
      end
    end
  end
end
