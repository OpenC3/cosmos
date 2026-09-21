/*
 * Copyright 2026 OpenC3, Inc.
 * All Rights Reserved.
 * See LICENSE.md for more details.
 */

// Metrics are published every five seconds. Allow several missed reports
// before treating a service's last measurements as stale.
export const STALE_SECONDS = 30
export const DELAY_WARNING_SECONDS = 1
export const DELAY_CRITICAL_SECONDS = 5
export const BUFFER_WARNING_BYTES = 1024 * 1024
export const BUFFER_CRITICAL_BYTES = 10 * 1024 * 1024

const STATES = {
  ok: {
    label: 'Within thresholds',
    color: 'success',
    icon: 'mdi-check-circle',
  },
  warning: { label: 'Falling behind', color: 'warning', icon: 'mdi-alert' },
  critical: {
    label: 'Falling behind',
    color: 'error',
    icon: 'mdi-alert-circle',
  },
  stale: {
    label: 'Stale metrics',
    color: 'warning',
    icon: 'mdi-clock-alert-outline',
  },
  unknown: {
    label: 'No delay samples',
    color: 'grey',
    icon: 'mdi-help-circle-outline',
  },
  unavailable: {
    label: 'Metrics unavailable',
    color: 'warning',
    icon: 'mdi-alert-outline',
  },
}

const METRIC_LABELS = {
  interface_topic_delta_seconds: 'Command queue delay',
  router_topic_delta_seconds: 'Telemetry queue delay',
  decom_topic_delta_seconds: 'Decommutation queue delay',
  log_topic_delta_seconds: 'Logging queue delay',
  text_log_topic_delta_seconds: 'Text logging queue delay',
  tsdb_ingest_topic_delta_seconds: 'Database ingestion queue delay',
  decom_duration_seconds: 'Decommutation duration',
  tsdb_ingest_duration_seconds: 'Database ingestion duration',
  tsdb_flush_duration_seconds: 'Database flush duration',
  interface_read_queue_bytes: 'Buffered input',
  router_read_queue_bytes: 'Buffered input',
  interface_cmd_total: 'Commands sent',
  interface_tlm_total: 'Telemetry packets received',
  interface_directive_total: 'Interface directives processed',
  router_cmd_total: 'Commands received',
  router_tlm_total: 'Telemetry packets sent',
  router_directive_total: 'Router directives processed',
  decom_total: 'Packets decommutated',
  decom_error_total: 'Decommutation errors',
  log_total: 'Packets logged',
  log_error_total: 'Logging errors',
  text_log_total: 'Text messages logged',
  text_log_error_total: 'Text logging errors',
  text_error_total: 'Text logging errors',
  tsdb_ingest_total: 'Packets ingested',
  tsdb_ingest_error_total: 'Database ingestion errors',
  limits_response_total: 'Limits responses processed',
  limits_response_error_total: 'Limits response errors',
}

function numeric(value) {
  if (
    !['number', 'bigint', 'string'].includes(typeof value) ||
    (typeof value === 'string' && value.trim() === '')
  ) {
    return null
  }
  const number = Number(value)
  return Number.isFinite(number) && number >= 0 ? number : null
}

export function formatMetric(value, unit) {
  const number = numeric(value)
  if (number === null) return 'Not reported'
  if (unit === 'seconds') {
    return number > 0 && number < 0.001
      ? '< 0.001 s'
      : `${number.toLocaleString(undefined, { maximumFractionDigits: 3 })} s`
  }
  if (unit === 'bytes') {
    if (number >= 1024 * 1024)
      return `${(number / (1024 * 1024)).toFixed(2)} MiB`
    if (number >= 1024) return `${(number / 1024).toFixed(2)} KiB`
    return `${number.toLocaleString()} B`
  }
  // Preserve large counters parsed by OpenC3Api as BigInts.
  return typeof value === 'bigint'
    ? value.toLocaleString()
    : number.toLocaleString()
}

function metricRow(service, metric, data, age) {
  const value = numeric(data?.value)
  const isDelay = metric.endsWith('_topic_delta_seconds')
  const isDuration = metric.endsWith('_duration_seconds')
  const isBuffer = metric.endsWith('_read_queue_bytes')
  const monitored = isDelay || isDuration || isBuffer
  if (!monitored && !metric.endsWith('_total')) return null

  let state = monitored ? 'ok' : 'info'
  if (value === null || age === null) state = 'unknown'
  else if (age > STALE_SECONDS) state = 'stale'
  else if (monitored) {
    const warning = isBuffer ? BUFFER_WARNING_BYTES : DELAY_WARNING_SECONDS
    const critical = isBuffer ? BUFFER_CRITICAL_BYTES : DELAY_CRITICAL_SECONDS
    if (value >= critical) state = 'critical'
    else if (value >= warning) state = 'warning'
  }
  const unit = isBuffer ? 'bytes' : isDelay || isDuration ? 'seconds' : null
  const label = METRIC_LABELS[metric] || metric.replaceAll('_', ' ')
  return {
    id: `${service}:${metric}`,
    service,
    metric,
    label,
    help:
      data?.help ||
      (metric.endsWith('_total')
        ? 'Cumulative count for this service; resets when the service restarts.'
        : label),
    value: formatMetric(data?.value, unit),
    state,
    monitored,
    age,
    status: state === 'info' ? 'Total' : STATES[state].label,
    color: state === 'info' ? 'grey' : STATES[state].color,
  }
}

export function flowHealth(rows = [], unavailable = false) {
  let state = 'unknown'
  if (unavailable) state = 'unavailable'
  else if (rows.some((row) => row.state === 'critical')) state = 'critical'
  else if (rows.some((row) => row.state === 'warning')) state = 'warning'
  else if (rows.some((row) => row.state === 'stale')) state = 'stale'
  else if (rows.some((row) => row.monitored && row.state === 'unknown'))
    state = 'unknown'
  else if (rows.some((row) => row.monitored && row.state === 'ok')) state = 'ok'
  return { state, ...STATES[state], rows }
}

// Match complete names, not substrings (INST must never include INST2).
// A target can have multiple service instances such as DECOM, DECOM1, TSDB2.
export function buildFlowMetrics(
  metrics,
  unavailable = false,
  now = Date.now(),
) {
  const result = { interface: {}, router: {}, target: {} }
  for (const [service, report] of Object.entries(metrics || {})) {
    const [, type, ...nameParts] = service.split('__')
    const name = nameParts.join('__')
    if (!name || !type) continue
    const kind =
      type === 'INTERFACE'
        ? 'interface'
        : type === 'ROUTER'
          ? 'router'
          : 'target'
    const timestamp = numeric(report?.updated_at)
    const age =
      timestamp === null ? null : Math.max(0, (now - timestamp / 1e6) / 1000)
    const rows = Object.entries(report?.values || {})
      .map(([metric, data]) => metricRow(service, metric, data, age))
      .filter(Boolean)
    if (!rows.length) continue
    result[kind][name] ||= []
    result[kind][name].push(...rows)
  }
  for (const group of Object.values(result)) {
    for (const [name, rows] of Object.entries(group)) {
      rows.sort(
        (a, b) =>
          a.service.localeCompare(b.service) ||
          Number(b.monitored) - Number(a.monitored) ||
          a.metric.localeCompare(b.metric),
      )
      group[name] = flowHealth(rows, unavailable)
    }
  }
  return result
}
