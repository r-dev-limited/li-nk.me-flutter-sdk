import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const requests = [];
const aborted = [];
const server = createServer(async (req, res) => {
  const origin = req.headers.origin || '';
  const cors = {
    'Access-Control-Allow-Origin': /^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(origin) ? origin : 'null',
    'Access-Control-Allow-Headers': 'Accept, Content-Type, X-App-Id, X-Api-Key, X-Linkme-Device',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', Vary: 'Origin',
  };
  const json = (status, body) => { res.writeHead(status, { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(body)); };
  if (req.method === 'OPTIONS') { res.writeHead(204, cors); res.end(); return; }
  const url = new URL(req.url, 'http://fixture.test');
  if (url.pathname === '/state/reset') { requests.length = 0; aborted.length = 0; json(200, {}); return; }
  if (url.pathname === '/state') { json(200, { requests, aborted }); return; }
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  requests.push({ method: req.method, path: url.pathname, cid: url.searchParams.get('cid'), headers: req.headers, body: Buffer.concat(chunks).toString('utf8') });
  if (url.pathname === '/api/deeplink') {
    const cid = url.searchParams.get('cid');
    if (cid === 'stalled-headers' || cid === 'stalled-body') {
      res.once('close', () => aborted.push(cid));
      if (cid === 'stalled-body') { res.writeHead(200, { ...cors, 'Content-Type': 'application/json' }); res.write('{"path":'); }
      return;
    }
    json(200, { linkId: `link-${cid}`, cid, path: `/route/${cid}`, utm: { utm_source: 'flutter-browser' }, navigationAllowed: true });
    return;
  }
  if (url.pathname === '/api/deferred/claim') {
    // Deliberately attack the client boundary; Edge's whitelist is separately tested.
    json(200, { contractVersion: 1, navigationAllowed: false, claimId: 'inferred', claimMethod: 'fingerprint_exact', matchConfidence: 'medium', attributionStatus: 'inferred', duplicate: false, claimPolicyVersion: 2, utm: { utm_source: 'browser' }, path: '/must-not-route', forceRedirectWeb: true, webFallbackUrl: 'https://must-not-open.example' });
    return;
  }
  if (url.pathname === '/api/app-events') { json(200, { ok: true }); return; }
  json(404, { error: 'not_found' });
});

await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
const url = `http://127.0.0.1:${server.address().port}`;
const child = spawn('flutter', ['test', ...(process.argv.includes('--wasm') ? ['--wasm'] : []), '--platform', 'chrome', `--dart-define=LINKME_FIXTURE_URL=${url}`, 'test/browser_lifecycle_test.dart'], {
  cwd: fileURLToPath(new URL('../', import.meta.url)), stdio: 'inherit', env: process.env,
});
const stop = () => child.kill('SIGTERM');
process.once('SIGINT', stop); process.once('SIGTERM', stop);
try {
  process.exitCode = await new Promise((resolve, reject) => { child.once('error', reject); child.once('close', code => resolve(code ?? 1)); });
} finally {
  process.removeListener('SIGINT', stop); process.removeListener('SIGTERM', stop);
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
