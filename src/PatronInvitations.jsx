import React,{useEffect,useRef,useState} from 'react';
import {demo,supabase,rpc,downloadCSV} from './api';
import {collectEligible,sendInvitations} from './invitation-batch.mjs';
const labels={not_created:'No login yet',pending_invite:'Setup invitation pending',existing:'Existing account - retained',inactive:'Inactive membership',expired:'Expired membership',missing_email:'Missing or invalid email'};
export function PatronInvitations({institution,campuses}){
 const [category,setCategory]=useState(null),[busy,setBusy]=useState(false);
 return <section className="panel spaced" aria-label="Student and faculty invitations">
  <div className="panel-heading"><div><h2>Student and faculty invitations</h2><p>Select people already in this library and request their setup emails. Student and faculty selections are separate.</p></div></div>
  <div className="section-actions" role="group" aria-label="Choose invitation list">
   <button className={'button '+(category==='student'?'primary':'')} aria-pressed={category==='student'} disabled={busy} onClick={()=>setCategory('student')}>Student invitations</button>
   <button className={'button '+(category==='faculty'?'primary':'')} aria-pressed={category==='faculty'} disabled={busy} onClick={()=>setCategory('faculty')}>Faculty invitations</button>
   {category&&<button className="text-button" disabled={busy} onClick={()=>setCategory(null)}>Close invitation list</button>}
  </div>
  {category&&(demo?<p className="alert">Invitation sending and account status are available in the live system. No emails are sent from sample mode.</p>:<InvitationList key={institution+':'+category} institution={institution} category={category} campuses={campuses} onBusy={setBusy}/>)}
 </section>;
}
function InvitationList({institution,category,campuses,onBusy}){
 const [campus,setCampus]=useState(''),[draft,setDraft]=useState(''),[q,setQ]=useState(''),[cursor,setCursor]=useState(null),[history,setHistory]=useState([]),[page,setPage]=useState({rows:[],total:0,eligible_count:0,next_id:null}),[loading,setLoading]=useState(false),[selecting,setSelecting]=useState(false),[selected,setSelected]=useState(new Map()),[reviewed,setReviewed]=useState(false),[busy,setBusy]=useState(false),[stopping,setStopping]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[results,setResults]=useState([]),[resultPage,setResultPage]=useState(0),[refresh,setRefresh]=useState(0);
 const active=useRef(true),stop=useRef(false),requestVersion=useRef(0);
 useEffect(()=>{active.current=true;return()=>{active.current=false;stop.current=true;requestVersion.current++;};},[]);
 useEffect(()=>{const timer=setTimeout(()=>{setQ(draft.trim());setCursor(null);setHistory([]);},300);return()=>clearTimeout(timer);},[draft]);
 const args={i:institution,patron_category:category,campus_filter:campus,q};
 useEffect(()=>{let cancelled=false;const version=++requestVersion.current;setLoading(true);setError('');rpc('library_invitation_candidates_page',{i:institution,patron_category:category,campus_filter:campus,q,after_id:cursor,page_size:50,eligible_only:false}).then(p=>{if(!cancelled&&version===requestVersion.current){if(!Array.isArray(p?.rows))throw Error('Invalid invitation list');setPage(p);}}).catch(e=>{if(!cancelled)setError(e.message);}).finally(()=>{if(!cancelled)setLoading(false);});return()=>{cancelled=true;};},[institution,category,campus,q,cursor,refresh]);
 function clearSelection(){setSelected(new Map());setReviewed(false);setNotice('');}
 function choose(rows,remove=false){const next=new Map(selected);for(const row of rows)if(row.eligible){if(remove)next.delete(row.id);else next.set(row.id,row);}if(next.size>5000){setError('Select at most 5,000 people. Narrow the institute or search filter.');return;}setSelected(next);setReviewed(false);}
 const locked=busy||selecting,pendingSearch=draft.trim()!==q,eligiblePage=page.rows.filter(r=>r.eligible),allPage=eligiblePage.length>0&&eligiblePage.every(r=>selected.has(r.id));
 async function selectMatching(){setSelecting(true);setError('');try{const rows=await collectEligible(p=>rpc('library_invitation_candidates_page',p),args,{shouldStop:()=>!active.current});if(active.current){setSelected(new Map(rows.map(r=>[r.id,r])));setReviewed(false);}}catch(e){if(active.current)setError(e.message);}finally{if(active.current)setSelecting(false);}}
 async function send(){
  if(!reviewed||!selected.size||locked)return;
  setBusy(true);onBusy(true);stop.current=false;setStopping(false);setError('');setNotice('');setResults([]);setResultPage(0);
  try{const answer=await sendInvitations([...selected.values()],async body=>{const {data}=await supabase.auth.getSession();const response=await fetch('/api/patron-logins',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+data.session?.access_token},body:JSON.stringify(body)});const r=await response.json();if(!response.ok){const e=Error(r.error||'Invitation request failed');e.status=response.status;throw e;}return r;},{institution,category,campus,shouldStop:()=>stop.current||!active.current,onProgress:r=>{if(active.current)setResults(r);}});
   if(active.current){setResults(answer.results);setNotice(answer.paused?'Sending paused or stopped. Review the results; no automatic retry is performed.':'Invitation requests completed. Review each result; requested does not mean delivered.');setSelected(new Map());setReviewed(false);setRefresh(n=>n+1);}
  }catch(e){if(active.current)setError(e.message);}finally{if(active.current){setBusy(false);onBusy(false);setStopping(false);}}
 }
 const requested=results.filter(r=>['created','resent'].includes(r.status)).length,unsent=results.filter(r=>['not_sent','rate_limited'].includes(r.status)),shownResults=results.slice(resultPage*50,(resultPage+1)*50);
 return <div className="invitation-list">
  <h3>{category==='student'?'Student invitation list':'Faculty invitation list'}</h3>
  <p>{institution} library. Completed logins are retained. Pending setup links can be resent. Inactive/expired memberships and invalid emails must be corrected first.</p>
  <div className="search-filters">
   <label>Institute<select value={campus} disabled={locked} onChange={e=>{setCampus(e.target.value);setCursor(null);setHistory([]);clearSelection();setResults([]);}}><option value="">All institutes in this library</option>{(campuses||[institution]).map(c=><option key={c}>{c}</option>)}</select></label>
   <label>Search recipients<input value={draft} disabled={locked} maxLength={150} placeholder="Name, code, email, department or class" onChange={e=>{setDraft(e.target.value);clearSelection();setResults([]);}}/></label>
  </div>
  <div className="section-actions">
   <button className="button" disabled={locked||loading||pendingSearch||!eligiblePage.length} onClick={()=>choose(eligiblePage,allPage)}>{allPage?'Deselect eligible on this page':'Select eligible on this page'}</button>
   <button className="button" disabled={locked||loading||pendingSearch||!page.eligible_count||page.eligible_count>5000} onClick={selectMatching}>{selecting?'Selecting...':`Select all eligible matching (${page.eligible_count})`}</button>
   <button className="text-button" disabled={locked||!selected.size} onClick={clearSelection}>Clear selection</button>
  </div>
  {page.eligible_count>5000&&<p className="alert">More than 5,000 eligible people match. Narrow the institute or search filter before selecting all.</p>}
  {error&&<p className="alert error" role="alert">{error}</p>}
  <p role="status">{loading?'Loading recipients...':`${page.total} matching ${category==='student'?'students':'faculty members'} - ${page.eligible_count} eligible - ${selected.size} selected`}</p>
  <div className="table-scroll"><table><thead><tr><th>Select</th><th>Code / name</th><th>Email</th><th>Institute</th><th>Department</th><th>Login status</th></tr></thead><tbody>{!loading&&page.rows.map(r=><tr key={r.id}><td><input type="checkbox" aria-label={'Select '+r.code} disabled={locked||!r.eligible||pendingSearch} checked={selected.has(r.id)} onChange={e=>choose([r],!e.target.checked)}/></td><td><strong>{r.name}</strong><small>{r.code}</small></td><td>{r.email||'No email'}</td><td>{r.institute}</td><td>{r.department||'-'}</td><td>{labels[r.login_status]||r.login_status}</td></tr>)}</tbody></table></div>
  {!loading&&!page.rows.length&&<p>No matching {category==='student'?'students':'faculty members'} found.</p>}
  <div className="section-actions"><button className="button" disabled={locked||loading||pendingSearch||!history.length} onClick={()=>{setCursor(history.at(-1));setHistory(h=>h.slice(0,-1));}}>Previous recipients</button><span>Page {history.length+1}</span><button className="button" disabled={locked||loading||pendingSearch||!page.next_id} onClick={()=>{setHistory(h=>[...h,cursor]);setCursor(page.next_id);}}>Next recipients</button></div>
  <p>Selection is limited to 5,000 people. Invitations are submitted in batches of ten while this screen stays open. Changing institute, search or recipient type clears selection. Email delivery depends on Supabase/SMTP limits; a provider throttle pauses the queue.</p>
  <label className="checkbox-field"><input type="checkbox" disabled={locked||!selected.size||pendingSearch} checked={reviewed} onChange={e=>setReviewed(e.target.checked)}/>I reviewed the selected {category==='student'?'students':'faculty members'} and approve sending setup invitations to their email addresses.</label>
  <div className="section-actions"><button className="button primary" disabled={locked||loading||pendingSearch||!selected.size||!reviewed} onClick={send}>Send invitations to {selected.size} selected {category==='student'?'students':'faculty members'}</button>{busy&&<button className="button" disabled={stopping} onClick={()=>{stop.current=true;setStopping(true);}}>{stopping?'Stopping after current batch...':'Stop after current batch'}</button>}</div>
  {busy&&<p role="status">Sending requests. {requested} email requests accepted so far. Do not close this screen. Stopping or leaving cannot recall a batch already submitted.</p>}
  {notice&&<p className="alert success" role="status">{notice}</p>}
  {results.length>0&&<section aria-label="Invitation sending results"><h3>Invitation results</h3><p>{requested} requested, {unsent.length} not sent or rate limited, {results.filter(r=>r.status==='unknown').length} uncertain. A requested email is not a delivery receipt.</p><div className="section-actions"><button className="button" disabled={busy} onClick={()=>downloadCSV(category+'-invitation-results.csv',results.map(r=>({code:r.code,name:r.name,email:r.email,result:r.status,details:r.message})))}>Export invitation results</button><button className="button" disabled={busy||!unsent.length} onClick={()=>{setSelected(new Map(unsent.map(r=>[r.id,{...r,eligible:true}])));setReviewed(false);}}>Select unsent recipients for retry</button></div><div className="table-scroll"><table><thead><tr><th>Recipient</th><th>Result</th><th>Details</th></tr></thead><tbody>{shownResults.map(r=><tr key={r.code}><td>{r.name||r.code}<small>{r.email}</small></td><td>{r.status}</td><td>{r.message}</td></tr>)}</tbody></table></div><div className="section-actions"><button className="button" disabled={!resultPage} onClick={()=>setResultPage(p=>p-1)}>Previous results</button><span>Results page {resultPage+1}</span><button className="button" disabled={(resultPage+1)*50>=results.length} onClick={()=>setResultPage(p=>p+1)}>Next results</button></div><p>For uncertain results, refresh and inspect account status before resending. The queue is not stored after closing this screen.</p></section>}
 </div>;
}
