# Discovery matcher fixtures

Each directory holds a `plugin.txt` and the `expected.json` that
`OpenC3::PluginModel.discovery_matchers` derives from it (see
`spec/models/plugin_model_spec.rb`). The OpenC3 Store computes the same matchers
when a plugin is uploaded and tests its implementation against these files, so
change them together with both implementations.
