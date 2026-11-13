#!/usr/bin/env node
/*
 * Seeds the "discover" demo dataset:
 *  - a plain log index (classic / ad hoc classic / field statistics / ES|QL /
 *    ES|QL group-by / patterns / change point tabs)
 *  - a TSDB metrics index (ES|QL "Metrics Experience" tab)
 *  - an ES|QL view over the logs index ("ES|QL View" tab)
 *  - an ES|QL Data Federation dataset over a public S3 bucket ("Data
 *    Sources" tab)
 *  - four demo spaces, one per solution type (classic / oblt / security / es)
 *  - a rich, 11-tab Discover session created in every space, plus a
 *    dashboard embedding that session
 *  - two more dashboards per space: an "Embeddables Showcase" (Lens charts,
 *    ES|QL charts, Discover, aiops, controls, links, image) and an "Edge Cases"
 *    dashboard (errors, missing references, no data, odd sizes/markup, ...)
 *
 * Every tab and the dashboard store an explicit time_range, so they show
 * data regardless of the viewer's own default time range - as long as
 * Discover is opened reasonably soon after this script runs.
 *
 * Uses only Node built-ins (Node 18+). Run from a Kibana checkout to seed
 * traces via synthtrace, or pass --skip-traces to skip that step.
 */

import { parseArgs } from 'node:util';
import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';

const { values } = parseArgs({
  options: {
    'es-url': { type: 'string' },
    'kibana-url': { type: 'string' },
    username: { type: 'string' },
    password: { type: 'string' },
    'dev-prefix': { type: 'string' },
    'skip-traces': { type: 'boolean', default: false },
    help: { type: 'boolean', short: 'h', default: false },
  },
});

if (values.help) {
  console.log(`Usage: node discover.mjs [options]

Options (flags override environment variables):
  --es-url URL       KIBANA_DEMO_ES_URL      (http://localhost:9200)
  --kibana-url URL   KIBANA_DEMO_KIBANA_URL  (http://localhost:5601)
  --username USER    KIBANA_DEMO_USERNAME    (elastic)
  --password PASS   KIBANA_DEMO_PASSWORD    (changeme)
  --dev-prefix PATH KIBANA_DEMO_DEV_PREFIX  (auto-detected if unset)
  --skip-traces      Skip synthtrace (otherwise run from a Kibana checkout)
  -h, --help        Show this help

Environment variables are inherited when using discover.sh as well.`);
  process.exit(0);
}

const USERNAME = values.username ?? (process.env.KIBANA_DEMO_USERNAME || 'elastic');
const PASSWORD = values.password ?? (process.env.KIBANA_DEMO_PASSWORD || 'changeme');
const ES_URL = validateServiceUrl((values['es-url'] ?? (process.env.KIBANA_DEMO_ES_URL || 'http://localhost:9200')), 'Elasticsearch');
const KIBANA_URL = validateServiceUrl((values['kibana-url'] ?? (process.env.KIBANA_DEMO_KIBANA_URL || 'http://localhost:5601')), 'Kibana');
let DEV_PREFIX = values['dev-prefix'] ?? process.env.KIBANA_DEMO_DEV_PREFIX ?? '';

const AUTH_HEADER = 'Basic ' + Buffer.from(`${USERNAME}:${PASSWORD}`).toString('base64');

const LOGS_INDEX = 'demo-discover-logs';
const METRICS_INDEX = 'demo-discover-metrics';
const TRACES_INDEX_PATTERN = 'traces-apm*';
const ESQL_VIEW = 'demo_discover_view';

// ES|QL Data Federation: a public, unauthenticated S3 dataset (AWS Open Data
// Bitcoin blockchain) for the "Data Sources" tab.
const FEDERATION_DATA_SOURCE = 'aws_open_data_us_east_2';
const FEDERATION_DATASET = 'btc_blocks';

// All of this run's generated data (logs, metrics, traces) lives within this
// many hours of "now". Tabs/dashboards store a relative time_range of this
// same width so they reliably show data regardless of the viewer's own
// default time range - as long as Discover is opened reasonably soon after
// this script runs (the same assumption the rest of this repo's synthtrace
// scenarios make).
const RECENT_DATA_WINDOW_HOURS = 9;
const RECENT_TIME_RANGE = { from: `now-${RECENT_DATA_WINDOW_HOURS}h`, to: 'now' };
const LOG_BUCKET_COUNT = 100;
const LOG_BUCKET_INTERVAL_MS = 5 * 60 * 1000;
const LOGS_END = Math.floor(Date.now() / LOG_BUCKET_INTERVAL_MS) * LOG_BUCKET_INTERVAL_MS;
const LOGS_START = LOGS_END - LOG_BUCKET_COUNT * LOG_BUCKET_INTERVAL_MS;
const LOGS_TIME_RANGE = { from: new Date(LOGS_START).toISOString(), to: new Date(LOGS_END).toISOString() };
// The federated dataset is real historical data (Jan 2009), unrelated to
// "now", so it needs its own fixed time range.
const FEDERATION_TIME_RANGE = { from: '2009-01-01', to: '2009-02-01' };

const SPACES = [
  { id: 'demo-classic', name: 'Demo Classic', solution: 'classic' },
  { id: 'demo-o11y', name: 'Demo Observability', solution: 'oblt' },
  { id: 'demo-security', name: 'Demo Security', solution: 'security' },
  { id: 'demo-search', name: 'Demo Search', solution: 'es' },
];

function log(message) {
  console.log(`[${new Date().toISOString()}][discover] - ${message}`);
}

function validateServiceUrl(value, service) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error(`${service} URL must be an absolute HTTP(S) URL.`);
  }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) {
    throw new Error(`${service} URL must use HTTP(S) without credentials, query, or fragment. Use the username/password options instead.`);
  }
  return url.href.replace(/\/$/, '');
}

// API requests must stay on the configured endpoint. In particular, never
// replay a write body at a redirect destination or downgrade HTTPS to HTTP.
function apiFetch(url, options = {}) {
  return fetch(url, { ...options, redirect: 'error' });
}

async function waitForServices() {
  log('Waiting for Elasticsearch to be online...');
  await waitUntilReady(ES_URL);
  log('Waiting for Kibana to be online...');
  await waitUntilReady(() => `${KIBANA_URL}${DEV_PREFIX}/api/status`, async () => {
    if (DEV_PREFIX || values['dev-prefix'] !== undefined || process.env.KIBANA_DEMO_DEV_PREFIX !== undefined) return;
    const response = await fetch(KIBANA_URL, {
      headers: { Authorization: AUTH_HEADER },
      redirect: 'manual',
    });
    const location = response.headers.get('location');
    await response.body?.cancel();
    if (location) {
      const redirect = new URL(location, KIBANA_URL).href;
      if (redirect.startsWith(`${KIBANA_URL}/`)) {
        const candidatePrefix = redirect.slice(KIBANA_URL.length).replace(/\/$/, '');
        const statusResponse = await fetch(`${KIBANA_URL}${candidatePrefix}/api/status`, {
          headers: { Authorization: AUTH_HEADER },
          redirect: 'manual',
        });
        await statusResponse.body?.cancel();
        if (statusResponse.status === 200) DEV_PREFIX = candidatePrefix;
      }
    }
  });
}

async function waitUntilReady(url, onRetry = async () => {}) {
  while (true) {
    try {
      const response = await fetch(typeof url === 'function' ? url() : url, {
        headers: { Authorization: AUTH_HEADER },
        redirect: 'manual',
      });
      await response.body?.cancel();
      if (response.status === 200) return;
      await onRetry();
    } catch {
      // Services may still be starting; retry just as the shell launcher did.
    }
    await delay(5000);
  }
}

function seedTraces() {
  if (values['skip-traces']) return;
  if (!existsSync('scripts/synthtrace.js')) {
    log('WARNING: scripts/synthtrace not found - run from a Kibana checkout to seed traces. Continuing without it.');
    return;
  }
  log('Seeding traces data via synthtrace...');
  const target = new URL(ES_URL);
  target.username = USERNAME;
  target.password = PASSWORD;
  const result = spawnSync(process.execPath, [
    'scripts/synthtrace', 'logs_traces_hosts', '--from', 'now-3h', '--to', 'now', '--target', target.href,
  ], { stdio: 'inherit' });
  if (result.error || result.status !== 0) {
    throw new Error('synthtrace failed to seed traces data. Aborting.');
  }
}

async function esFetch(path, { method = 'GET', body } = {}) {
  const res = await apiFetch(`${ES_URL}${path}`, {
    method,
    headers: { Authorization: AUTH_HEADER, 'Content-Type': 'application/json' },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${method} ${path} -> ${res.status}: ${text}`);
  }
  return text ? JSON.parse(text) : undefined;
}

async function esBulk(ndjsonLines) {
  const res = await apiFetch(`${ES_URL}/_bulk?refresh=true`, {
    method: 'POST',
    headers: { Authorization: AUTH_HEADER, 'Content-Type': 'application/x-ndjson' },
    body: ndjsonLines.join('\n') + '\n',
  });
  const text = await res.text();
  if (!res.ok) {
    // A request-level failure (e.g. 403) returns a top-level `error` object
    // with no `errors` field at all - checking only `json.errors` below
    // would silently treat this as successful indexing.
    throw new Error(`POST /_bulk -> ${res.status}: ${text}`);
  }
  const json = text ? JSON.parse(text) : undefined;
  if (json.errors) {
    const firstError = json.items.find((item) => item.index?.error);
    throw new Error(`Bulk indexing had errors: ${JSON.stringify(firstError)}`);
  }
  return json;
}

async function recreateIndex(indexName, indexBody) {
  log(`Creating index "${indexName}"...`);
  const deleted = await apiFetch(`${ES_URL}/${indexName}`, {
    method: 'DELETE',
    headers: { Authorization: AUTH_HEADER },
  });
  if (!deleted.ok && deleted.status !== 404) {
    throw new Error(`DELETE /${indexName} -> ${deleted.status}: ${await deleted.text()}`);
  }
  await deleted.body?.cancel();
  await esFetch(`/${indexName}`, { method: 'PUT', body: indexBody });
}

async function kbnFetch(path, { method = 'GET', body, space } = {}) {
  const spacePrefix = space ? `/s/${space}` : '';
  const url = `${KIBANA_URL}${DEV_PREFIX}${spacePrefix}${path}`;
  const headers = {
    Authorization: AUTH_HEADER,
    'kbn-xsrf': 'true',
    'Content-Type': 'application/json',
    'elastic-api-version': '2023-10-31',
  };
  const res = await apiFetch(url, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${method} ${url} -> ${res.status}: ${text}`);
  }
  return text ? JSON.parse(text) : undefined;
}

const HOSTS = ['web-01', 'web-02', 'web-03', 'api-01', 'api-02'];
const SERVICES = ['frontend', 'checkout', 'inventory', 'payments'];
const LEVELS = ['info', 'info', 'info', 'warn', 'error'];
const PATHS = ['/home', '/cart', '/checkout', '/api/orders', '/api/inventory'];
const MESSAGES = {
  info: 'Request handled successfully',
  warn: 'Request took longer than expected',
  error: 'Failed to process request',
};

async function seedLogsIndex() {
  await recreateIndex(LOGS_INDEX, {
    mappings: {
      properties: {
        '@timestamp': { type: 'date' },
        'host.name': { type: 'keyword' },
        'service.name': { type: 'keyword' },
        'log.level': { type: 'keyword' },
        message: { type: 'text' },
        response_time_ms: { type: 'long' },
        bytes: { type: 'long' },
        'url.path': { type: 'keyword' },
      },
    },
  });

  const lines = [];
  for (let bucket = 0; bucket < LOG_BUCKET_COUNT; bucket++) {
    const requests = (bucket < LOG_BUCKET_COUNT / 2 ? 10 : 40) + bucket % 5 - 2;
    for (let request = 0; request < requests; request++) {
      const documentIndex = lines.length / 2;
      const level = LEVELS[documentIndex % LEVELS.length];
      const doc = {
        '@timestamp': new Date(LOGS_START + bucket * LOG_BUCKET_INTERVAL_MS
          + Math.floor((request + 0.5) * LOG_BUCKET_INTERVAL_MS / requests)).toISOString(),
        'host.name': HOSTS[documentIndex % HOSTS.length],
        'service.name': SERVICES[documentIndex % SERVICES.length],
        'log.level': level,
        message: MESSAGES[level],
        response_time_ms: (documentIndex * 37) % 2000,
        bytes: (documentIndex * 2003) % 50000,
        'url.path': PATHS[documentIndex % PATHS.length],
      };
      lines.push(JSON.stringify({ index: { _index: LOGS_INDEX } }), JSON.stringify(doc));
    }
  }
  const count = lines.length / 2;
  log(`Indexing ${count} log documents...`);
  await esBulk(lines);
  log(`Seeded "${LOGS_INDEX}" with ${count} docs.`);
}

const METRICS_DEFS = [
  { name: 'cpu.utilization', type: 'gauge' },
  { name: 'memory.utilization', type: 'gauge' },
  { name: 'requests.count', type: 'counter' },
  { name: 'errors.count', type: 'counter' },
];

function getEsMapping(type) {
  if (type === 'gauge') return { type: 'double', time_series_metric: 'gauge' };
  if (type === 'counter') return { type: 'long', time_series_metric: 'counter' };
  throw new Error(`Unsupported metric type: ${type}`);
}

function generateMetricValue(type, i) {
  return type === 'gauge' ? ((i * 37) % 10000) / 100 : (i * 277) % 10000;
}

async function seedMetricsIndex() {
  const dimensions = [
    { name: 'host.name', values: HOSTS },
    { name: 'service.name', values: SERVICES },
  ];
  const now = Date.now();
  const start = new Date(now - 6 * 60 * 60 * 1000).toISOString();
  const end = new Date(now + 6 * 60 * 60 * 1000).toISOString();

  const properties = { '@timestamp': { type: 'date' } };
  for (const dim of dimensions) {
    properties[dim.name] = { type: 'keyword', time_series_dimension: true };
  }
  for (const metric of METRICS_DEFS) {
    properties[metric.name] = getEsMapping(metric.type);
  }

  await recreateIndex(METRICS_INDEX, {
    settings: {
      mode: 'time_series',
      routing_path: dimensions.map((d) => d.name),
      time_series: { start_time: start, end_time: end },
    },
    mappings: { properties },
  });

  const count = 500;
  const baseTime = now - 5 * 60 * 60 * 1000;
  const lines = [];
  for (let i = 0; i < count; i++) {
    const doc = {
      '@timestamp': new Date(baseTime + i * 30_000).toISOString(),
      'host.name': HOSTS[i % HOSTS.length],
      'service.name': SERVICES[i % SERVICES.length],
    };
    for (const metric of METRICS_DEFS) {
      doc[metric.name] = generateMetricValue(metric.type, i);
    }
    lines.push(JSON.stringify({ index: { _index: METRICS_INDEX } }), JSON.stringify(doc));
  }
  log(`Indexing ${count} metrics documents...`);
  await esBulk(lines);
  log(`Seeded "${METRICS_INDEX}" with ${count} docs.`);
}

async function seedFederatedDataset() {
  log(`Registering ES|QL Data Federation data source "${FEDERATION_DATA_SOURCE}"...`);
  await esFetch(`/_query/data_source/${FEDERATION_DATA_SOURCE}`, {
    method: 'PUT',
    body: {
      type: 's3',
      description: 'Public AWS Open Data bucket, us-east-2',
      settings: { auth: 'anonymous', region: 'us-east-2' },
    },
  });

  log(`Registering ES|QL Data Federation dataset "${FEDERATION_DATASET}"...`);
  await esFetch(`/_query/dataset/${FEDERATION_DATASET}`, {
    method: 'PUT',
    body: {
      data_source: FEDERATION_DATA_SOURCE,
      resource: 's3://aws-public-blockchain/v1.0/btc/blocks/date=2009-01-*/*.parquet',
      description: 'Bitcoin blocks, Jan 2009',
      settings: { format: 'parquet' },
    },
  });
  log(`Seeded federated dataset "${FEDERATION_DATASET}".`);
}

async function seedEsqlView() {
  log(`Registering ES|QL view "${ESQL_VIEW}"...`);
  await esFetch(`/_query/view/${ESQL_VIEW}`, {
    method: 'PUT',
    body: {
      query: `FROM ${LOGS_INDEX}* | STATS count = COUNT(*) BY service.name, log.level | SORT count DESC`,
      description: 'Error/warn/info counts by service, as a reusable ES|QL view',
    },
  });
  log(`Seeded ES|QL view "${ESQL_VIEW}".`);
}

async function ensureSpace(space) {
  const res = await apiFetch(`${KIBANA_URL}${DEV_PREFIX}/api/spaces/space/${space.id}`, {
    headers: { Authorization: AUTH_HEADER, 'kbn-xsrf': 'true' },
  });
  if (res.ok) {
    log(`Space "${space.id}" already exists.`);
    return;
  }
  if (res.status !== 404) {
    throw new Error(`GET /api/spaces/space/${space.id} -> ${res.status}: ${await res.text()}`);
  }
  log(`Creating space "${space.id}" (solution: ${space.solution})...`);
  await kbnFetch('/api/spaces/space', {
    method: 'POST',
    body: { id: space.id, name: space.name, solution: space.solution },
  });
}

async function ensureDataView(space) {
  const title = `${LOGS_INDEX}*`;
  try {
    const result = await kbnFetch('/api/data_views/data_view', {
      method: 'POST',
      space: space.id,
      body: { data_view: { title, name: title, timeFieldName: '@timestamp' } },
    });
    return result.data_view.id;
  } catch (err) {
    const list = await kbnFetch('/api/data_views', { space: space.id });
    const existing = (list.data_view || []).find((dv) => dv.title === title);
    if (existing) return existing.id;
    throw err;
  }
}

function buildTabs(dataViewId) {
  return [
    {
      id: 'classic',
      label: 'Classic',
      type: 'default',
      data_source: { type: 'data_view_reference', ref_id: dataViewId },
      query: { language: 'kql', expression: 'log.level: "error"' },
      filters: [],
      column_order: ['@timestamp', 'host.name', 'service.name', 'log.level', 'message'],
      sort: [{ name: '@timestamp', direction: 'desc' }],
      view_mode: 'documents',
      time_range: RECENT_TIME_RANGE,
    },
    {
      id: 'field-statistics',
      label: 'Field Statistics',
      type: 'default',
      data_source: { type: 'data_view_reference', ref_id: dataViewId },
      query: { language: 'kql', expression: '' },
      filters: [],
      view_mode: 'aggregated',
      time_range: RECENT_TIME_RANGE,
    },
    {
      id: 'classic-adhoc',
      label: 'Classic (Ad Hoc)',
      type: 'default',
      data_source: {
        type: 'data_view_spec',
        name: 'Demo Discover Logs (ad hoc)',
        index_pattern: `${LOGS_INDEX}*`,
        time_field: '@timestamp',
      },
      query: { language: 'kql', expression: 'log.level: "warn"' },
      filters: [],
      column_order: ['@timestamp', 'host.name', 'service.name', 'log.level', 'message'],
      sort: [{ name: '@timestamp', direction: 'desc' }],
      view_mode: 'documents',
      time_range: RECENT_TIME_RANGE,
    },
    {
      id: 'esql',
      label: 'ES|QL',
      type: 'default',
      data_source: {
        type: 'esql',
        query: `FROM ${LOGS_INDEX}* | WHERE log.level == "error" | LIMIT 100`,
      },
      time_range: RECENT_TIME_RANGE,
    },
    {
      id: 'esql-group-by',
      label: 'ES|QL Group By',
      type: 'default',
      data_source: {
        type: 'esql',
        query: `FROM ${LOGS_INDEX}* | STATS count = COUNT(*) BY host.name, log.level | SORT count DESC`,
      },
      time_range: RECENT_TIME_RANGE,
    },
    {
      id: 'esql-view',
      label: 'ES|QL View',
      type: 'default',
      data_source: { type: 'esql', query: `FROM ${ESQL_VIEW} | LIMIT 100` },
      time_range: RECENT_TIME_RANGE,
    },
    {
      id: 'metrics-experience',
      label: 'Metrics Experience',
      type: 'default',
      data_source: { type: 'esql', query: `TS ${METRICS_INDEX}` },
      time_range: RECENT_TIME_RANGE,
    },
    {
      id: 'traces-experience',
      label: 'Traces Experience',
      type: 'default',
      data_source: { type: 'esql', query: `FROM ${TRACES_INDEX_PATTERN} | LIMIT 100` },
      time_range: RECENT_TIME_RANGE,
    },
    {
      id: 'patterns',
      label: 'Patterns',
      type: 'default',
      data_source: {
        type: 'esql',
        query: `FROM ${LOGS_INDEX}* | STATS count = COUNT(*) BY pattern = CATEGORIZE(message)`,
      },
      time_range: RECENT_TIME_RANGE,
    },
    {
      id: 'change-point',
      label: 'Change Point',
      type: 'default',
      data_source: {
        type: 'esql',
        query: `FROM ${LOGS_INDEX}* | WHERE @timestamp >= TO_DATETIME("${LOGS_TIME_RANGE.from}") AND @timestamp < TO_DATETIME("${LOGS_TIME_RANGE.to}") | STATS count = COUNT(*) BY bucket = BUCKET(@timestamp, 5 minutes) | SORT bucket ASC | CHANGE_POINT count ON bucket`,
      },
      time_range: LOGS_TIME_RANGE,
    },
    {
      id: 'data-sources',
      label: 'Data Sources',
      type: 'default',
      data_source: {
        type: 'esql',
        query: `FROM ${FEDERATION_DATASET} | LIMIT 10`,
      },
      time_range: FEDERATION_TIME_RANGE,
    },
  ];
}

// Deterministic per-space IDs so automated tests can reference these saved
// objects directly instead of having to look up a freshly-generated UUID.
// PUT-by-id is an upsert, so re-running this script is also fully
// idempotent. Note: these must be unique *across* spaces, not just within
// one - the discover_sessions upsert route's existence check isn't
// space-scoped (a `search` object with the same ID in a different space
// still 409s), unlike `GET`, which correctly respects space isolation.
const getDiscoverSessionId = (space) => `demo-discover-session-${space.id}`;
const getDashboardId = (space) => `demo-discover-dashboard-${space.id}`;

async function createDiscoverSession(space, dataViewId) {
  const body = {
    title: 'Discover Demo',
    description:
      'Rich multi-tab Discover session: classic (saved + ad hoc data view), field statistics, ES|QL, ES|QL group by, ES|QL view, metrics experience, traces experience, patterns, change point, data sources.',
    tabs: buildTabs(dataViewId),
  };
  const result = await kbnFetch(`/api/discover_sessions/${getDiscoverSessionId(space)}`, {
    method: 'PUT',
    space: space.id,
    body,
  });
  log(`Upserted Discover session "${result.id}" in space "${space.id}".`);
  return result.id;
}

async function createDashboard(space, sessionId) {
  const body = {
    title: 'Discover Demo Dashboard',
    description: 'A dashboard panel embedding the "Discover Demo" Discover session.',
    panels: [
      {
        type: 'discover_session',
        grid: { x: 0, y: 0, w: 48, h: 20 },
        config: { ref_id: sessionId },
      },
    ],
    time_range: RECENT_TIME_RANGE,
  };
  const result = await kbnFetch(`/api/dashboards/${getDashboardId(space)}`, {
    method: 'PUT',
    space: space.id,
    body,
  });
  log(`Upserted dashboard "${result.id}" in space "${space.id}".`);
}

// ---- Demo dashboards: a broad range of embeddables, plus edge cases ----
const getShowcaseDashboardId = (space) => `demo-embeddables-dashboard-${space.id}`;
const getEdgeCasesDashboardId = (space) => `demo-edge-cases-dashboard-${space.id}`;

function buildDashboards(space, dataViewId, sessionId) {
  const dsl = { type: 'data_view_spec', index_pattern: LOGS_INDEX, time_field: '@timestamp' };
  const esql = (query) => ({ type: 'esql', query });
  const bucket = 'BUCKET(@timestamp, 30, ?_tstart, ?_tend)';
  const terms = (field, size = 5) => ({ operation: 'terms', fields: [field], size });
  const vis = (config, grid) => ({ type: 'vis', grid, config });
  const md = (content, grid, extra = {}) => ({ type: 'markdown', grid, config: { content, ...extra } });
  const grid = (x, y, w, h) => ({ x, y, w, h });
  const timeRange = { time_range: RECENT_TIME_RANGE };

  const showcase = {
    title: 'Embeddables Showcase',
    description: 'A broad range of dashboard embeddables: Lens charts (DSL and ES|QL), Discover, aiops, markdown, links, image and controls.',
    ...timeRange,
    pinned_panels: [
      { type: 'options_list_control', config: { data_view_id: dataViewId, field_name: 'service.name', title: 'Service' } },
      { type: 'options_list_control', config: { data_view_id: dataViewId, field_name: 'log.level', title: 'Level (single select)', single_select: true } },
      { type: 'range_slider_control', config: { data_view_id: dataViewId, field_name: 'bytes', title: 'Bytes' } },
      { type: 'time_slider_control', config: {} },
      {
        type: 'esql_control',
        config: {
          title: 'ES|QL host', variable_name: 'host', variable_type: 'values', control_type: 'VALUES_FROM_QUERY',
          esql_query: `FROM ${LOGS_INDEX} | STATS BY host.name | KEEP host.name`, selected_options: [],
        },
      },
    ],
    panels: [
      md('## Embeddables Showcase\nLens charts, ES|QL charts, Discover, aiops, links and an image.\n\nPinned controls above filter the data view backed panels.', grid(0, 0, 16, 8)),
      vis({ type: 'metric', data_source: dsl, metrics: [{ type: 'primary', operation: 'count' }] }, grid(16, 0, 8, 8)),
      vis({ type: 'metric', data_source: esql(`FROM ${LOGS_INDEX} | STATS avg_ms = AVG(response_time_ms)`), metrics: [{ type: 'primary', operation: 'value', column: 'avg_ms' }] }, grid(24, 0, 8, 8)),
      vis({ type: 'legacy_metric', data_source: dsl, metric: { operation: 'unique_count', field: 'host.name' } }, grid(32, 0, 8, 8)),
      vis({ type: 'gauge', data_source: dsl, metric: { operation: 'average', field: 'response_time_ms' } }, grid(40, 0, 8, 8)),
      vis({ type: 'xy', layers: [{ type: 'line', data_source: dsl, x: { operation: 'date_histogram', field: '@timestamp' }, y: [{ operation: 'count' }] }] }, grid(0, 8, 24, 12)),
      vis({
        type: 'xy',
        layers: [{ type: 'area', data_source: esql(`FROM ${LOGS_INDEX} | STATS c = COUNT() BY ${bucket}, log.level`), x: { column: bucket }, y: [{ column: 'c' }], breakdown_by: { column: 'log.level' } }],
      }, grid(24, 8, 24, 12)),
      vis({ type: 'xy', layers: [{ type: 'bar', data_source: dsl, x: terms('service.name'), y: [{ operation: 'average', field: 'bytes' }] }] }, grid(0, 20, 16, 12)),
      vis({ type: 'pie', data_source: dsl, metrics: [{ operation: 'count' }], group_by: [terms('log.level')] }, grid(16, 20, 16, 12)),
      vis({ type: 'pie', donut_hole: 'm', data_source: dsl, metrics: [{ operation: 'count' }], group_by: [terms('service.name')] }, grid(32, 20, 16, 12)),
      vis({ type: 'data_table', data_source: dsl, metrics: [{ operation: 'count' }, { operation: 'average', field: 'response_time_ms' }], rows: [terms('service.name'), terms('url.path', 10)] }, grid(0, 32, 24, 12)),
      vis({ type: 'heatmap', data_source: dsl, metric: { operation: 'count' }, x: terms('service.name'), y: terms('log.level') }, grid(24, 32, 24, 12)),
      vis({ type: 'treemap', data_source: dsl, metrics: [{ operation: 'count' }], group_by: [terms('service.name')] }, grid(0, 44, 16, 12)),
      vis({ type: 'mosaic', data_source: dsl, metric: { operation: 'count' }, group_by: [terms('service.name')], group_breakdown_by: [terms('log.level')] }, grid(16, 44, 16, 12)),
      vis({ type: 'waffle', data_source: dsl, metrics: [{ operation: 'count' }], group_by: [terms('log.level')] }, grid(32, 44, 16, 12)),
      vis({ type: 'tag_cloud', data_source: dsl, metric: { operation: 'count' }, tag_by: terms('url.path', 20) }, grid(0, 56, 16, 12)),
      { type: 'field_stats_table', grid: grid(16, 56, 32, 12), config: { view_type: 'dataview', data_view_id: dataViewId, show_distributions: true } },
      { type: 'field_stats_table', grid: grid(0, 68, 24, 12), config: { view_type: 'esql', query: { esql: `FROM ${LOGS_INDEX}` } } },
      { type: 'aiops_change_point_chart', grid: grid(24, 68, 24, 12), config: { data_view_id: dataViewId, view_type: 'charts', aggregation_function: 'avg', metric_field: 'response_time_ms', split_field: 'service.name' } },
      { type: 'aiops_log_rate_analysis', grid: grid(0, 80, 24, 14), config: { data_view_id: dataViewId } },
      { type: 'aiops_pattern_analysis', grid: grid(24, 80, 24, 14), config: { data_view_id: dataViewId, field_name: 'message' } },
      { type: 'discover_session', grid: grid(0, 94, 32, 16), config: { ref_id: sessionId } },
      { type: 'links', grid: grid(32, 94, 16, 8), config: { layout: 'vertical', links: [{ type: 'externalLink', label: 'Kibana docs', destination: 'https://www.elastic.co/docs/explore-analyze/dashboards' }] } },
      { type: 'image', grid: grid(32, 102, 16, 8), config: { image_config: { src: { type: 'url', url: 'https://www.elastic.co/static-res/images/elastic-logo-200.png' }, alt_text: 'Elastic logo', object_fit: 'contain' } } },
    ],
  };

  const longTitle = 'A very long panel title that keeps going and going to check truncation, wrapping and tooltip behavior in the panel header ' + 'x'.repeat(80);
  const edgeCases = {
    title: 'Edge Cases',
    description: 'Embeddables in unusual states: errors, no data, missing references, odd sizes, titles, markup, time ranges and filters.',
    ...timeRange,
    query: { language: 'kql', expression: 'log.level:*' },
    filters: [{ type: 'condition', condition: { field: 'service.name', operator: 'is', value: 'frontend' } }],
    panels: [
      md('## Edge cases\nA dashboard-level KQL query and a `service.name: frontend` filter apply to every panel. Collapsed sections below are loaded lazily.', grid(0, 0, 48, 5)),
      {
        title: 'Errors and missing data', collapsed: false, grid: { y: 5 },
        panels: [
          vis({ type: 'metric', data_source: esql('FROM demo-does-not-exist | STATS c = COUNT()'), metrics: [{ type: 'primary', operation: 'value', column: 'c' }], title: 'ES|QL: unknown index' }, grid(0, 0, 12, 8)),
          vis({ type: 'metric', data_source: esql(`FROM ${LOGS_INDEX} | STATS c = COUNT( | WHERE`), metrics: [{ type: 'primary', operation: 'value', column: 'c' }], title: 'ES|QL: syntax error' }, grid(12, 0, 12, 8)),
          vis({ type: 'metric', data_source: dsl, metrics: [{ type: 'primary', operation: 'average', field: 'no.such.field' }], title: 'DSL: unknown field' }, grid(24, 0, 12, 8)),
          vis({ type: 'metric', data_source: { type: 'data_view_spec', index_pattern: 'demo-does-not-exist*', time_field: '@timestamp' }, metrics: [{ type: 'primary', operation: 'count' }], title: 'DSL: no matching index' }, grid(36, 0, 12, 8)),
          vis({ type: 'xy', title: 'No data in range', layers: [{ type: 'line', data_source: esql(`FROM ${LOGS_INDEX} | WHERE @timestamp < NOW() - 365 days | STATS c = COUNT() BY ${bucket}`), x: { column: bucket }, y: [{ column: 'c' }] }] }, grid(0, 8, 16, 10)),
          vis({ type: 'data_table', title: 'Zero hit query', data_source: dsl, metrics: [{ operation: 'count' }], rows: [terms('service.name')] }, grid(16, 8, 16, 10)),
          { type: 'field_stats_table', grid: grid(32, 8, 16, 10), config: { view_type: 'dataview', data_view_id: 'does-not-exist' } },
          { type: 'aiops_log_rate_analysis', grid: grid(0, 18, 16, 10), config: { data_view_id: 'does-not-exist' } },
          { type: 'discover_session', grid: grid(16, 18, 16, 10), config: { ref_id: 'does-not-exist' } },
          { type: 'image', grid: grid(32, 18, 16, 10), config: { image_config: { src: { type: 'url', url: 'https://example.invalid/missing.png' }, alt_text: 'Broken image', object_fit: 'cover' } } },
        ],
      },
      {
        title: 'Titles, sizes and markup', collapsed: false, grid: { y: 6 },
        panels: [
          md('Panel with a very long title', grid(0, 0, 16, 6), { title: longTitle }),
          md('Hidden panel title', grid(16, 0, 16, 6), { title: 'You should not see this', hide_title: true }),
          md('Description tooltip', grid(32, 0, 16, 6), { title: 'Panel with description', description: 'Shown in the panel header tooltip.' }),
          md('1x1', grid(0, 6, 1, 1)),
          md('Narrow and tall', grid(1, 6, 2, 20)),
          md('Full width, tiny height', grid(3, 6, 45, 2)),
          md('# Unicode & markup\n日本語 · العربية · emoji 🚀🔥 · `code` · **bold**\n\n<script>alert("xss")</script> <img src=x onerror=alert(1)> <b>raw html</b>\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n' + 'Long line without spaces: ' + 'x'.repeat(300), grid(3, 8, 22, 18)),
          md('', grid(25, 8, 11, 6), { title: 'Empty markdown' }),
          md(Array.from({ length: 80 }, (_, i) => `Line ${i + 1}`).join('\n\n'), grid(36, 8, 12, 18), { title: 'Overflowing content' }),
        ],
      },
      {
        title: 'Per-panel time range and options', collapsed: false, grid: { y: 7 },
        panels: [
          vis({ type: 'xy', title: 'Own time range: last 1h', time_range: { from: 'now-1h', to: 'now' }, layers: [{ type: 'line', data_source: dsl, x: { operation: 'date_histogram', field: '@timestamp' }, y: [{ operation: 'count' }] }] }, grid(0, 0, 16, 10)),
          vis({ type: 'xy', title: 'Own time range: absolute (no data)', time_range: { from: '2001-01-01T00:00:00.000Z', to: '2001-01-02T00:00:00.000Z' }, layers: [{ type: 'line', data_source: dsl, x: { operation: 'date_histogram', field: '@timestamp' }, y: [{ operation: 'count' }] }] }, grid(16, 0, 16, 10)),
          vis({ type: 'pie', title: 'High cardinality (url.path, 100 slices)', data_source: dsl, metrics: [{ operation: 'count' }], group_by: [terms('url.path', 100)] }, grid(32, 0, 16, 10)),
          vis({ type: 'data_table', title: 'Wide table', data_source: dsl, metrics: [{ operation: 'count' }, { operation: 'average', field: 'bytes' }, { operation: 'max', field: 'bytes' }, { operation: 'min', field: 'bytes' }, { operation: 'sum', field: 'bytes' }, { operation: 'average', field: 'response_time_ms' }, { operation: 'max', field: 'response_time_ms' }], rows: [terms('service.name'), terms('host.name'), terms('log.level'), terms('url.path', 20)] }, grid(0, 10, 48, 12)),
        ],
      },
      { title: 'Collapsed section', collapsed: true, grid: { y: 8 }, panels: [vis({ type: 'metric', data_source: dsl, metrics: [{ type: 'primary', operation: 'count' }] }, grid(0, 0, 12, 8)), md('Rendered when the section is expanded.', grid(12, 0, 12, 8))] },
      { title: 'Empty section', collapsed: false, grid: { y: 9 }, panels: [] },
    ],
  };

  return [
    [getShowcaseDashboardId(space), showcase],
    [getEdgeCasesDashboardId(space), edgeCases],
  ];
}

async function createDemoDashboards(space, dataViewId, sessionId) {
  for (const [id, body] of buildDashboards(space, dataViewId, sessionId)) {
    const result = await kbnFetch(`/api/dashboards/${id}`, { method: 'PUT', space: space.id, body });
    log(`Upserted dashboard "${result.id}" ("${body.title}") in space "${space.id}".`);
  }
}

async function main() {
  await waitForServices();
  seedTraces();
  await seedLogsIndex();
  await seedMetricsIndex();
  await seedFederatedDataset();
  await seedEsqlView();

  for (const space of SPACES) {
    await ensureSpace(space);
    const dataViewId = await ensureDataView(space);
    const sessionId = await createDiscoverSession(space, dataViewId);
    await createDashboard(space, sessionId);
    await createDemoDashboards(space, dataViewId, sessionId);
  }

  log('Discover demo dataset installed. Open the Discover sessions:');
  for (const space of SPACES) log(`Demo session: ${KIBANA_URL}${DEV_PREFIX}/s/${space.id}/app/discover#/view/${getDiscoverSessionId(space)}`);
  for (const space of SPACES) {
    for (const id of [getShowcaseDashboardId(space), getEdgeCasesDashboardId(space)]) log(`Demo dashboard: ${KIBANA_URL}${DEV_PREFIX}/s/${space.id}/app/dashboards#/view/${id}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
