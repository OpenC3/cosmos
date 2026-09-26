# Interface Socket Throughput Integration Tests

Verify that UDP and TCP interfaces keep up with a device that sends faster than
the interface can process packets. No Redis or other services are needed.

## The problem

The interface microservice reads a packet, runs it through the protocols,
decommutates it and writes it to Redis before reading the next packet. While
it's busy the unread data waits in the operating system socket buffers, which
are small (about 200KB for UDP on Linux). Once they fill:

- **UDP**: the kernel silently drops datagrams
- **TCP**: the device can't write. Real hardware usually can't block so its own
  buffer overruns and data is lost at the source.

The read queue (`READ_QUEUE_MAX_SIZE`, default 20MB) reads the socket in a
dedicated thread and buffers the backlog in memory so the socket buffers stay
drained.

## What the tests do

A simulated device in a separate process sends 30MB in 8KB chunks at 40MB/s
while the consumer reads the interface and only processes 20MB/s (standing in
for the protocol / decom / Redis work). Each case runs with reads inline
(`READ_QUEUE_MAX_SIZE 0`, which is how interfaces read before the read queue)
and with the default read queue:

| Test                   | Inline reads                 | Read queue                    |
| ---------------------- | ---------------------------- | ----------------------------- |
| UDP datagrams received | ~50% lost (test expects > 0) | 0% (macOS), ~2% (Ruby, Linux) |
| TCP device overrun     | ~35% lost (test expects > 0) | 0% (test expects 0)           |

The inline tests are a sanity check that the scenario really overflows the
socket buffers on the machine running it.

With the read queue a small UDP loss remains on Linux with Ruby. A garbage
collection pause stops every thread, including the read thread, and a few ms
is enough to fill the default ~200KB receive buffer at 40MB/s. The UDP test
allows up to `OPENC3_SOCKET_TEST_MAX_UDP_LOSS_PERCENT` (default 5).

## Running

Ruby (build the C extensions first with `bundle exec rake build`):

```bash
cd openc3
bundle exec rspec test/integration/interfaces/ruby
```

Python:

```bash
cd openc3/python
uv run pytest ../test/integration/interfaces/python -s
```

`-s` shows the per test report, e.g.

```
UDP inline: produced 30.0MB in 0.75s, received 15.7MB, lost 14.3MB (47.5%), peak queue 0.0MB
UDP read queue: produced 30.0MB in 0.75s, received 30.0MB, lost 0.0MB (0.0%), peak queue 15.0MB
```

## Running against another version

`run_against.sh` runs these tests against the openc3 code at any git ref by
checking it out into a temporary worktree. Against `main` (before the read
queue) the read queue tests fail because `READ_QUEUE_MAX_SIZE` is ignored and
reads are always inline:

```bash
./run_against.sh main          # Ruby and Python
./run_against.sh main ruby
./run_against.sh main python
```

## Tuning

| Environment variable                      | Default | Description                          |
| ----------------------------------------- | ------- | ------------------------------------ |
| `OPENC3_SOCKET_TEST_MB`                   | 30      | Total MB the device sends            |
| `OPENC3_SOCKET_TEST_SEND_MBPS`            | 40      | Device send rate in MB/s             |
| `OPENC3_SOCKET_TEST_CONSUME_MBPS`         | 20      | Consumer processing rate in MB/s     |
| `OPENC3_SOCKET_TEST_MAX_UDP_LOSS_PERCENT` | 5       | UDP loss allowed with the read queue |

Keep the send rate above the consume rate and the backlog
(`MB * (1 - CONSUME / SEND)`) below the 20MB default read queue limit.
