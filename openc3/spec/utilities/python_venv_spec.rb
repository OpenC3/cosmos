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
require "openc3/utilities/python_venv"

module OpenC3
  describe PythonVenv do
    describe ".configure_for_script" do
      it "returns nil without changing the environment when no venv is configured" do
        environment = {"EXISTING" => "value"}
        allow(TargetModel).to receive(:get).with(name: "INST", scope: "DEFAULT").and_return(nil)

        expect(PythonVenv.configure_for_script(environment, name: "INST/procedures/test.py", scope: "DEFAULT")).to be_nil
        expect(environment).to eq({"EXISTING" => "value"})
      end

      it "configures and returns the resolved venv" do
        environment = {}
        target_info = {"plugin" => "demo-plugin"}
        allow(TargetModel).to receive(:get).with(name: "INST", scope: "DEFAULT").and_return(target_info)
        allow(File).to receive(:directory?).with("/gems/plugin_venvs/DEFAULT__demo-plugin/.venv").and_return(true)
        expect(PythonVenv).to receive(:configure_environment).with(
          environment,
          "/gems/plugin_venvs/DEFAULT__demo-plugin/.venv"
        ).and_return(environment)

        result = PythonVenv.configure_for_script(environment, name: "inst/procedures/test.py", scope: "DEFAULT")

        expect(result).to eq("/gems/plugin_venvs/DEFAULT__demo-plugin/.venv")
      end

      it "returns nil when target metadata has no plugin" do
        allow(TargetModel).to receive(:get).with(name: "INST", scope: "DEFAULT").and_return({})

        result = PythonVenv.configure_for_script({}, name: "INST/test.py", scope: "DEFAULT")

        expect(result).to be_nil
      end

      it "uses the supplied venv for a temporary script" do
        environment = {}
        expect(TargetModel).not_to receive(:get)
        allow(File).to receive(:directory?).with("/gems/plugin_venvs/DEFAULT__demo/.venv").and_return(true)
        allow(PythonVenv).to receive(:configure_environment).and_return(environment)

        result = PythonVenv.configure_for_script(
          environment,
          name: "__TEMP__/test.py",
          scope: "DEFAULT",
          python_venv: "DEFAULT__demo"
        )

        expect(result).to eq("/gems/plugin_venvs/DEFAULT__demo/.venv")
      end

      it "strips directory components from a temporary script venv" do
        environment = {}
        allow(File).to receive(:directory?).with("/gems/plugin_venvs/DEFAULT__demo/.venv").and_return(true)
        allow(PythonVenv).to receive(:configure_environment).and_return(environment)

        result = PythonVenv.configure_for_script(
          environment,
          name: "__TEMP__/test.py",
          scope: "DEFAULT",
          python_venv: "../../DEFAULT__demo"
        )

        expect(result).to eq("/gems/plugin_venvs/DEFAULT__demo/.venv")
      end

      it "returns nil when a temporary script venv does not exist" do
        allow(File).to receive(:directory?).with("/gems/plugin_venvs/missing/.venv").and_return(false)

        result = PythonVenv.configure_for_script(
          {},
          name: "__TEMP__/test.py",
          scope: "DEFAULT",
          python_venv: "missing"
        )

        expect(result).to be_nil
      end

      it "checks target metadata when a temporary script has no supplied venv" do
        allow(TargetModel).to receive(:get).with(name: "__TEMP__", scope: "DEFAULT").and_return(nil)

        result = PythonVenv.configure_for_script({}, name: "__TEMP__/test.py", scope: "DEFAULT")

        expect(result).to be_nil
      end

      it "logs resolution errors and falls back to the system environment" do
        allow(TargetModel).to receive(:get).and_raise("metadata unavailable")
        expect(Logger).to receive(:debug).with(
          "Could not resolve plugin venv for script 'INST/test.py': metadata unavailable"
        )

        result = PythonVenv.configure_for_script({}, name: "INST/test.py", scope: "DEFAULT")

        expect(result).to be_nil
      end
    end

    describe ".configure_environment" do
      before(:each) do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("PATH", "").and_return("/usr/bin")
      end

      it "sets the venv variables and site-packages path" do
        environment = {}
        allow(ENV).to receive(:fetch).with("PYTHONPATH", "").and_return("")
        allow(Dir).to receive(:glob).with("/venv/lib/python*/site-packages").and_return(
          ["/venv/lib/python3.12/site-packages"]
        )

        result = PythonVenv.configure_environment(environment, "/venv")

        expect(result).to equal(environment)
        expect(environment).to eq(
          "VIRTUAL_ENV" => "/venv",
          "PATH" => "/venv/bin:/usr/bin",
          "PYTHONUSERBASE" => "/venv",
          "PYTHONPATH" => "/venv/lib/python3.12/site-packages"
        )
      end

      it "prepends site-packages to an existing Python path" do
        environment = {}
        allow(ENV).to receive(:fetch).with("PYTHONPATH", "").and_return("/shared/python")
        allow(Dir).to receive(:glob).with("/venv/lib/python*/site-packages").and_return(
          ["/venv/lib/python3.12/site-packages"]
        )

        PythonVenv.configure_environment(environment, "/venv")

        expect(environment["PYTHONPATH"]).to eq("/venv/lib/python3.12/site-packages:/shared/python")
      end

      it "clears Python path when site-packages and an existing path are absent" do
        environment = {"PYTHONPATH" => "stale"}
        allow(ENV).to receive(:fetch).with("PYTHONPATH", "").and_return("")
        allow(Dir).to receive(:glob).with("/venv/lib/python*/site-packages").and_return([])

        PythonVenv.configure_environment(environment, "/venv")

        expect(environment["PYTHONPATH"]).to be_nil
      end

      it "preserves an existing Python path when site-packages is absent" do
        environment = {}
        allow(ENV).to receive(:fetch).with("PYTHONPATH", "").and_return("/shared/python")
        allow(Dir).to receive(:glob).with("/venv/lib/python*/site-packages").and_return([])

        PythonVenv.configure_environment(environment, "/venv")

        expect(environment["PYTHONPATH"]).to eq("/shared/python")
      end
    end

    describe ".plugin_venv_path" do
      it "sanitizes the scope and plugin name" do
        expected_path = "/gems/plugin_venvs/MY_SCOPE__demo_plugin_1_0/.venv"
        allow(File).to receive(:directory?).with(expected_path).and_return(true)

        result = PythonVenv.plugin_venv_path(scope: "MY SCOPE", plugin_name: "demo/plugin@1.0")

        expect(result).to eq(expected_path)
      end

      it "returns nil when the plugin venv does not exist" do
        allow(File).to receive(:directory?).with("/gems/plugin_venvs/DEFAULT__missing/.venv").and_return(false)

        result = PythonVenv.plugin_venv_path(scope: "DEFAULT", plugin_name: "missing")

        expect(result).to be_nil
      end
    end
  end
end
