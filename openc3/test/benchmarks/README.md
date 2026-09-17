# OpenC3 benchmarks

Run the C extension comparison from the `openc3` directory:

```sh
bundle exec ruby test/benchmarks/c_extensions_benchmark.rb
```

The benchmark launches two fresh YJIT-enabled Ruby processes: one with the
checked-in C extensions and one with `OPENC3_NO_EXT=1`. It verifies
representative results match before printing native and Ruby throughput, the
C-to-Ruby speedup, sample variation, and a per-extension geometric mean.

The defaults favor a useful development-time run. Increase the sample duration
and count before making a removal decision:

```sh
OPENC3_BENCHMARK_WARMUP=1 \
OPENC3_BENCHMARK_TIME=2 \
OPENC3_BENCHMARK_SAMPLES=7 \
bundle exec ruby test/benchmarks/c_extensions_benchmark.rb
```

To isolate an extension or workload, set a case-sensitive substring filter:

```sh
OPENC3_BENCHMARK_FILTER=crc bundle exec ruby test/benchmarks/c_extensions_benchmark.rb
```

Results are machine-, Ruby-version-, and workload-dependent. Run on each Ruby
version and deployment architecture that OpenC3 supports. A small speedup on a
rare path may not justify native build and maintenance costs, while a speedup on
packet access, CRC, or parsing hot paths can have a large end-to-end impact.

`platform` is intentionally not timed: its extension installs crash signal
handlers and exposes no callable performance path. `tabbed_plots_config` is
benchmarked against its direct Ruby equivalent because no Ruby fallback exists
in the repository and production Ruby code no longer requires that extension.

## Ruby versus Python

Compare pure Ruby both with and without YJIT (`OPENC3_NO_EXT=1`) against the
same-named Python implementations from the `openc3` directory:

```sh
uv run --project python python test/benchmarks/ruby_python_benchmark.py
```

The same `OPENC3_BENCHMARK_WARMUP`, `OPENC3_BENCHMARK_TIME`,
`OPENC3_BENCHMARK_SAMPLES`, and `OPENC3_BENCHMARK_FILTER` environment variables
are supported. Only equivalent OpenC3 methods available in both languages are
included; Ruby-only helpers are intentionally omitted. Each workload verifies a
correctness signature before its throughput is compared.
