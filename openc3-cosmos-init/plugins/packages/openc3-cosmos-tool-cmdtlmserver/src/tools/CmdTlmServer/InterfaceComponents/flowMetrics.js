/*
 * Copyright 2026 OpenC3, Inc.
 * All Rights Reserved.
 * See LICENSE.md for more details.
 */

// Metrics are published every five seconds. Allow several missed reports
// before treating a service's last measurements as stale.
export const STALE_SECONDS = 30
// Queue delay thresholds come from the server (TopicLagMonitor) so the
// indicators match its falling behind notifications. These are its defaults.
export const DEFAULT_LAG_THRESHOLDS = Object.freeze({
  warning: 5,
  critical: 30,
})
export const DURATION_WARNING_SECONDS = 1
export const DURATION_CRITICAL_SECONDS = 5
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

// A warning <= 0 means the server has notifications disabled; keep showing
// delays against the defaults rather than never flagging them.
export function lagThresholds(thresholds) {
  const warning = numeric(thresholds?.warning)
  const critical = numeric(thresholds?.critical)
  if (!warning || critical === null || critical < warning) {
    return DEFAULT_LAG_THRESHOLDS
  }
  return { warning, critical }
}

function thresholdsFor(metric, lag) {
  if (metric.endsWith('_read_queue_bytes')) {
    return [BUFFER_WARNING_BYTES, BUFFER_CRITICAL_BYTES]
  }
  if (metric.endsWith('_topic_delta_seconds')) {
    return [lag.warning, lag.critical]
  }
  return [DURATION_WARNING_SECONDS, DURATION_CRITICAL_SECONDS]
}

function metricRow(service, metric, data, age, lag) {
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
    const [warning, critical] = thresholdsFor(metric, lag)
    if (value >= critical) state = 'critical'
    else if (value >= warning) state = 'warning'
  }
  let unit = null
  if (isBuffer) unit = 'bytes'
  else if (isDelay || isDuration) unit = 'seconds'
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

export function flowHealth(
  rows = [],
  unavailable = false,
  lag = DEFAULT_LAG_THRESHOLDS,
) {
  let state = 'unknown'
  if (unavailable) state = 'unavailable'
  else if (rows.some((row) => row.state === 'critical')) state = 'critical'
  else if (rows.some((row) => row.state === 'warning')) state = 'warning'
  else if (rows.some((row) => row.state === 'stale')) state = 'stale'
  else if (
    !rows.some((row) => row.monitored && row.state === 'unknown') &&
    rows.some((row) => row.monitored && row.state === 'ok')
  )
    state = 'ok'
  return { state, ...STATES[state], rows, lag }
}

// Services TargetModel deploys per target, optionally numbered (DECOM1, TSDB2).
// Scope level services such as SCOPEMULTI or TRIGGER_GROUP use the same
// SCOPE__TYPE__NAME form but their NAME is not a target.
const TARGET_SERVICE = /^(MULTI|DECOM|COMMANDLOG|PACKETLOG|TSDB|CLEANUP)\d*$/

// Match complete names, not substrings (INST must never include INST2).
// A target can have multiple service instances such as DECOM, DECOM1, TSDB2.
export function buildFlowMetrics(
  response,
  unavailable = false,
  now = Date.now(),
) {
  const lag = lagThresholds(response?.lag_thresholds)
  const result = { interface: {}, router: {}, target: {}, lag }
  for (const [service, report] of Object.entries(response?.services || {})) {
    const [, type, ...nameParts] = service.split('__')
    const name = nameParts.join('__')
    if (!name || !type) continue
    let kind
    if (type === 'INTERFACE') kind = 'interface'
    else if (type === 'ROUTER') kind = 'router'
    else if (TARGET_SERVICE.test(type)) kind = 'target'
    else continue
    const timestamp = numeric(report?.updated_at)
    const age =
      timestamp === null ? null : Math.max(0, (now - timestamp / 1e6) / 1000)
    const rows = Object.entries(report?.values || {})
      .map(([metric, data]) => metricRow(service, metric, data, age, lag))
      .filter(Boolean)
    if (!rows.length) continue
    result[kind][name] ||= []
    result[kind][name].push(...rows)
  }
  for (const group of [result.interface, result.router, result.target]) {
    for (const [name, rows] of Object.entries(group)) {
      rows.sort(
        (a, b) =>
          a.service.localeCompare(b.service) ||
          Number(b.monitored) - Number(a.monitored) ||
          a.metric.localeCompare(b.metric),
      )
      group[name] = flowHealth(rows, unavailable, lag)
    }
  }
  return result
}
