/* Copyright 2026 OpenC3, Inc. All Rights Reserved. See LICENSE.md. */

import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  buildFlowMetrics,
  flowHealth,
  formatMetric,
} from '../src/tools/CmdTlmServer/InterfaceComponents/flowMetrics.js'

const now = 1_800_000_000_000
function report(values, age = 0) {
  return {
    updated_at: BigInt(now - age * 1000) * 1_000_000n,
    values: Object.fromEntries(
      Object.entries(values).map(([key, value]) => [key, { value }]),
    ),
  }
}

test('isolates interfaces, routers, and exact target names, including service instances', () => {
  const metrics = buildFlowMetrics(
    {
      DEFAULT__INTERFACE__INST: report({ interface_topic_delta_seconds: 0.01 }),
      DEFAULT__ROUTER__INST: report({ router_topic_delta_seconds: 2 }),
      DEFAULT__DECOM__INST: report({ decom_topic_delta_seconds: 0.1 }),
      DEFAULT__DECOM1__INST: report({ decom_topic_delta_seconds: 6 }),
      DEFAULT__TSDB2__INST: report({ tsdb_ingest_topic_delta_seconds: 0.2 }),
      DEFAULT__DECOM__INST2: report({ decom_topic_delta_seconds: 0.1 }),
    },
    false,
    now,
  )
  assert.equal(metrics.interface.INST.state, 'ok')
  assert.equal(metrics.router.INST.state, 'warning')
  assert.equal(metrics.target.INST.state, 'critical')
  assert.equal(metrics.target.INST.rows.length, 3)
  assert.equal(metrics.target.INST2.state, 'ok')
})

test('flags queue delays, durations, and buffered input at documented thresholds', () => {
  for (const [metric, warning, critical] of [
    ['decom_topic_delta_seconds', 1, 5],
    ['tsdb_ingest_duration_seconds', 1, 5],
    ['interface_read_queue_bytes', 1024 * 1024, 10 * 1024 * 1024],
  ]) {
    for (const [value, state] of [
      [0, 'ok'],
      [warning, 'warning'],
      [critical, 'critical'],
    ]) {
      const metrics = buildFlowMetrics(
        { DEFAULT__DECOM__INST: report({ [metric]: value }) },
        false,
        now,
      )
      assert.equal(metrics.target.INST.state, state, `${metric}: ${value}`)
    }
  }
})

test('stale reports cannot report healthy or an old backlog as current', () => {
  for (const delay of [0, 50]) {
    const metrics = buildFlowMetrics(
      {
        DEFAULT__DECOM__INST: report({ decom_topic_delta_seconds: delay }, 31),
      },
      false,
      now,
    )
    assert.equal(metrics.target.INST.state, 'stale')
    assert.equal(metrics.target.INST.rows[0].age, 31)
  }
})

test('a fresh healthy service does not hide a stale service for the same target', () => {
  const metrics = buildFlowMetrics(
    {
      DEFAULT__DECOM__INST: report({ decom_topic_delta_seconds: 0 }),
      DEFAULT__TSDB__INST: report({ tsdb_ingest_topic_delta_seconds: 0 }, 60),
    },
    false,
    now,
  )
  assert.equal(metrics.target.INST.state, 'stale')
})

test('missing and invalid samples are unknown, never healthy zeroes', () => {
  assert.equal(flowHealth().state, 'unknown')
  for (const value of [
    null,
    undefined,
    '',
    ' ',
    NaN,
    Infinity,
    -1,
    'bad',
    true,
  ]) {
    const metrics = buildFlowMetrics(
      { DEFAULT__DECOM__INST: report({ decom_topic_delta_seconds: value }) },
      false,
      now,
    )
    assert.equal(metrics.target.INST.state, 'unknown')
    assert.equal(metrics.target.INST.rows[0].value, 'Not reported')
  }
  const metrics = buildFlowMetrics(
    {
      DEFAULT__DECOM__INST: {
        values: { decom_topic_delta_seconds: { value: 0 } },
      },
    },
    false,
    now,
  )
  assert.equal(metrics.target.INST.state, 'unknown')
})

test('API failure overrides cached health and recovery clears the warning', () => {
  const data = {
    DEFAULT__DECOM__INST: report({ decom_topic_delta_seconds: 0.1 }),
  }
  assert.equal(
    buildFlowMetrics(data, true, now).target.INST.state,
    'unavailable',
  )
  assert.equal(buildFlowMetrics(data, false, now).target.INST.state, 'ok')
  assert.equal(flowHealth([], true).state, 'unavailable')
})

test('cumulative error totals are displayed without claiming a current backlog', () => {
  const metrics = buildFlowMetrics(
    {
      DEFAULT__DECOM__INST: report({
        decom_error_total: 20,
        decom_total: 1000,
      }),
    },
    false,
    now,
  )
  assert.equal(metrics.target.INST.state, 'unknown')
  assert.ok(metrics.target.INST.rows.every((row) => row.status === 'Total'))
})

test('warnings clear on recovery and reset counters do not imply a backlog', () => {
  const old = buildFlowMetrics(
    {
      DEFAULT__DECOM__INST: report({
        decom_topic_delta_seconds: 7,
        decom_total: 100,
      }),
    },
    false,
    now,
  )
  const current = buildFlowMetrics(
    {
      DEFAULT__DECOM__INST: report({
        decom_topic_delta_seconds: 0,
        decom_total: 0,
      }),
    },
    false,
    now,
  )
  assert.equal(old.target.INST.state, 'critical')
  assert.equal(current.target.INST.state, 'ok')
})

test('formats units and preserves large counters', () => {
  assert.equal(formatMetric(0.0001, 'seconds'), '< 0.001 s')
  assert.equal(formatMetric(1048576, 'bytes'), '1.00 MiB')
  assert.equal(
    formatMetric(9007199254740993n),
    9007199254740993n.toLocaleString(),
  )
  assert.deepEqual(buildFlowMetrics(null, false, now), {
    interface: {},
    router: {},
    target: {},
  })
})
