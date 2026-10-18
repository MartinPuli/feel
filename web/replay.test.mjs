import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import vm from 'node:vm';
import { build, publicReport } from './build.mjs';

// Exercise the production inline rendering code against a minimal DOM surface.
function replay(report) {
  const html = readFileSync(new URL('./public/replay/index.html', import.meta.url), 'utf8');
  const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, { innerHTML: '', textContent: '', setAttribute(k, v) { this[k] = v; } });
    return elements.get(id);
  };
  const context = vm.createContext({ document: { getElementById: element }, fetch: async () => ({ ok: true, json: async () => report }), Date });
  // Event wiring isn't needed to test these pure rendering/label paths.
  vm.runInContext(script.slice(0, script.indexOf("$('play').onclick")), context);
  return { context, element, run: source => vm.runInContext(source, context) };
}

test('six physical columns ignore reserved slot zero and retain exact label expectations', () => {
  const { run, element } = replay();
  run(`session = {start:0,expect:[{from:0,to:1,columns:'all',band:2}]};
    drawPins({t:0,fw:[4,2,1,0,2,2,2],dist:[null,1,2,null,1,1,1],hl:255,tap:false,state:'live'});`);
  assert.equal((element('pins').innerHTML.match(/class="pin /g) || []).length, 24);
  assert.match(element('pins')['aria-label'], /column 1, L3: band 2/);
  assert.doesNotMatch(element('pins')['aria-label'], /column 0/);
  assert.match(element('pinChecks').innerHTML, /L2 · slot 2/);
  assert.match(element('pinChecks').innerHTML, /WRONG PIN/);
  assert.doesNotMatch(element('pinChecks').innerHTML, /slot 0/);
});

test('unlabelled moments never manufacture a passing check', () => {
  const { run, element } = replay();
  run(`session={start:0,expect:[]}; drawPinChecks({t:2},Array(7).fill(null));`);
  assert.match(element('pinChecks').innerHTML, /No labelled pin expectation/);
  assert.doesNotMatch(element('pinChecks').innerHTML, /PASS/);
});

test('diagnostic output escapes report data and cannot claim physical validation', async () => {
  const attack = '<img src=x onerror="alert(1)">';
  const { run, element } = replay({status:'PASS',total:1,passed:1,failed:0,generatedAt:'2026-10-18',hardware:'VERIFIED',cases:[{label:attack,slot:1,gpio:33,expectedBand:attack,actualBands:[0,attack],actualAngleDeg:attack,actualPulseUs:attack,status:attack,firstFailure:attack,packetHex:attack}]});
  await run('loadPinDiagnostics()');
  const output = element('pinDiagnosticContent').innerHTML;
  assert.doesNotMatch(output, /<img/);
  assert.match(output, /&lt;img/);
  assert.match(output, /Physical movement remains unverified/);
});

test('empty PASS reports are not rendered as successful evidence', async () => {
  const { run, element } = replay({status:'PASS',total:0,passed:0,failed:0,suites:[]});
  await run('loadUnitTests()');
  assert.doesNotMatch(element('unitTestSummary').textContent, /PASS/);
});

test('public report excludes raw errors and unrecognized payloads', () => {
  const result = publicReport({status:'FAIL',errors:['private path and payload'],recording:'private',suites:[{name:'FixtureTests',private:'secret',tests:[{name:'testFixture',status:'FAILED',error:'secret'}]}]}, 'unit-tests');
  assert.doesNotMatch(JSON.stringify(result), /private|secret/);
  assert.equal(result.suites[0].tests[0].status, 'FAILED');
});

test('static build excludes private recordings and raw report errors', () => {
  const root = mkdtempSync(join(tmpdir(), 'feel-replay-build-'));
  try {
    const data = join(root, 'data'), dist = join(root, 'dist'), publicDir = join(root, 'public');
    mkdirSync(publicDir); writeFileSync(join(publicDir, 'index.html'), 'fixture');
    for (const name of ['synthetic-fixture','private-fixture']) {
      mkdirSync(join(data,'sessions',name),{recursive:true});
      writeFileSync(join(data,'sessions',name,'session.json'), '{}');
    }
    writeFileSync(join(data,'index.json'),JSON.stringify({sessions:[{name:'synthetic-fixture',publish:true},{name:'private-fixture',publish:false}]}));
    writeFileSync(join(data,'unit-tests.json'),JSON.stringify({status:'FAIL',errors:['private-output'],suites:[]}));
    build({data,dist,publicDir});
    assert.equal(existsSync(join(dist,'replay/data/sessions/private-fixture')),false);
    assert.equal(existsSync(join(dist,'replay/data/sessions/synthetic-fixture/session.json')),true);
    assert.doesNotMatch(readFileSync(join(dist,'replay/data/index.json'),'utf8'),/private-fixture/);
    assert.doesNotMatch(readFileSync(join(dist,'replay/data/unit-tests.json'),'utf8'),/private-output/);
  } finally { rmSync(root,{recursive:true,force:true}); }
});
