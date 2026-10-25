export async function collectEligible(request,args,{limit=5000,shouldStop=()=>false}={}){
 const rows=[],seen=new Set();let after_id=null;
 do{if(shouldStop())throw Error('Selection cancelled');const p=await request({...args,after_id,page_size:1000,eligible_only:true});if(!Array.isArray(p?.rows))throw Error('Invalid invitation page');rows.push(...p.rows.filter(r=>r.eligible));if(rows.length>limit)throw Error('Selection limit is 5,000 people. Narrow the institute or search filter.');after_id=p.next_id;if(after_id&&seen.has(after_id))throw Error('Page cursor repeated; refresh and retry');if(after_id)seen.add(after_id);}while(after_id);
 return rows;
}
export async function sendInvitations(rows,request,{institution,category,campus='',shouldStop=()=>false,onProgress=()=>{}}={}){
 if(!['student','faculty'].includes(category))throw Error('Select students or faculty');
 if(rows.length>5000)throw Error('Selection limit is 5,000 people');
 if(new Set(rows.map(r=>r.code)).size!==rows.length)throw Error('Duplicate membership codes in selection');
 const results=[];let paused=false;
 for(let start=0;start<rows.length;start+=10){
  if(shouldStop()){paused=true;results.push(...rows.slice(start).map(r=>({...r,status:'not_sent',message:'Stopped before this recipient was submitted.'})));break;}
  const batch=rows.slice(start,start+10);let answer;
  try{answer=await request({institution,category,campus,resend:true,rows:batch.map(r=>({code:r.code}))});if(!Array.isArray(answer?.results)||answer.results.length!==batch.length||batch.some(r=>!answer.results.some(a=>a.code===r.code)))throw Error('Incomplete server results');}
  catch(e){paused=true;results.push(...batch.map(r=>({...r,status:e.status===429?'not_sent':'unknown',message:e.status===429?'Request limit reached; nothing in this batch was submitted.':'Connection interrupted. Check account status before resending; an email may already have been requested.'})),...rows.slice(start+batch.length).map(r=>({...r,status:'not_sent',message:'Not submitted after the interruption.'})));onProgress([...results]);break;}
  results.push(...answer.results.map(r=>({...batch.find(x=>x.code===r.code),...r})));
  if(answer.paused||answer.results.some(r=>r.status==='rate_limited')){paused=true;results.push(...rows.slice(start+batch.length).map(r=>({...r,status:'not_sent',message:'Queue paused at the email provider limit.'})));onProgress([...results]);break;}
  onProgress([...results]);
 }
 return {results,paused};
}
