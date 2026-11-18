#!/usr/bin/env node
'use strict';

// Capture selected frames from the official shader with the checked-in model
// seed and input events. This is an offline comparison tool, not app code.
// Usage: node tool/capture_theme_switch_source_frames.cjs MAIN_JS OUTPUT_DIR [CHROME_BIN]

const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');
const {spawn} = require('node:child_process');

const [sourceArg, outputArg, chromeArg] = process.argv.slice(2);
if (!sourceArg || !outputArg) {
  console.error('Usage: node tool/capture_theme_switch_source_frames.cjs MAIN_JS OUTPUT_DIR [CHROME_BIN]');
  process.exit(2);
}

const sourcePath = path.resolve(sourceArg);
const outputDir = path.resolve(outputArg);
const repoRoot = path.resolve(__dirname, '../..');
if (outputDir === repoRoot || outputDir.startsWith(repoRoot + path.sep)) {
  throw new Error('Write comparison output outside the repository.');
}

const modelFixturePath = path.join(__dirname, '../test/fixtures/theme_switch_model.json');
const opticsFixturePath = path.join(__dirname, '../test/fixtures/theme_switch_optics.json');
const modelFixture = JSON.parse(fs.readFileSync(modelFixturePath, 'utf8'));
const opticsFixture = JSON.parse(fs.readFileSync(opticsFixturePath, 'utf8'));
const provenance = modelFixture.provenance;
const optics = opticsFixture.provenance;
const trajectoryMetadata = provenance.particle_trajectory_oracle;
const trajectoryBytes = fs.readFileSync(path.join(__dirname, '../test/fixtures', trajectoryMetadata.file));
const trajectorySha = crypto.createHash('sha256').update(trajectoryBytes).digest('hex');
if (trajectorySha !== trajectoryMetadata.sha256) {
  throw new Error(`Particle trajectory fixture SHA mismatch: ${trajectorySha}`);
}
const fullParticleOracle = JSON.parse(zlib.gunzipSync(trajectoryBytes).toString('utf8'));
if (fullParticleOracle.length !== 151) throw new Error('Unexpected particle trajectory frame count.');
const source = fs.readFileSync(sourcePath, 'utf8');
const sourceSha = crypto.createHash('sha256').update(source).digest('hex');
if (sourceSha !== provenance.source_sha256) {
  throw new Error(`Official source SHA mismatch: ${sourceSha}`);
}
const stateTap = `window.__frameState={
  i:Math.round(now*60/1000),time,p:s.p,v:s.v,theme,x:kx-cx,hx:khx,hy:khy,
  theta,led:s.led*P.intensity,lift:s.hover*(1-s.press),
  particles:PIX.map(px=>[px.sx-cx,px.sy-cy,px.size,Math.max(0,Math.min(1,px.bright))]),
};`;
const rasterMarker = '// raster pixels';
if (!source.includes(rasterMarker)) throw new Error('Official source raster marker is missing.');
const instrumentedSource = source.replace(rasterMarker, `${stateTap}\n  ${rasterMarker}`);

const [width, height] = optics.viewport;
const [centerX, centerY] = optics.scene_origin;
const scale = optics.scene_scale;
const dpr = optics.device_pixel_ratio;
const frames = provenance.trajectory_sample_frames;
const events = provenance.events_before_frame;
const particleCount = provenance.particle_count;
const chromeBin = chromeArg || process.env.AGGREGATE_CHROME_BIN ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
if (!fs.existsSync(chromeBin)) throw new Error('Chrome executable does not exist.');

fs.mkdirSync(outputDir, {recursive: true});
const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'aggregate-glass-source-'));
const safeSource = instrumentedSource.replace(/<\/script/gi, '<\\/script');
const html = `<!doctype html>
<meta charset="utf-8">
<style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#101218}canvas{position:fixed;inset:0;width:100vw;height:100vh}#hint{display:none}</style>
<canvas id="gl"></canvas><div id="hint"></div>
<script>
let randomState=${provenance.seed}>>>0;
Math.random=()=>{randomState=(Math.imul(1664525,randomState)+1013904223)>>>0;return randomState/4294967296};
window.requestAnimationFrame=()=>1;
</script>
<script>${safeSource}</script>
<script>
(async()=>{
  const events=new Map(${JSON.stringify(events)}.map(row=>[row.frame,row]));
  const wanted=new Set(${JSON.stringify(frames)});
  vw=${width};vh=${height};cx=${centerX};cy=${centerY};S=${scale};dpr=${dpr};
  const travel=TRACK.w/2-PAD-KNOB_HALF;leftX=cx-travel;rightX=cx+travel;
  canvas.width=${width};canvas.height=${height};gl.viewport(0,0,${width},${height});
  box.x=cx-box.w/2;box.y=cy-box.h/2;
  lastT=0;
  const model=[];
  for(let i=0;i<=150;i++){
    const event=events.get(i);
    if(event?.hover!==undefined)state.hoverT=event.hover?1:0;
    if(event?.light!==undefined){state.target=event.light?1:0;state.kick=1;}
    frame(i/60*1000);
    if(!wanted.has(i))continue;
    const row=window.__frameState;
    model.push(row);
    const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/png'));
    if(!blob)throw new Error('Canvas PNG export failed.');
    const response=await fetch('/frame/'+i,{method:'POST',body:blob});
    if(!response.ok)throw new Error('Frame write failed: '+i);
  }
  const modelResponse=await fetch('/model-input',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(model)});
  if(!modelResponse.ok)throw new Error('Model input write failed.');
  const doneResponse=await fetch('/done',{method:'POST',body:'ok'});
  if(!doneResponse.ok)throw new Error('Capture completion failed.');
  document.title='CAPTURE_COMPLETE';
})().catch(error=>{document.title='CAPTURE_FAILED';fetch('/error',{method:'POST',body:String(error)});});
</script>`;

let resolveDone;
let rejectDone;
const done = new Promise((resolve, reject) => {
  resolveDone = resolve;
  rejectDone = reject;
});

const server = http.createServer((request, response) => {
  if (request.method === 'GET' && new URL(request.url, 'http://localhost').pathname === '/') {
    response.writeHead(200, {'content-type': 'text/html; charset=utf-8'});
    response.end(html);
    return;
  }

  const frameMatch = request.url.match(/^\/frame\/(\d+)$/);
  if (request.method === 'POST' && frameMatch) {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      const bytes = Buffer.concat(chunks);
        if (
          bytes.length < 24 ||
          bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a'
        ) {
          response.writeHead(400);
          response.end('Unexpected PNG.');
          return;
        }
        const frameWidth = bytes.readUInt32BE(16);
        const frameHeight = bytes.readUInt32BE(20);
        if (frameWidth !== width || frameHeight !== height) {
        response.writeHead(400);
        response.end('Unexpected PNG.');
        return;
      }
      const file = `original-render-${Number(frameMatch[1])}.png`;
      fs.writeFileSync(path.join(outputDir, file), bytes);
      response.writeHead(204);
      response.end();
    });
    return;
  }

  if (request.method === 'POST' && request.url === '/model-input') {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      const rows = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (rows.length !== frames.length || rows.some(row => row.particles.length !== particleCount)) {
        response.writeHead(400);
        response.end('Unexpected model dimensions.');
        return;
      }
      try {
        verifySourceSamples(rows);
        fs.writeFileSync(path.join(outputDir, 'model-input.json'), JSON.stringify(rows));
      } catch (error) {
        response.writeHead(400);
        response.end('Source samples do not match the checked-in fixture.');
        rejectDone(error);
        return;
      }
      response.writeHead(204);
      response.end();
    });
    return;
  }

  if (request.method === 'POST' && request.url === '/done') {
    request.resume();
    request.on('end', () => {
      response.writeHead(204);
      response.end();
      resolveDone();
    });
    return;
  }

  if (request.method === 'POST' && request.url === '/error') {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      response.writeHead(204);
      response.end();
      rejectDone(new Error(Buffer.concat(chunks).toString('utf8')));
    });
    return;
  }

  response.writeHead(404);
  response.end();
});

function verifySourceSamples(rows) {
  const expectedRows = new Map(modelFixture.frames.map(row => [row.i, row]));
  const scalarFields = ['p', 'v', 'theme', 'x', 'hx', 'hy', 'theta', 'led', 'lift'];
  for (const row of rows) {
    const expected = expectedRows.get(row.i);
    if (!expected) throw new Error(`Unexpected source frame ${row.i}.`);
    for (const field of scalarFields) {
      if (Math.abs(row[field] - expected[field]) > 1e-12) {
        throw new Error(`Source scalar mismatch at frame ${row.i}: ${field}.`);
      }
    }
    const trajectory = fullParticleOracle[row.i];
    if (!trajectory || trajectory.length !== particleCount) {
      throw new Error(`Missing complete particle oracle at frame ${row.i}.`);
    }
    for (let index = 0; index < particleCount; index++) {
      const actual = row.particles[index];
      const sourceExpected = trajectory[index];
      for (let field = 0; field < 4; field++) {
        if (Math.abs(actual[field] - sourceExpected[field]) > 1e-9) {
          throw new Error(`Source particle mismatch at frame ${row.i}: ${index}.${field}.`);
        }
      }
    }
  }
}

async function main() {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const url = `http://127.0.0.1:${server.address().port}/?zoom=${scale}`;
  const child = spawn(chromeBin, [
    '--headless=new', '--no-first-run', '--no-default-browser-check',
    '--disable-sync', '--disable-background-networking', '--disable-component-update',
    '--disable-features=Translate,BackForwardCache', '--use-gl=angle',
    '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--enable-webgl',
    '--ignore-gpu-blocklist', `--force-device-scale-factor=${dpr}`,
    `--window-size=${width},${height}`, `--user-data-dir=${profileDir}`, url,
  ], {stdio: 'ignore'});
  const exit = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', (code, signal) => {
      if (code !== 0 && !signal) reject(new Error(`Chrome exited with ${code}.`));
      else resolve({code, signal});
    });
  });
  const timeout = setTimeout(() => rejectDone(new Error('Source frame capture timed out.')), 45000);
  try {
    await Promise.race([done, exit.then(() => { throw new Error('Chrome closed before capture completed.'); })]);
    clearTimeout(timeout);
    child.kill('SIGTERM');
    await Promise.race([exit, new Promise(resolve => setTimeout(resolve, 5000))]);
    const manifest = {
      sourceUrl: provenance.source_url,
      sourceSha256: sourceSha,
      particleTrajectorySha256: trajectorySha,
      seed: provenance.seed,
      framesPerSecond: provenance.frames_per_second,
      events: events,
      frameIndices: frames,
      viewport: [width, height],
      devicePixelRatio: dpr,
      sceneOrigin: [centerX, centerY],
      scale,
      renderer: 'Google Chrome headless, ANGLE SwiftShader WebGL2',
      modelInputPath: path.join(outputDir, 'model-input.json'),
    };
    fs.writeFileSync(path.join(outputDir, 'source-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
    console.log(JSON.stringify({status: 'ok', sourceSha256: sourceSha, frames, outputDir}));
  } finally {
    clearTimeout(timeout);
    child.kill('SIGTERM');
    server.close();
    fs.rmSync(profileDir, {recursive: true, force: true});
  }
}

main().catch(error => {
  console.error(JSON.stringify({status: 'failed', error: String(error)}));
  process.exitCode = 1;
});
