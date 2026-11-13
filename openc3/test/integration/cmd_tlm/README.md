# Cmd/Tlm Processing Benchmark

Benchmarks how long `PacketConfig` takes to process a very large command and
telemetry definition, in both Ruby and Python.

## Generate the definition

From the `openc3` directory:

```bash
ruby test/integration/cmd_tlm/generate_cmd_tlm.rb
```

By default this writes `generated/targets/BIG/cmd_tlm/{tlm.txt,cmd.txt,limits_groups.txt}`
(about 55 MB, gitignored) containing:

- 500 telemetry packets with 125,000 items and 500,000 states
  (4 states per item). Packet and item descriptions are 50 to 250 characters.
- 500 command packets with 125,000 parameters, also with 50 to 250
  character packet and parameter descriptions.
- 1,001 limits groups nested vehicle > payload > subsystem > box > board
  containing 25,000 telemetry items, half with LIMITS and half with GREEN,
  YELLOW and RED states.

The defaults are sized so the installed plugin fits in a 16 GB Docker VM. Each
of the target's microservices loads the whole definition (about 1.1 KB per
telemetry item) and QuestDB keeps a writer open for 10 minutes after each write
to a table, about 2.6 MB for a 250 item packet. The earlier 4x larger
definition (`--tlm-packets 2000 --tlm-items 500000 --tlm-states 2000000
--cmd-packets 2000 --cmd-params 500000 --limits-group-items 100000`) is fine
for benchmarking `PacketConfig` but made QuestDB run out of memory when installed.

Each packet starts with an ID item/parameter, which counts toward the totals.
Output is deterministic for a given `--seed`. Run with `--help` to change any
of the counts, e.g. for a quick smoke test:

```bash
ruby test/integration/cmd_tlm/generate_cmd_tlm.rb --tlm-packets 20 --tlm-items 5000 \
  --tlm-states 20000 --cmd-packets 20 --cmd-params 1500 --limits-group-items 1000
```

## Install as a plugin

The output directory is also a complete plugin (`plugin.txt`, gemspec,
`Rakefile`, etc.) so the target can be installed into an operational COSMOS.
Pass `--language python` to generate a Python target and interface instead of
the default Ruby one. The interface is a TCP client to
`host.docker.internal:8080` that doesn't need a server; it makes COSMOS start
the interface and decom microservices that load the definition.

```bash
ruby test/integration/cmd_tlm/generate_cmd_tlm.rb --language python
cd test/integration/cmd_tlm/generated
rake build VERSION=1.0.0      # or: gem build openc3-cosmos-big.gemspec
```

Then install `openc3-cosmos-big-1.0.0.gem` from the Admin Plugins tab or with
`./openc3.sh cli load`.

## Run the benchmark

```bash
bundle exec ruby test/integration/cmd_tlm/benchmark_cmd_tlm.rb
bundle exec ruby --yjit test/integration/cmd_tlm/benchmark_cmd_tlm.rb
uv run --project python python test/integration/cmd_tlm/benchmark_cmd_tlm.py
```

Both scripts accept optional `[--no-descriptions] [generated_dir] [target]`
arguments. `--no-descriptions` parses the way the decom and interface
microservices do, without keeping packet and item descriptions. They time
parsing `tlm.txt` and `cmd.txt`, then the `as_json` + JSON encode of every
packet that `TargetModel` performs when storing a target in Redis. Ruby
reports current RSS; Python reports peak RSS. Reported item counts include the
5 derived items COSMOS adds to every packet.
