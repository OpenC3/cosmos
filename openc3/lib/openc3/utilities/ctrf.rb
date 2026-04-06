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

require 'openc3/version'
require 'date'

module OpenC3
  # Utility class for converting COSMOS script reports to CTRF (Common Test Report Format)
  # See https://ctrf.io/docs/category/specification
  class Ctrf
    # Convert a COSMOS plain text script report to CTRF JSON format
    # @param report_content [String] Plain text script report
    # @param version [String] Version string to include in CTRF output (defaults to OpenC3::VERSION)
    # @return [Hash] CTRF formatted report as a Ruby hash
    def self.convert_report(report_content, version: OpenC3::VERSION)
      lines = report_content.split("\n")
      tests = []
      summary = {}
      settings = {}
      in_settings = false
      last_result = nil
      in_summary = false

      lines.each do |line|
        next if line.nil?
        line_clean = line.strip

        if line_clean == 'Settings:'
          in_settings = true
          next
        end

        if in_settings
          if line_clean.include?('Manual')
            parts = line.split('=')
            settings[:manual] = parts[1].strip if parts[1]
            next
          elsif line_clean.include?('Pause on Error')
            parts = line.split('=')
            settings[:pauseOnError] = parts[1].strip if parts[1]
            next
          elsif line_clean.include?('Continue After Error')
            parts = line.split('=')
            settings[:continueAfterError] = parts[1].strip if parts[1]
            next
          elsif line_clean.include?('Abort After Error')
            parts = line.split('=')
            settings[:abortAfterError] = parts[1].strip if parts[1]
            next
          elsif line_clean.include?('Loop =')
            parts = line.split('=')
            settings[:loop] = parts[1].strip if parts[1]
            next
          elsif line_clean.include?('Break Loop On Error')
            parts = line.split('=')
            settings[:breakLoopOnError] = parts[1].strip if parts[1]
            in_settings = false
            next
          end
        end

        if line_clean == 'Results:'
          last_result = line_clean
          next
        end

        if last_result
          # The first line should always have a timestamp and what it is executing
          # Format: "2026-04-02T19:45:41.228209Z: Executing MySuite:ExampleGroup:script_2"
          if last_result == 'Results:' and line_clean.include?("Executing")
            # Split on first ': ' to separate timestamp from message
            timestamp_and_msg = line_clean.split(': ', 2)
            if timestamp_and_msg.length >= 2
              timestamp = timestamp_and_msg[0]
              begin
                summary[:startTime] = DateTime.parse(timestamp).to_time.to_f * 1000
              rescue Date::Error
                # Skip malformed timestamps
              end
            end
            last_result = line_clean
            next
          end

          # Format: "2026-04-02T19:45:44.041472Z: ExampleGroup:script_2:PASS"
          # Check if line contains a test result (but not Executing or Completed)
          if !line_clean.include?("Executing") && !line_clean.include?("Completed")
            # Try to parse as a test result line
            timestamp_and_msg = line_clean.split(': ', 2)
            if timestamp_and_msg.length >= 2
              result_string = timestamp_and_msg[1]
              # Must have at least 2 colons for group:name:status format
              result_parts = result_string.split(':')
              if result_parts.length >= 3
                # Get start time from last_result if it was an Executing line
                start_time = nil
                if last_result && last_result.include?("Executing")
                  last_timestamp_and_msg = last_result.split(': ', 2)
                  if last_timestamp_and_msg.length >= 2
                    begin
                      start_time = DateTime.parse(last_timestamp_and_msg[0]).to_time.to_f * 1000
                    rescue Date::Error
                      # Skip malformed timestamps
                    end
                  end
                end

                # Parse current line timestamp
                timestamp = timestamp_and_msg[0]
                begin
                  end_time = DateTime.parse(timestamp).to_time.to_f * 1000
                rescue Date::Error
                  last_result = line_clean
                  next # Skip lines with malformed timestamps
                end

                # Parse the test result: ExampleGroup:script_2:PASS
                suite_group = result_parts[0]
                name = result_parts[1]
                status = result_parts[2]

                format_status = case status
                when 'PASS'
                  'passed'
                when 'SKIP'
                  'skipped'
                when 'FAIL'
                  'failed'
                else
                  'unknown'
                end

                tests << {
                  name: "#{suite_group}:#{name}",
                  status: format_status,
                  duration: start_time ? (end_time - start_time) : 0,
                }
                last_result = line_clean
                next
              end
            end
          end

          # Format: "2026-04-02T19:45:44.044982Z: Completed MySuite:ExampleGroup:script_2"
          if line_clean.include?("Completed")
            timestamp_and_msg = line_clean.split(': ', 2)
            if timestamp_and_msg.length >= 2
              timestamp = timestamp_and_msg[0]
              begin
                summary[:stopTime] = DateTime.parse(timestamp).to_time.to_f * 1000
              rescue Date::Error
                # Skip malformed timestamps
              end
            end
            last_result = nil
            next
          end
        end

        if line_clean == '--- Test Summary ---'
          in_summary = true
          next
        end

        if in_summary
          if line_clean.include?("Total Tests")
            parts = line_clean.split(':')
            summary[:total] = parts[1].to_i if parts[1]
          end
          if line_clean.include?("Pass:")
            parts = line_clean.split(':')
            summary[:passed] = parts[1].to_i if parts[1]
          end
          if line_clean.include?("Skip:")
            parts = line_clean.split(':')
            summary[:skipped] = parts[1].to_i if parts[1]
          end
          if line_clean.include?("Fail:")
            parts = line_clean.split(':')
            summary[:failed] = parts[1].to_i if parts[1]
          end
        end
      end

      # Build CTRF report
      # See https://ctrf.io/docs/specification/root
      return {
        results: {
          # See https://ctrf.io/docs/specification/tool
          tool: {
            name: "COSMOS Script Runner",
            version: version,
          },
          # See https://ctrf.io/docs/specification/summary
          summary: {
            tests: summary[:total],
            passed: summary[:passed],
            failed: summary[:failed],
            pending: 0,
            skipped: summary[:skipped],
            other: 0,
            start: summary[:startTime],
            stop: summary[:stopTime],
          },
          # See https://ctrf.io/docs/specification/tests
          tests: tests,
          # See https://ctrf.io/docs/specification/extra
          extra: {
            manual: settings[:manual],
            pauseOnError: settings[:pauseOnError],
            continueAfterError: settings[:continueAfterError],
            abortAfterError: settings[:abortAfterError],
            loop: settings[:loop],
            breakLoopOnError: settings[:breakLoopOnError],
          },
        },
      }
    end
  end
end
