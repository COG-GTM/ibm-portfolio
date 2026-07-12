'use strict';

const $ = (id) => document.getElementById(id);

const SCENARIO = [
  { key: 'create',   title: '1. Create portfolio',      method: 'POST',   path: (o) => `/portfolio/${o}` },
  { key: 'buy-ibm',  title: '2. Buy 100 shares of IBM', method: 'PUT',    path: (o) => `/portfolio/${o}?symbol=IBM&shares=100` },
  { key: 'buy-aapl', title: '3. Buy 25 shares of AAPL', method: 'PUT',    path: (o) => `/portfolio/${o}?symbol=AAPL&shares=25` },
  { key: 'get',      title: '4. Get portfolio',         method: 'GET',    path: (o) => `/portfolio/${o}` },
  { key: 'returns',  title: '5. Get returns (all portfolios, totals & loyalty)', method: 'GET', path: () => `/portfolio/` },
  { key: 'delete',   title: '6. Delete portfolio',      method: 'DELETE', path: (o) => `/portfolio/${o}` },
];

let results = {};

function sortKeys(v) {
  if (Array.isArray(v)) return v.map(sortKeys);
  if (v && typeof v === 'object') {
    const out = {};
    for (const k of Object.keys(v).sort()) out[k] = sortKeys(v[k]);
    return out;
  }
  return v;
}

// returns list of json paths that differ
function diffPaths(a, b, prefix = '') {
  if (a === null || b === null || typeof a !== 'object' || typeof b !== 'object') {
    return JSON.stringify(a) === JSON.stringify(b) ? [] : [prefix || '(root)'];
  }
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  let out = [];
  for (const k of keys) {
    out = out.concat(diffPaths(a[k], b[k], prefix ? `${prefix}.${k}` : k));
  }
  return out;
}

function renderJson(el, obj, diffKeys) {
  const text = JSON.stringify(sortKeys(obj), null, 2) ?? 'null';
  el.innerHTML = text
    .split('\n')
    .map((line) => {
      const m = line.match(/^\s*"([^"]+)":/);
      const topKey = m && diffKeys.some((d) => d === m[1] || d.startsWith(m[1] + '.'));
      return `<span class="diff-line${topKey ? ' diff' : ''}">${line.replace(/</g, '&lt;')}</span>`;
    })
    .join('\n');
}

function timelineChip(step, state) {
  const icon = { pending: '·', running: '⏳', match: '✓', mismatch: '✗' }[state];
  return `<span class="tl-chip ${state}" id="tl-${step.key}">${icon} ${step.title.replace(/^\d+\. /, '')}</span>`;
}

function stepCard(step) {
  return `
  <div class="step-card" id="card-${step.key}">
    <div class="step-head">
      <span class="step-title">${step.title}</span>
      <span class="step-req" id="req-${step.key}"></span>
      <span class="badge" id="badge-${step.key}"></span>
    </div>
    <div class="panes">
      <div class="pane db2">
        <h3>DB2 instance</h3>
        <div class="meta"><span id="meta-db2-${step.key}"></span></div>
        <pre id="json-db2-${step.key}"></pre>
      </div>
      <div class="pane pg">
        <h3>PostgreSQL instance</h3>
        <div class="meta"><span id="meta-pg-${step.key}"></span></div>
        <pre id="json-pg-${step.key}"></pre>
      </div>
    </div>
    <div class="diff-summary" id="diff-${step.key}"></div>
  </div>`;
}

function reset() {
  results = {};
  $('timeline').innerHTML = SCENARIO.map((s) => timelineChip(s, 'pending')).join('');
  $('steps').innerHTML = '';
  $('rows').classList.add('hidden');
  setVerdict('idle', '');
}

function setVerdict(text, cls) {
  const v = $('verdict');
  v.textContent = text;
  v.className = 'verdict ' + cls;
}

async function runStep(step, owner) {
  document.getElementById(`tl-${step.key}`).outerHTML = timelineChip(step, 'running');
  $('steps').insertAdjacentHTML('beforeend', stepCard(step));
  const apiPath = step.path(owner);
  $(`req-${step.key}`).textContent = `${step.method} ${apiPath}`;

  const resp = await fetch('/api/call', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ method: step.method, path: apiPath }),
  });
  const { db2, postgres } = await resp.json();

  const diffs = diffPaths(sortKeys(db2.body), sortKeys(postgres.body));
  const statusMatch = db2.status === postgres.status;
  const match = statusMatch && diffs.length === 0;

  $(`meta-db2-${step.key}`).innerHTML = `HTTP ${db2.status} · <span class="lat">${db2.ms} ms</span>`;
  $(`meta-pg-${step.key}`).innerHTML = `HTTP ${postgres.status} · <span class="lat">${postgres.ms} ms</span>`;
  renderJson($(`json-db2-${step.key}`), db2.body, diffs);
  renderJson($(`json-pg-${step.key}`), postgres.body, diffs);

  const badge = $(`badge-${step.key}`);
  badge.textContent = match ? 'MATCH ✓' : 'MISMATCH ✗';
  badge.className = 'badge ' + (match ? 'match' : 'mismatch');

  const summary = $(`diff-${step.key}`);
  summary.className = 'diff-summary ' + (match ? 'match' : 'mismatch');
  summary.textContent = match
    ? `Field-level diff: 0 differing fields — identical response (status ${db2.status} on both).`
    : `Differing: ${!statusMatch ? `HTTP status (${db2.status} vs ${postgres.status}) ` : ''}${diffs.join(', ')}`;

  document.getElementById(`tl-${step.key}`).outerHTML = timelineChip(step, match ? 'match' : 'mismatch');
  results[step.key] = match;
  return match;
}

async function runScenario() {
  const owner = $('owner').value.trim() || 'DemoTrader';
  $('runBtn').disabled = true;
  reset();
  setVerdict('running…', 'running');
  const keep = $('keep').checked;
  let allMatch = true;
  const steps = keep ? SCENARIO.filter((s) => s.key !== 'delete') : SCENARIO;
  if (keep) document.getElementById('tl-delete').outerHTML = '';
  for (const step of steps) {
    const ok = await runStep(step, owner);
    allMatch = allMatch && ok;
  }
  setVerdict(
    allMatch ? `✓ Full parity — ${steps.length}/${steps.length} steps match` : '✗ Behavioral drift detected',
    allMatch ? 'pass' : 'fail'
  );
  $('runBtn').disabled = false;
}

async function peekRows() {
  const owner = $('owner').value.trim() || 'DemoTrader';
  $('rows').classList.remove('hidden');
  $('rowsDb2').textContent = 'querying DB2…';
  $('rowsPg').textContent = 'querying Postgres…';
  const r = await (await fetch(`/api/rows?owner=${encodeURIComponent(owner)}`)).json();
  $('rowsDb2').textContent = `-- Portfolio --\n${r.db2.portfolio}\n-- Stock --\n${r.db2.stock}`;
  $('rowsPg').textContent = `-- Portfolio --\n${r.postgres.portfolio}\n-- Stock --\n${r.postgres.stock}`;
  $('rows').scrollIntoView({ behavior: 'smooth' });
}

$('runBtn').addEventListener('click', runScenario);
$('rowsBtn').addEventListener('click', peekRows);
$('resetBtn').addEventListener('click', reset);
reset();
