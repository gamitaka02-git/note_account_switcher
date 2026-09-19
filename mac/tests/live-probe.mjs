// Explicit manual integration check. Only aggregates are printed; no credentials or article content.
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawn} from 'node:child_process';
const support=path.join(os.homedir(),'Library/Application Support/NoteAccountSwitcher');
const accounts=JSON.parse(await fs.readFile(path.join(support,'accounts.json'),'utf8'));
if (!accounts.length) throw Error('No registered accounts');
const profile=path.join(support,'Profiles',accounts[0].id.toUpperCase());
const child=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',[
  '--user-data-dir='+profile,'--remote-debugging-port=0','--remote-debugging-address=127.0.0.1',
  '--no-first-run','--disable-background-mode','https://note.com/dashboard'
],{stdio:'ignore'});
const delay=ms=>new Promise(r=>setTimeout(r,ms));
let ws;
try {
  let port;
  for(let i=0;i<40;i++) {
    try {
      const [p,route]=(await fs.readFile(path.join(profile,'DevToolsActivePort'),'utf8')).trim().split('\n');
      const version=await fetch('http://127.0.0.1:'+p+'/json/version').then(r=>r.json());
      if (new URL(version.webSocketDebuggerUrl).pathname===route) {port=p;break;}
    } catch {}
    await delay(500);
  }
  if (!port) throw Error('Dedicated Chrome must be closed before probe');
  await delay(7000);
  const targets=await fetch('http://127.0.0.1:'+port+'/json/list').then(r=>r.json());
  const target=targets.find(t=>t.type==='page' && t.url.startsWith('https://note.com/'));
  if(!target) throw Error('note page not found');
  ws=new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res,rej)=>{ws.onopen=res;ws.onerror=rej;});
  const script=await fs.readFile(new URL('../FetchAnalytics.js',import.meta.url),'utf8');
  const result=await new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(Error('Probe timed out')),130000);
    ws.onmessage=event=>{const m=JSON.parse(event.data);if(m.id===1){clearTimeout(timer);resolve(m);}};
    ws.send(JSON.stringify({id:1,method:'Runtime.evaluate',params:{expression:script+'\nfetchNoteAnalytics("LAST_28_DAYS")',awaitPromise:true,returnByValue:true,timeout:120000}}));
  });
  const value=result.result?.result?.value;
  console.log(value?.ok ? {ok:true,period:value.snapshot.period,articles:value.snapshot.articles.length,totals:value.snapshot.totals} : {ok:false,code:value?.code ?? 'evaluationError'});
  process.exitCode=value?.ok ? 0:1;
} finally {
  ws?.close();
  // This is the child launched above, never the user's ordinary Chrome.
  if(child.exitCode===null) child.kill('SIGTERM');
}
