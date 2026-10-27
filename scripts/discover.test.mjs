import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('./discover.mjs', import.meta.url), 'utf8');
const launcher = readFileSync(new URL('./discover.sh', import.meta.url), 'utf8');
function load(fetch) {
  // Exercise the actual helpers without starting an installation or contacting services.
  const body = source.replace(/^#!.*\n/, '').replace(/^import .*;\n/gm, '').split('main().catch')[0];
  return runInNewContext(body + '\n({ validateServiceUrl, esFetch, esBulk, kbnFetch, recreateIndex, seedTraces, waitForServices })', {
    parseArgs: () => ({ values: {} }), process: { env: {}, execPath: process.execPath },
    URL, Buffer, console: { log() {} }, fetch,
    delay: async () => {}, existsSync: () => true,
    spawnSync: () => ({ status: 1 }),
  });
}

test('service URLs reject embedded secrets without echoing them', () => {
  const api = load();
  for (const url of ['https://user:secret@example.com', 'file:///tmp/foo', 'invalid-secret', 'https://host/?secret=secret']) {
    assert.throws(() => api.validateServiceUrl(url, 'Kibana'), error => !error.message.includes('secret'));
  }
  assert.equal(api.validateServiceUrl('http://localhost:5601/dev/', 'Kibana'), 'http://localhost:5601/dev');
});

test('all data requests prohibit redirects; session requests use public version', async () => {
  const api = load(async (url, options) => {
    assert.equal(options.redirect, 'error');
    if (url.includes('/api/')) assert.equal(options.headers['elastic-api-version'], '2023-10-31');
    return new Response('{"errors":false}');
  });
  await api.esFetch('/test', { method: 'PUT', body: {} });
  await api.esBulk([]);
  await api.kbnFetch('/api/discover_sessions/test', { method: 'PUT', body: {}, space: 'demo-classic' });
  await api.recreateIndex('demo-discover-logs', {});
});

test('index deletion permission errors stop before creation', async () => {
  let calls = 0;
  const api = load(async () => { calls++; return new Response('denied', { status: 403 }); });
  await assert.rejects(api.recreateIndex('demo-discover-logs', {}), /DELETE.*403/);
  assert.equal(calls, 1);
});

test('missing index is allowed; bulk request failures and synthtrace failures abort', async () => {
  let calls = 0;
  const api = load(async () => ++calls === 1 ? new Response('', { status: 404 }) : new Response('{}'));
  await api.recreateIndex('demo-discover-logs', {});
  assert.equal(calls, 2);
  const failed = load(async () => new Response('denied', { status: 403 }));
  await assert.rejects(failed.esBulk([]), /403/);
  assert.throws(() => failed.seedTraces(), /synthtrace failed/);
});

test('readiness discovers a same-origin development prefix', async () => {
  const urls = [];
  const api = load(async (url, options) => {
    urls.push(url);
    assert.equal(options.redirect, 'manual');
    if (url.endsWith(':5601/api/status')) return new Response('', { status: 404 });
    if (url.endsWith(':5601')) return new Response('', { status: 302, headers: { location: '/abc123' } });
    return new Response('{}');
  });
  await api.waitForServices();
  assert.equal(urls.at(-1), 'http://localhost:5601/abc123/api/status');
});

test('piped launcher ignores cwd module, forwards flags and env, and propagates failures', () => {
  const dir = mkdtempSync(join(tmpdir(), 'discover-test-'));
  try {
    writeFileSync(join(dir, 'discover.mjs'), 'throw new Error("Untrusted cwd module executed");');
    writeFileSync(join(dir, 'curl'), `#!/bin/sh
[ "$1" = "--proto" ] && [ "$2" = "=https" ] && [ "$3" = "--proto-redir" ] && [ "$4" = "=https" ] || exit 90
[ "$6" = "https://example.test/scripts/discover.mjs" ] || exit 91
[ "$TEST_FAIL_CURL" != "1" ] || exit 22
printf '%s' 'import assert from "node:assert/strict"; assert.deepEqual(process.argv.slice(2), ["--password", "value with spaces"]); assert.equal(process.env.TEST_ENV, "inherited"); process.exit(Number(process.env.TEST_NODE_EXIT || 0));'
`, { mode: 0o755 });
    const env = { ...process.env, PATH: `${dir}:${process.env.PATH}`, KIBANA_DEMO_SCRIPTS_URL: 'https://example.test/scripts', TEST_ENV: 'inherited' };
    const run = extra => spawnSync('sh', ['-s', '--', '--password', 'value with spaces'], { cwd: dir, input: launcher, encoding: 'utf8', env: { ...env, ...extra } });
    assert.equal(run({}).status, 0);
    assert.equal(run({ TEST_NODE_EXIT: '17' }).status, 17);
    assert.equal(run({ TEST_FAIL_CURL: '1' }).status, 22);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('default local dataset selection includes Discover', () => {
  const all = readFileSync(new URL('./all.sh', import.meta.url), 'utf8');
  const dir = mkdtempSync(join(tmpdir(), 'discover-all-test-'));
  try {
    writeFileSync(join(dir, 'discover.sh'), 'echo discover-selected\n');
    const path = join(dir, 'all.sh');
    writeFileSync(path, all);
    const result = spawnSync('sh', [path], { encoding: 'utf8' });
    assert.equal(result.status, 0);
    assert.match(result.stdout, /discover-selected/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
