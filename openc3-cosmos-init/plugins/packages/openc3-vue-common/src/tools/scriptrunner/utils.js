/**
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
*/

export function detectLanguage(text) {
  let rubyRegex1 = /^\s*(require|load|puts) /
  let pythonRegex1 = /^\s*(import|from) /
  let rubyRegex2 = /^\s*end\s*$/
  let pythonRegex2 = /^\s*(if|def|while|else|elif|class).*:\s*$/
  let pythonRegex3 = /\(f"/ // f strings
  // Since python types are defined like "def method(string: str):"
  // we make sure the line doesn't end in ':' which indicates Python
  // (?!:)$ is a negative lookahead to ensure it doesn't end in ':'
  let rubyRegex3 = /\(.*\w+:\s+.+\)(?!:)$/ // named parameters
  let lines = text.split('\n')
  for (let line of lines) {
    if (line.match(rubyRegex1)) {
      return 'ruby'
    }
    if (line.match(pythonRegex1)) {
      return 'python'
    }
    if (line.match(rubyRegex2)) {
      return 'ruby'
    }
    if (line.match(pythonRegex2)) {
      return 'python'
    }
    if (line.match(pythonRegex3)) {
      return 'python'
    }
    if (line.match(rubyRegex3)) {
      return 'ruby'
    }
  }
  return 'unknown' // otherwise unknown
}

export const pythonTestSuiteText = `from openc3.script.suite import Suite, Group

# Group class name should indicate what the scripts are testing
class Power(Group):
  # Methods beginning with script_ are added to Script dropdown
  def script_power_on(self):
    # Using Group.print adds the output to the Test Report
    # This can be useful for requirements verification, QA notes, etc
    Group.print("Verifying requirement SR-1")
    self.configure()

  # Other methods are not added to Script dropdown
  def configure(self):
    pass

  def setup(self):
    # Run when Group Setup button is pressed
    # Run before all scripts when Group Start is pressed
    pass

  def teardown(self):
    # Run when Group Teardown button is pressed
    # Run after all scripts when Group Start is pressed
    pass

class TestSuite(Suite):
  def __init__(self):
    self.add_group(Power)

  def setup(self):
    # Run when Suite Setup button is pressed
    # Run before all groups when Suite Start is pressed
    pass

  def teardown(self):
    # Run when Suite Teardown button is pressed
    # Run after all groups when Suite Start is pressed
    pass
`

export const rubyTestSuiteText = `require 'openc3/script/suite.rb'

# Group class name should indicate what the scripts are testing
class Power < OpenC3::Group
  # Methods beginning with script_ are added to Script dropdown
  def script_power_on
    # Using OpenC3::Group.puts adds the output to the Test Report
    # This can be useful for requirements verification, QA notes, etc
    OpenC3::Group.puts "Verifying requirement SR-1"
    configure()
  end

  # Other methods are not added to Script dropdown
  def configure
  end

  def setup
    # Run when Group Setup button is pressed
    # Run before all scripts when Group Start is pressed
  end

  def teardown
    # Run when Group Teardown button is pressed
    # Run after all scripts when Group Start is pressed
  end
end

class TestSuite < OpenC3::Suite
  def initialize
    add_group('Power')
  end
  def setup
    # Run when Suite Setup button is pressed
    # Run before all groups when Suite Start is pressed
  end
  def teardown
    # Run when Suite Teardown button is pressed
    # Run after all groups when Suite Start is pressed
  end
end
`
