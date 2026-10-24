// Isolated load laboratory: real application SQL, synthetic data, loopback HTTP only.
// PGlite is single connection: these numbers are NOT Vercel/Supabase capacity estimates.
import http from 'node:http';import {performance} from 'node:perf_hooks';import {mkdir,writeFile} from 'node:fs/promises';import {resolve} from 'node:path';
import {fixture,actors} from '../tests/helpers/fixture.mjs';
const db=await fixture(),out=resolve(process.env.QA_OUTPUT_DIR||'test-results'),clientLimit=Math.max(1,Math.min(1000,Number(process.env.QA_CLIENT_CONCURRENCY)||1000));await mkdir(out,{recursive:true});
console.log('Preparing 26,071 synthetic copies, 9,668 synthetic titles and 5,000 synthetic patrons…');
await db.exec(`insert into app.titles(institution_id,title,author,isbn) select 'RBCET','Load title '||n,'Synthetic author','QA-ISBN-'||n from generate_series(1,9652) n;
insert into app.copies(institution_id,title_id,accession,barcode) select 'RBCET',t.id,'QA-ACCESSION-'||n,'QA-BARCODE-'||n from generate_series(1,26023) n cross join lateral(select id from app.titles where institution_id='RBCET' order by id limit 1) t;
insert into app.patrons(institution_id,code,name,email,category) select 'RBCET','QA-USER-'||n,'Synthetic user '||n,'qa'||n||'@example.invalid','student' from generate_series(1,5000) n;`);
await db.query("select set_config('request.jwt.claim.sub',$1,false)",[actors.admin]);
let tail=Promise.resolve(),queued=0,peakQueue=0;const latency=[];
const server=http.createServer((req,res)=>{
 const arrived=performance.now();queued++;peakQueue=Math.max(peakQueue,queued);
 const run=async()=>{try{
  const u=new URL(req.url,'http://127.0.0.1');let data;
  if(u.pathname==='/catalogue')data=(await db.query('select public.library_catalogue_search($1,$2,$3) d',['RBCET','Load title '+(Number(u.searchParams.get('n'))%9652+1),10])).rows[0].d;
  else if(u.pathname==='/page')data=(await db.query('select public.library_collection_page($1,$2,$3,$4) d',['RBCET','copies',null,25])).rows[0].d;
  else if(u.pathname==='/contended-issue')data=(await db.query('select public.library_action($1,$2,$3) d',['RBCET','issue',{library_code:'RBCET',barcode:'QA-BARCODE-1',patron_code:'QA-USER-1'}])).rows[0].d;
  else{res.writeHead(404);res.end();return;}
  res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify(data));
 }catch(e){res.writeHead(409,{'content-type':'application/json'});res.end(JSON.stringify({error:e.message}));}finally{queued--;latency.push(performance.now()-arrived);}};
 tail=tail.then(run,run);
});await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
const results={date:'2026-10-24',environment:'Loopback Node HTTP + real application migrations in single-connection PGlite; synthetic records only',limits:'No hosted Auth, PostgREST, connection pool, network latency, independent DB transactions or browser rendering. Virtual users are request workflows, not browser sessions. At most 1,000 client requests in flight; additional workflows queue.',phases:[],data:{copies:26071,titles:9668,additionalPatrons:5000}};
const pct=(a,p)=>a.slice().sort((x,y)=>x-y)[Math.min(a.length-1,Math.floor(a.length*p))]||0;
try{
 for(const users of [100,500,1000,5000]){
  const durations=[],errors=[],statuses={},start=performance.now();let next=0;
  await Promise.all(Array.from({length:Math.min(clientLimit,users)},async()=>{while(next<users){const n=next++,t=performance.now();try{const r=await fetch(base+(n%4===0?'/page':'/catalogue?n='+n),{signal:AbortSignal.timeout(60000)});const d=await r.json();statuses[r.status]=(statuses[r.status]||0)+1;if(r.status!==200)errors.push(d.error||String(r.status));else if(n%4===0?d.rows.length!==25:!Array.isArray(d.titles))errors.push('Response shape mismatch');}catch(e){errors.push(e.name+': '+e.message+'; '+(e.cause?.code||''));}durations.push(performance.now()-t);}}));
  const seconds=(performance.now()-start)/1000,p={virtualUsers:users,requests:users,clientConcurrency:Math.min(clientLimit,users),seconds:+seconds.toFixed(2),requestsPerSecond:+(users/seconds).toFixed(2),p50ms:+pct(durations,.5).toFixed(2),p95ms:+pct(durations,.95).toFixed(2),p99ms:+pct(durations,.99).toFixed(2),over2seconds:durations.filter(n=>n>2000).length,failures:errors.length,statuses,errorSamples:errors.slice(0,3)};results.phases.push(p);console.log(JSON.stringify(p));
 }
 const repeated=await Promise.all(Array.from({length:200},async()=>{const r=await fetch(base+'/contended-issue');return {status:r.status,data:await r.json()};}));
 results.contention={attempts:200,accepted:repeated.filter(x=>x.status===200).length,rejected:repeated.filter(x=>x.status===409).length,openLoans:(await db.query("select count(*) n from app.loans l join app.copies c on c.id=l.copy_id where c.barcode='QA-BARCODE-1' and l.returned is null")).rows[0].n,note:'Serialized duplicate submissions; NOT proof of multi-connection locking or deadlock freedom'};
 results.peakServerQueue=peakQueue;results.memoryMB=+(process.memoryUsage().rss/1048576).toFixed(1);results.passed=results.phases.every(p=>p.failures===0)&&results.contention.accepted===1&&results.contention.openLoans===1;
 await writeFile(out+'/load-results.json',JSON.stringify(results,null,2));console.log(JSON.stringify({contention:results.contention,peakQueue,memoryMB:results.memoryMB,passed:results.passed}));if(!results.passed)process.exitCode=1;
}finally{await new Promise(r=>server.close(r));await db.close();}
