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
 *
 * Every tab and the dashboard store an explicit time_range, so they show
 * data regardless of the viewer's own default time range - as long as
 * Discover is opened reasonably soon after this script runs.
 *
 * Uses only Node's built-in fetch - no npm dependencies - so it can run
 * standalone (downloaded alongside discover.sh) without needing a Kibana
 * checkout's node_modules. Requires Node 18+.
 *
 * Traces data (for the "Traces Experience" tab) is seeded separately by
 * discover.sh via `node scripts/synthtrace`, since that must run from a
 * Kibana checkout.
 */

const USERNAME = process.env.KIBANA_DEMO_USERNAME || 'elastic';
const PASSWORD = process.env.KIBANA_DEMO_PASSWORD || 'changeme';
const ES_URL = process.env.KIBANA_DEMO_ES_URL || 'http://localhost:9200';
const KIBANA_URL = process.env.KIBANA_DEMO_KIBANA_URL || 'http://localhost:5601';
const DEV_PREFIX = process.env.KIBANA_DEMO_DEV_PREFIX || '';

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
const RECENT_TIME_RANGE = { from: `now-${RECENT_DATA_WINDOW_HOURS}h`, to: 'now', mode: 'relative' };
// The federated dataset is real historical data (Jan 2009), unrelated to
// "now", so it needs its own fixed time range.
const FEDERATION_TIME_RANGE = { from: '2009-01-01', to: '2009-02-01', mode: 'absolute' };

const SPACES = [
  { id: 'demo-classic', name: 'Demo Classic', solution: 'classic' },
  { id: 'demo-o11y', name: 'Demo Observability', solution: 'oblt' },
  { id: 'demo-security', name: 'Demo Security', solution: 'security' },
  { id: 'demo-search', name: 'Demo Search', solution: 'es' },
];

function log(message) {
  console.log(`[${new Date().toISOString()}][discover] - ${message}`);
}

async function esFetch(path, { method = 'GET', body } = {}) {
  const res = await fetch(`${ES_URL}${path}`, {
    method,
    headers: { Authorization: AUTH_HEADER, 'Content-Type': 'application/json' },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : undefined;
  if (!res.ok) {
    throw new Error(`${method} ${path} -> ${res.status}: ${text}`);
  }
  return json;
}

async function esBulk(ndjsonLines) {
  const res = await fetch(`${ES_URL}/_bulk?refresh=true`, {
    method: 'POST',
    headers: { Authorization: AUTH_HEADER, 'Content-Type': 'application/x-ndjson' },
    body: ndjsonLines.join('\n') + '\n',
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : undefined;
  if (!res.ok) {
    // A request-level failure (e.g. 403) returns a top-level `error` object
    // with no `errors` field at all - checking only `json.errors` below
    // would silently treat this as successful indexing.
    throw new Error(`POST /_bulk -> ${res.status}: ${text}`);
  }
  if (json.errors) {
    const firstError = json.items.find((item) => item.index?.error);
    throw new Error(`Bulk indexing had errors: ${JSON.stringify(firstError)}`);
  }
  return json;
}

async function recreateIndex(indexName, indexBody) {
  log(`Creating index "${indexName}"...`);
  await fetch(`${ES_URL}/${indexName}`, {
    method: 'DELETE',
    headers: { Authorization: AUTH_HEADER },
  }).catch(() => {});
  await esFetch(`/${indexName}`, { method: 'PUT', body: indexBody });
}

async function kbnFetch(path, { method = 'GET', body, space, internal = false } = {}) {
  const spacePrefix = space ? `/s/${space}` : '';
  const url = `${KIBANA_URL}${DEV_PREFIX}${spacePrefix}${path}`;
  const headers = {
    Authorization: AUTH_HEADER,
    'kbn-xsrf': 'true',
    'Content-Type': 'application/json',
  };
  if (internal) {
    headers['elastic-api-version'] = '1';
    headers['x-elastic-internal-origin'] = 'Kibana';
  } else {
    headers['elastic-api-version'] = '2023-10-31';
  }
  const res = await fetch(url, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
  const text = await res.text();
  const json = text ? JSON.parse(text) : undefined;
  if (!res.ok) {
    throw new Error(`${method} ${url} -> ${res.status}: ${text}`);
  }
  return json;
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

  const now = Date.now();
  const count = 2000;
  const lines = [];
  for (let i = 0; i < count; i++) {
    const level = LEVELS[i % LEVELS.length];
    const doc = {
      '@timestamp': new Date(now - (count - i) * 15_000).toISOString(),
      'host.name': HOSTS[i % HOSTS.length],
      'service.name': SERVICES[i % SERVICES.length],
      'log.level': level,
      message: MESSAGES[level],
      response_time_ms: (i * 37) % 2000,
      bytes: (i * 2003) % 50000,
      'url.path': PATHS[i % PATHS.length],
    };
    lines.push(JSON.stringify({ index: { _index: LOGS_INDEX } }), JSON.stringify(doc));
  }
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
  const exists = await fetch(`${KIBANA_URL}${DEV_PREFIX}/api/spaces/space/${space.id}`, {
    headers: { Authorization: AUTH_HEADER, 'kbn-xsrf': 'true' },
  }).then((res) => res.ok);
  if (exists) {
    log(`Space "${space.id}" already exists.`);
    return;
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
  // Real, computed bounds for the Change Point bucket, matching the window
  // the logs data actually lives in - not a hardcoded, year-specific guess.
  const bucketEnd = new Date().toISOString();
  const bucketStart = new Date(Date.now() - RECENT_DATA_WINDOW_HOURS * 60 * 60 * 1000).toISOString();

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
        query: `FROM ${LOGS_INDEX}* | STATS count = COUNT(*) BY bucket = BUCKET(@timestamp, 50, "${bucketStart}", "${bucketEnd}") | CHANGE_POINT count ON bucket`,
      },
      time_range: RECENT_TIME_RANGE,
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
    internal: true,
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

async function main() {
  await seedLogsIndex();
  await seedMetricsIndex();
  await seedFederatedDataset();
  await seedEsqlView();

  for (const space of SPACES) {
    await ensureSpace(space);
    const dataViewId = await ensureDataView(space);
    const sessionId = await createDiscoverSession(space, dataViewId);
    await createDashboard(space, sessionId);
  }

  log('Done.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
