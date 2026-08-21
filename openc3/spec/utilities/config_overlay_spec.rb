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
require "openc3/utilities/config_overlay"

module OpenC3
  describe ConfigOverlay do
    describe "cmd_tlm_overlay?" do
      it "flags cmd_tlm overlay names (admin required)" do
        expect(ConfigOverlay.cmd_tlm_overlay?("INST/cmd_tlm/tlm.txt")).to be true
        expect(ConfigOverlay.cmd_tlm_overlay?("INST/cmd_tlm/config/extra.txt")).to be true
      end

      it "allows non-cmd_tlm overlay names" do
        expect(ConfigOverlay.cmd_tlm_overlay?("INST/procedures/x.rb")).to be false
        expect(ConfigOverlay.cmd_tlm_overlay?("INST/screens/x.txt")).to be false
        expect(ConfigOverlay.cmd_tlm_overlay?("INST/tables/bin/table.bin")).to be false
        expect(ConfigOverlay.cmd_tlm_overlay?("__TEMP__/2026_01_01_00_00_00_000_temp.rb")).to be false
        # No area segment at all (e.g. a bare filename) is not the cmd_tlm subtree
        expect(ConfigOverlay.cmd_tlm_overlay?("script.rb")).to be false
      end

      it "fails closed on non-canonical names so the positional check cannot be bypassed" do
        expect(ConfigOverlay.cmd_tlm_overlay?("INST//cmd_tlm/x.txt")).to be true
        expect(ConfigOverlay.cmd_tlm_overlay?("INST/./cmd_tlm/x.txt")).to be true
        expect(ConfigOverlay.cmd_tlm_overlay?("INST/../cmd_tlm/x.txt")).to be true
        expect(ConfigOverlay.cmd_tlm_overlay?("/INST/procedures/x.rb")).to be true
        expect(ConfigOverlay.cmd_tlm_overlay?("INST/procedures/")).to be true
        expect(ConfigOverlay.cmd_tlm_overlay?("")).to be true
        expect(ConfigOverlay.cmd_tlm_overlay?(nil)).to be true
      end
    end

    describe "non_admin_writable_key?" do
      it "allows non-cmd_tlm targets_modified and tmp keys" do
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/targets_modified/INST/screens/poc.txt")).to be true
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/targets_modified/INST/procedures/x.rb")).to be true
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/tmp/foo.txt")).to be true
        # tmp is not target-structured, so cmd_tlm has no meaning there
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/tmp/INST/cmd_tlm/x.txt")).to be true
      end

      it "requires admin (returns false) for the cmd_tlm overlay" do
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/targets_modified/INST/cmd_tlm/tlm.txt")).to be false
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/targets_modified/INST/cmd_tlm/config/extra.txt")).to be false
      end

      it "requires admin for non-overlay areas" do
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/targets/INST/screens/x.txt")).to be false
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/target_archives/INST/x.zip")).to be false
      end

      it "fails closed on non-canonical keys so the positional check cannot be bypassed" do
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/targets_modified/INST//cmd_tlm/x.txt")).to be false
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/targets_modified/INST/./cmd_tlm/x.txt")).to be false
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/targets_modified/INST/../cmd_tlm/x.txt")).to be false
        expect(ConfigOverlay.non_admin_writable_key?("/DEFAULT/targets_modified/INST/screens/x.txt")).to be false
        expect(ConfigOverlay.non_admin_writable_key?("DEFAULT/targets_modified/INST/screens/")).to be false
        expect(ConfigOverlay.non_admin_writable_key?("")).to be false
        expect(ConfigOverlay.non_admin_writable_key?(nil)).to be false
      end
    end
  end
end
