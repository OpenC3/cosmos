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

require 'etc'

# See: https://man7.org/linux/man-pages/man5/proc.5.html

module OpenC3
  # Samples CPU and memory for an arbitrary pid out of /proc/<pid>/stat.
  #
  # Every microservice is bootstrapped by plugin_microservice.rb, which exec()s
  # the configured cmd. exec replaces the process image, so everything the
  # bootstrap set up - including the Metric update thread - is gone. A
  # microservice whose cmd is itself an OpenC3::Microservice builds a new Metric
  # and keeps reporting, but a plugin that runs a Rails app, a Python script or
  # any other binary never loads the OpenC3 libraries and so can never report on
  # itself. Sampling by pid lets the operator report on behalf of those
  # processes without requiring anything of the plugin.
  class ProcessStats
    # /proc/<pid>/stat field offsets, 0 based, after the comm field has been
    # collapsed to a single token. proc(5) numbers these fields from 1.
    UTIME_INDEX = 13
    STIME_INDEX = 14
    NUM_THREADS_INDEX = 19
    STARTTIME_INDEX = 21
    VSIZE_INDEX = 22
    RSS_INDEX = 23

    # Near universal Linux default. Only used if sysconf can't answer - a zero
    # here would turn every CPU number into Infinity or NaN.
    DEFAULT_USER_HZ = 100.0
    DEFAULT_PAGESIZE = 4096

    attr_reader :pid

    class << self
      # Whether this kernel exposes the procfs data we need at all. macOS and
      # Windows don't, and neither do some hardened container runtimes.
      def supported?
        return @supported unless @supported.nil?
        @supported = File.exist?('/proc/self/stat')
      rescue Exception
        @supported = false
      end

      def pagesize
        @pagesize ||= sysconf(:SC_PAGESIZE, DEFAULT_PAGESIZE)
      end

      def user_hz
        @user_hz ||= sysconf(:SC_CLK_TCK, DEFAULT_USER_HZ).to_f
      end

      # Wall time the machine booted. /proc/<pid>/stat reports starttime
      # relative to boot, so this is what turns it into an absolute time.
      def boot_time
        @boot_time ||= begin
          Time.now - File.read('/proc/uptime').split[0].to_f
        rescue Exception
          Time.now
        end
      end

      private

      def sysconf(name, default)
        return default unless Etc.const_defined?(name)

        value = Etc.sysconf(Etc.const_get(name))
        (value and value > 0) ? value : default
      rescue Exception
        default
      end
    end

    def initialize(pid)
      @pid = pid
      @start_time = nil
      @last_sample_time = nil
      # nil rather than 0 so a process that has genuinely burned no CPU yet
      # still starts producing sample deltas on the next pass
      @cpu_time = nil
      @average_cpu_utilization = 0.0
      @sample_cpu_utilization = 0.0
      @virtual_memory_bytes = 0.0
      @resident_memory_bytes = 0.0
      @num_threads = 0
    end

    # @return [Boolean] whether a usable sample was taken
    def sample
      stat = read_stat()
      return false unless stat

      fields = split_stat(stat)
      return false if fields.length <= RSS_INDEX

      sample_time = Time.now
      user_hz = self.class.user_hz
      cpu_time = (fields[UTIME_INDEX].to_f + fields[STIME_INDEX].to_f) / user_hz
      @start_time ||= self.class.boot_time + (fields[STARTTIME_INDEX].to_f / user_hz)

      if @cpu_time and @last_sample_time
        time_delta = sample_time - @last_sample_time
        @sample_cpu_utilization = (cpu_time - @cpu_time) / time_delta if time_delta > 0
      end
      @cpu_time = cpu_time
      @last_sample_time = sample_time

      elapsed = sample_time - @start_time
      @average_cpu_utilization = cpu_time / elapsed if elapsed > 0

      @num_threads = fields[NUM_THREADS_INDEX].to_i
      @virtual_memory_bytes = fields[VSIZE_INDEX].to_f
      @resident_memory_bytes = fields[RSS_INDEX].to_f * self.class.pagesize
      true
    end

    # Shaped like OpenC3::Metric's internal data hash so it can be handed
    # straight to MetricModel.
    def values
      {
        'average_cpu_utilization' => { 'value' => @average_cpu_utilization, 'type' => 'gauge', 'unit' => 'ratio' },
        'sample_cpu_utilization' => { 'value' => @sample_cpu_utilization, 'type' => 'gauge', 'unit' => 'ratio' },
        'virtual_memory_bytes' => { 'value' => @virtual_memory_bytes, 'type' => 'gauge', 'unit' => 'bytes' },
        'resident_memory_bytes' => { 'value' => @resident_memory_bytes, 'type' => 'gauge', 'unit' => 'bytes' },
        'num_threads' => { 'value' => @num_threads, 'type' => 'gauge' },
      }
    end

    private

    def read_stat
      File.read("/proc/#{@pid}/stat")
    rescue SystemCallError, IOError
      # The process can exit between being listed and being read
      nil
    end

    # The comm field is wrapped in parens and may itself contain spaces and
    # parens, so split from the last close paren rather than trying to match it.
    # Two placeholders stand in for pid and comm to keep the proc(5) offsets.
    def split_stat(stat)
      close = stat.rindex(')')
      return [] unless close

      ['0', '0'].concat(stat[(close + 1)..-1].to_s.split)
    end
  end
end
