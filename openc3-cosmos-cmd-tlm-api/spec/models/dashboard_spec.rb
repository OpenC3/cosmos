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

RSpec.describe Dashboard, :type => :model do
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
        ['INST/dashboards/dash1.txt', 'INST/dashboards/dash2.txt*']
      )
      expect(Dashboard.all('DEFAULT')).to eql(['INST/dashboards/dash1.txt', 'INST/dashboards/dash2.txt'])
    end

    it "keeps a '*' which is part of the filename" do
      allow(OpenC3::TargetFile).to receive(:all).and_return(
        ['INST/dashboards/das*h.txt', 'INST/dashboards/das*h.txt*']
      )
      # Both list entries resolve to the same underlying file
      expect(Dashboard.all('DEFAULT')).to eql(['INST/dashboards/das*h.txt', 'INST/dashboards/das*h.txt'])
    end
  end

  describe "self.find" do
    it "downcases the dashboard name and requests the dashboard file" do
      expect(Dashboard).to receive(:body).with('DEFAULT', 'INST/dashboards/overview.txt').and_return('DASHBOARD')
      expect(Dashboard.find('DEFAULT', 'INST', 'OVERVIEW')).to eql('DASHBOARD')
    end

    it "strips the modified marker from the dashboard name" do
      expect(Dashboard).to receive(:body).with('DEFAULT', 'INST/dashboards/overview.txt').and_return('DASHBOARD')
      expect(Dashboard.find('DEFAULT', 'INST', 'OVERVIEW*')).to eql('DASHBOARD')
    end

    it "keeps a '*' which is part of the dashboard name" do
      expect(Dashboard).to receive(:body).with('DEFAULT', 'INST/dashboards/over*view.txt').and_return('DASHBOARD')
      expect(Dashboard.find('DEFAULT', 'INST', 'OVER*VIEW*')).to eql('DASHBOARD')
    end

    it "returns nil if the dashboard does not exist" do
      expect(Dashboard).to receive(:body).with('DEFAULT', 'INST/dashboards/nope.txt').and_return(nil)
      expect(Dashboard.find('DEFAULT', 'INST', 'NOPE')).to be_nil
    end
  end

  describe "self.destroy" do
    it "downcases the dashboard name and deletes the dashboard file" do
      expect(OpenC3::TargetFile).to receive(:destroy).with('DEFAULT', 'INST/dashboards/overview.txt')
      Dashboard.destroy('DEFAULT', 'INST', 'OVERVIEW')
    end
  end
end
