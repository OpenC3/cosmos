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

  describe "self.summary" do
    it "reads the title, the dashboard's icon and color, and counts panels" do
      text = <<~DOC
        # A comment
        DASHBOARD "INST Overview"
          SETTING ICON mdi-satellite-variant
          SETTING COLOR "#938bdb"
        PANEL STAT 0 0 3 4 "Temp"
          ITEM INST HEALTH_STATUS TEMP1
          SETTING COLOR "#ffffff"
        END
        PANEL GRAPH 3 0 3 4
          SETTING ICON mdi-ignored
        END
      DOC
      expect(Dashboard.summary(text)).to eql(
        { 'title' => 'INST Overview', 'icon' => 'mdi-satellite-variant', 'color' => '#938bdb', 'panels' => 2 }
      )
    end

    it "leaves out what the dashboard doesn't set" do
      expect(Dashboard.summary("PANEL STAT 0 0 3 4\nEND\n")).to eql(
        { 'title' => nil, 'icon' => nil, 'color' => nil, 'panels' => 1 }
      )
      expect(Dashboard.summary('DASHBOARD Plain')['title']).to eql('Plain')
    end
  end

  describe "self.summaries" do
    before(:each) do
      allow(OpenC3::TargetModel).to receive(:names).with(scope: 'DEFAULT').and_return(['INST'])
      allow(OpenC3::TargetFile).to receive(:all).and_return(
        ['INST/dashboards/dash1.txt', 'INST/dashboards/gone.txt']
      )
    end

    it "summarizes each readable dashboard with its path" do
      allow(Dashboard).to receive(:body).with('DEFAULT', 'INST/dashboards/dash1.txt').and_return("DASHBOARD \"One\"\nPANEL STAT 0 0 3 4\nEND\n")
      allow(Dashboard).to receive(:body).with('DEFAULT', 'INST/dashboards/gone.txt').and_return(nil)
      expect(Dashboard.summaries('DEFAULT')).to eql(
        [{ 'path' => 'INST/dashboards/dash1.txt', 'title' => 'One', 'icon' => nil, 'color' => nil, 'panels' => 1 }]
      )
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

  describe "self.path" do
    it "rejects names that resolve outside the target" do
      expect { Dashboard.path('.', 'x') }.to raise_error(ArgumentError)
      expect { Dashboard.path('..', 'x') }.to raise_error(ArgumentError)
      expect { Dashboard.path('INST', '../../x') }.to raise_error(ArgumentError)
      expect(Dashboard.path('INST', 'OVERVIEW*')).to eql 'INST/dashboards/overview.txt'
    end
  end

  describe "self.destroy" do
    it "downcases the dashboard name and deletes the dashboard file" do
      expect(OpenC3::TargetFile).to receive(:destroy).with('DEFAULT', 'INST/dashboards/overview.txt')
      Dashboard.destroy('DEFAULT', 'INST', 'OVERVIEW')
    end
  end
end
