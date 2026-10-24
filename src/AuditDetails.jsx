import React,{useState} from 'react';import {rpc} from './api';
export function AuditDetails({event,institution}){
 const [detail,setDetail]=useState(null),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 async function load(part=0){setBusy(true);setError('');try{setDetail(await rpc('library_audit_detail',{i:institution,event_id:event.id,part}));}catch(e){setError(e.message);}finally{setBusy(false);}}
 return <details><summary>View details</summary>{error&&<p role="alert">{error}</p>}{!event._details_truncated?<pre>{JSON.stringify(event.details,null,2)}</pre>:<>{!detail?<button className="button small" disabled={busy} onClick={()=>load()}>Load full audit details</button>:<><p>Part {detail.part+1} of {detail.parts}</p><pre>{detail.text}</pre><button className="button small" disabled={busy||detail.part===0} onClick={()=>load(detail.part-1)}>Previous detail part</button><button className="button small" disabled={busy||detail.next_part==null} onClick={()=>load(detail.next_part)}>Next detail part</button></>}</>}</details>;
}
