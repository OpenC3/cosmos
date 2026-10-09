# Cmd/Tlm Processing Benchmark

Benchmarks how long `PacketConfig` takes to process a very large command and
telemetry definition, in both Ruby and Python.

## Generate the definition

From the `openc3` directory:

```bash
ruby test/integration/cmd_tlm/generate_cmd_tlm.rb
```

By default this writes `generated/targets/BIG/cmd_tlm/{tlm.txt,cmd.txt}`
(about 125 MB, gitignored) containing:

- 2,000 telemetry packets with 500,000 items and 2,000,000 states
  (4 states per item). Packet and item descriptions are 50 to 250 characters.
- 2,000 command packets with 150,000 parameters, also with 50 to 250
  character packet and parameter descriptions.

Each packet starts with an ID item/parameter, which counts toward the totals.
Output is deterministic for a given `--seed`. Run with `--help` to change any
of the counts, e.g. for a quick smoke test:

```bash
ruby test/integration/cmd_tlm/generate_cmd_tlm.rb --tlm-packets 20 --tlm-items 5000 \
  --tlm-states 20000 --cmd-packets 20 --cmd-params 1500
```

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
