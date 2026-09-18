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

require 'rails_helper'
require 'openc3/utilities/target_file'

RSpec.describe Screen, :type => :model do
  before(:each) do
    mock_redis()
    ENV.delete('OPENC3_LOCAL_MODE')
  end

  describe "self.all" do
    before(:each) do
      allow(OpenC3::TargetModel).to receive(:names).with(scope: 'DEFAULT').and_return(['INST'])
    end

    it "strips the modified marker from the returned names" do
      allow(OpenC3::TargetFile).to receive(:all).and_return(
        ['INST/screens/screen1.txt', 'INST/screens/screen2.txt*']
      )
      expect(Screen.all('DEFAULT')).to eql(['INST/screens/screen1.txt', 'INST/screens/screen2.txt'])
    end

    it "keeps a '*' which is part of the filename" do
      allow(OpenC3::TargetFile).to receive(:all).and_return(
        ['INST/screens/scr*een.txt', 'INST/screens/scr*een.txt*']
      )
      # Both list entries resolve to the same underlying file
      expect(Screen.all('DEFAULT')).to eql(['INST/screens/scr*een.txt', 'INST/screens/scr*een.txt'])
    end
  end

  describe "self.find" do
    it "downcases the screen name and requests the screen file" do
      expect(Screen).to receive(:body).with('DEFAULT', 'INST/screens/adcs.txt').and_return('SCREEN')
      expect(Screen.find('DEFAULT', 'INST', 'ADCS')).to eql('SCREEN')
    end

    it "strips the modified marker from the screen name" do
      expect(Screen).to receive(:body).with('DEFAULT', 'INST/screens/adcs.txt').and_return('SCREEN')
      expect(Screen.find('DEFAULT', 'INST', 'ADCS*')).to eql('SCREEN')
    end

    it "keeps a '*' which is part of the screen name" do
      expect(Screen).to receive(:body).with('DEFAULT', 'INST/screens/ad*cs.txt').and_return('SCREEN')
      expect(Screen.find('DEFAULT', 'INST', 'AD*CS*')).to eql('SCREEN')
    end

    it "returns nil if the screen does not exist" do
      expect(Screen).to receive(:body).with('DEFAULT', 'INST/screens/nope.txt').and_return(nil)
      expect(Screen.find('DEFAULT', 'INST', 'NOPE')).to be_nil
    end
  end

  describe "self.destroy" do
    it "downcases the screen name and deletes the screen file" do
      expect(OpenC3::TargetFile).to receive(:destroy).with('DEFAULT', 'INST/screens/adcs.txt')
      Screen.destroy('DEFAULT', 'INST', 'ADCS')
    end
  end
end
