// External VM-service listener. No product code, flags, hot reload or app lifecycle changes.
// Node24+, no dependencies. URI stays in a private file; errors omit URL/cause/stack.
// Exit0: <=5% over budget;1: >5%;2: failed/empty capture. No profiling flags changed.
const fs = require('node:fs');
const [uriFile, outputFile, secondsText = '10', budgetText = '16667'] = process.argv.slice(2);
const seconds = Number(secondsText), budgetUs = Number(budgetText);
if (!uriFile || !outputFile || !(seconds > 0 && seconds <= 60) || !(budgetUs > 0)) {
  console.error('Usage: node sample_theme_switch_frames.cjs URI_FILE OUT_JSON SECONDS FRAME_BUDGET_US');
  process.exit(2);
}
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));
function percentile(values, p) {
  if (!values.length) return null;
  const sorted = values.slice().sort((a, b) => a-b);
  return sorted[Math.max(0, Math.ceil(sorted.length * p) - 1)];
}
function stats(values) {
  return {p50Ms: percentile(values,.5)/1000, p95Ms: percentile(values,.95)/1000,
    p99Ms: percentile(values,.99)/1000, maxMs: Math.max(...values)/1000,
    overBudgetCount: values.filter(v => v > budgetUs).length};
}
(async () => {
  let socket;
  try {
    const raw = fs.readFileSync(uriFile, 'utf8').trim();
    const target = new URL(raw);
    target.protocol = ['https:', 'wss:'].includes(target.protocol) ? 'wss:' : 'ws:';
    if (!target.pathname.endsWith('/ws')) target.pathname = target.pathname.replace(/\/$/, '') + '/ws';
    socket = new WebSocket(target);
    let nextId=1, active=false, protocolErrors=0, disconnectedDuringCapture=false;
    const pending=new Map(), frames=[];
    socket.addEventListener('close', () => { if (active) disconnectedDuringCapture=true; });
    socket.addEventListener('error', () => { if (active) disconnectedDuringCapture=true; });
    socket.addEventListener('message', event => {
      let message;
      try { message=JSON.parse(String(event.data)); } catch { protocolErrors++; return; }
      if (message.id != null && pending.has(message.id)) {
        const item=pending.get(message.id);pending.delete(message.id);clearTimeout(item.timer);
        if (message.error) item.reject(new Error('VM_RPC_FAILED'));else item.resolve(message.result);
      } else if (active && message.method === 'streamNotify' && message.params?.streamId === 'Extension') {
        const event=message.params.event;
        if (event?.extensionKind === 'Flutter.Frame') {
          const data=event.extensionData;
          const row={};
          for (const key of ['number','startTime','elapsed','build','raster','vsyncOverhead']) {
            if (!Number.isFinite(data?.[key])) { protocolErrors++; return; }
            row[key]=data[key];
          }
          frames.push(row);
        }
      }
    });
    await new Promise((resolve,reject) => {
      const timer=setTimeout(()=>reject(new Error('VM_CONNECT_TIMEOUT')),10000);
      socket.addEventListener('open',()=>{clearTimeout(timer);resolve();},{once:true});
      socket.addEventListener('error',()=>{clearTimeout(timer);reject(new Error('VM_CONNECT_FAILED'));},{once:true});
    });
    function rpc(method,params) {
      return new Promise((resolve,reject)=>{
        const id=nextId++;
        const timer=setTimeout(()=>{pending.delete(id);reject(new Error('VM_RPC_TIMEOUT'));},5000);
        pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({jsonrpc:'2.0',id,method,params}));
      });
    }
    await rpc('streamListen',{streamId:'Extension'});
    active=true;
    const wallStart=Date.now();
    process.stdout.write(`READY: capturing Flutter.Frame for ${seconds}s; budget ${(budgetUs/1000).toFixed(3)}ms\n`);
    await delay(seconds*1000);
    active=false;
    const summary={schemaVersion:1, frameBudgetUs:budgetUs, requestedDurationSeconds:seconds,
      elapsedWallMs:Date.now()-wallStart, frameCount:frames.length, protocolErrors,
      disconnectedDuringCapture, failureThresholdRatio:0.05,
      scope:'Existing debug/profile runtime. Flutter frame submissions, not SurfaceFlinger display presentation. No profiling flags changed.'};
    if (frames.length) {
      summary.build=stats(frames.map(f=>f.build));summary.raster=stats(frames.map(f=>f.raster));
      summary.totalSpan=stats(frames.map(f=>f.elapsed));summary.vsyncOverhead=stats(frames.map(f=>f.vsyncOverhead));
      summary.buildOrRasterOverBudgetRatio=frames.filter(f=>f.build>budgetUs||f.raster>budgetUs).length/frames.length;
      const span=frames.at(-1).startTime-frames[0].startTime;
      summary.submittedFrameRateEstimate=span>0?(frames.length-1)*1e6/span:null;
    }
    const failed = !frames.length || protocolErrors > 0 || disconnectedDuringCapture;
    summary.status = failed ? 'FAILED' : summary.buildOrRasterOverBudgetRatio > 0.05 ? 'JANK_REPRODUCED' : 'PASS';
    const outputFd=fs.openSync(outputFile,'w',0o600);
    fs.fchmodSync(outputFd,0o600);
    fs.writeFileSync(outputFd,JSON.stringify({summary,frames},null,2));
    fs.closeSync(outputFd);
    console.log(JSON.stringify(summary));
    try { socket.close(); } catch {}
    process.exitCode = failed ? 2 : summary.buildOrRasterOverBudgetRatio > 0.05 ? 1 : 0;
  } catch(error) {
    console.error('VM frame capture failed (URI and details redacted).');
    if (socket) { try { socket.close(); } catch {} }
    process.exitCode=2;
  }
})();
