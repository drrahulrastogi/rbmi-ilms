import React,{useEffect,useState} from 'react';
import {rpc,today} from './api';
import {fineMoney,fineText} from './fine-amount.jsx';
import {registerPDF} from './register-print.mjs';

export function FineMonthReports({institution,role}){
 const current=today().slice(0,7),canConsolidate=['admin','accountant'].includes(role);
 const [from,setFrom]=useState(current.slice(0,4)+'-01'),[to,setTo]=useState(current),[all,setAll]=useState(role==='accountant');
 const [rows,setRows]=useState([]),[error,setError]=useState(''),[busy,setBusy]=useState(false),[loading,setLoading]=useState(false);
 const args={i:institution,from_month:from+'-01',to_month:to+'-01',all_libraries:canConsolidate&&all};
 useEffect(()=>{let live=true;async function load(){try{const r=await rpc('library_fine_months',args);if(live){setRows(r.rows);setError('');}}catch(e){if(live)setError(e.message);}finally{if(live)setLoading(false);}}
  setLoading(true);setRows([]);load();const timer=setInterval(()=>{if(document.visibilityState!=='hidden')load();},15000);window.addEventListener('focus',load);
  return()=>{live=false;clearInterval(timer);window.removeEventListener('focus',load);};
 },[institution,from,to,all,canConsolidate]);
 const total=rows.reduce((n,r)=>n+Number(r.total),0),deposited=rows.reduce((n,r)=>n+Number(r.deposited),0),pending=rows.reduce((n,r)=>n+Number(r.pending),0);
 async function pdf(){setBusy(true);setError('');try{
  const report=await rpc('library_fine_months',args),items=report.rows;
  const slip=await rpc('library_print_slip',{i:institution,kind:'collections',filters:{report:'monthly_consolidated',from,to,all:args.all_libraries},request_key:crypto.randomUUID()});
  const sums=items.reduce((s,r)=>s.map((v,n)=>v+Number(r[['total','deposited','pending'][n]])),[0,0,0]);
  await registerPDF('Consolidated monthly fine report',['Slip number: '+slip.slip_no,'Prepared by: '+slip.actor_name,'Libraries: '+(args.all_libraries?'All assigned libraries':institution),'Months: '+from+' to '+to,'Collected: INR '+sums[0].toFixed(2)+' / Deposited: INR '+sums[1].toFixed(2)+' / Pending: INR '+sums[2].toFixed(2)],
   ['Month','Library','Receipts','Collected INR','Deposited INR','Pending INR','Status','Verified by / date / reference'],
   [...items.map(r=>[r.month.slice(0,7),r.institution_id,r.receipts,Number(r.total).toFixed(2),Number(r.deposited).toFixed(2),Number(r.pending).toFixed(2),r.status,[r.verified_by_name,r.verified_at,r.verification_reference].filter(Boolean).join(' / ')||'Awaiting verification']),['TOTAL','','',...sums.map(n=>n.toFixed(2)),'','']]);
 }catch(e){setError(e.message);}finally{setBusy(false);}}
 return <section className="panel spaced registers"><div className="panel-heading"><div><h2>Month-wise fine reports</h2><p>Track each month's submission and Accounts verification. Updates appear automatically. Use the monthly statement above for the student-wise PDF.</p></div></div>
  <div className="section-actions"><label>From month<input type="month" max={to} value={from} onChange={e=>setFrom(e.target.value)}/></label><label>To month<input type="month" min={from} max={current} value={to} onChange={e=>setTo(e.target.value)}/></label>{canConsolidate&&<label><input type="checkbox" checked={all} onChange={e=>setAll(e.target.checked)}/>All assigned libraries</label>}<button className="button" disabled={busy||loading||!!error} onClick={pdf}>Export consolidated PDF</button></div>
  {error&&<p role="alert">{fineText(error)}</p>}{loading&&<p role="status">Loading monthly reports…</p>}<p>Collected {fineMoney(total)} · Deposited {fineMoney(deposited)} · Pending {fineMoney(pending)}</p>
  <div className="table-wrap"><table><thead><tr>{['Month','Library','Receipts','Collected','Deposited','Pending','Status','Accounts verification'].map(h=><th key={h}>{h}</th>)}</tr></thead><tbody>{rows.map(r=><tr key={r.institution_id+r.month}><td>{r.month.slice(0,7)}</td><td>{r.library_name}</td><td>{r.receipts}</td><td>{fineMoney(r.total)}</td><td>{fineMoney(r.deposited)}</td><td>{fineMoney(r.pending)}</td><td>{r.status}</td><td>{r.verified_by_name||'Awaiting verification'}<br/>{r.verified_at}<br/>{r.verification_reference}</td></tr>)}</tbody></table></div>{!loading&&!rows.length&&!error&&<p>No fine collections or statements in this period.</p>}
 </section>;
}
