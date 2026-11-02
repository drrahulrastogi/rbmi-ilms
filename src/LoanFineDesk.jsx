import React,{useEffect,useState} from 'react';
import {rpc,money} from './api';
import {paymentReceipt} from './register-print.mjs';

export function LoanFineDesk({institution,loanId,canCollect,canReturn,onChanged,onClose}){
 const [quote,setQuote]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[receipt,setReceipt]=useState(null);
 const [key,setKey]=useState(()=>crypto.randomUUID());
 async function refresh(){const q=await rpc('library_fine_quote',{i:institution,loan_id:loanId});setQuote(q);return q;}
 useEffect(()=>{let live=true;rpc('library_fine_quote',{i:institution,loan_id:loanId}).then(q=>{if(live)setQuote(q);}).catch(e=>{if(live)setError(e.message);});return()=>{live=false;};},[institution,loanId]);
 async function collect(e){e.preventDefault();setBusy(true);setError('');try{
  const p={...Object.fromEntries(new FormData(e.currentTarget)),id:loanId,request_key:key};
  const r=await rpc('library_action',{i:institution,action:'collect_loan_fine',p});
  const receiptPage=await rpc('library_register_page',{i:institution,kind:'collections',from_day:null,to_day:null,q:r.id,after_id:null,page_size:1});setReceipt(receiptPage.rows[0]||null);
  setKey(crypto.randomUUID());await refresh();await onChanged?.();
 }catch(e){setError(e.message);}finally{setBusy(false);}}
 async function returnBook(){setBusy(true);setError('');try{await rpc('library_action',{i:institution,action:'return',p:{id:loanId,library_code:institution}});await refresh();await onChanged?.();}catch(e){setError(e.message);await refresh().catch(()=>{});}finally{setBusy(false);}}
 async function printReceipt(){try{await paymentReceipt(receipt,institution);}catch(e){setError('Payment is saved. Receipt could not be printed: '+e.message);}}
 return <section className="panel fine-desk" aria-label="Fine check before return"><div className="panel-heading"><h2>Fine check before return</h2><button className="button" disabled={busy} onClick={onClose}>Close</button></div>{error&&<p className="alert error" role="alert">{error}</p>}{!quote?<p>Loading current fine…</p>:<>
  <p><strong>{quote.patron_name}</strong> ({quote.patron_code}) · {quote.title} · Accession {quote.accession}</p>
  <p>Due: {quote.due} · Fine starts: {quote.fine_starts||'—'} · Fine calculated through {quote.as_of}</p>
  <p>Fine: <strong>{money(quote.amount)}</strong> · Collected: <strong>{money(quote.paid)}</strong> · Remaining: <strong>{money(quote.balance)}</strong></p>
  {Number(quote.balance)>0&&!quote.returned&&<><p role="status">Return blocked. Collect the outstanding fine in the library first.</p>{canCollect?<form className="editor-form" onSubmit={collect}><p>Full fine to collect: <strong>{money(quote.balance)}</strong>. The system fixes this amount; partial payments are not permitted.</p><label>Payment method<select name="payment_method"><option value="cash">Cash</option><option value="upi">UPI</option><option value="bank">Bank transfer</option><option value="card">Card</option></select></label><label>Collection reference / note<input name="reason" defaultValue="Collected at library desk" required/></label><button className="button primary" disabled={busy}>Confirm fine collected</button></form>:<p>A librarian must collect this fine before return.</p>}</>}
  {receipt&&<p role="status">Fine collection saved. <button className="button" onClick={printReceipt}>Print payment receipt</button></p>}
  {quote.returned?<p role="status"><strong>Book returned successfully.</strong></p>:canReturn&&<button className="button primary" disabled={busy||Number(quote.balance)>0} onClick={returnBook}>Confirm book return</button>}
 </>}</section>;
}

export function FineDuePanel({institution,role,refreshKey,onChanged}){
 const [q,setQ]=useState(''),[page,setPage]=useState({rows:[],balance:0,total:0}),[error,setError]=useState(''),[loan,setLoan]=useState(null),[busy,setBusy]=useState(false);
 const canCollect=['admin','librarian'].includes(role),canReturn=['admin','librarian','assistant'].includes(role);
 useEffect(()=>{let live=true;setBusy(true);const timer=setTimeout(()=>rpc('library_fines_due',{i:institution,after_id:null,page_size:100,q}).then(p=>{if(live){setPage(p);setError('');}}).catch(e=>{if(live)setError(e.message);}).finally(()=>{if(live)setBusy(false);}),200);return()=>{live=false;clearTimeout(timer);};},[institution,q,refreshKey]);
 async function more(){setBusy(true);try{const p=await rpc('library_fines_due',{i:institution,after_id:page.next_id,page_size:100,q});setPage(old=>({...p,rows:[...old.rows,...p.rows]}));}catch(e){setError(e.message);}finally{setBusy(false);}}
 return <><section className="panel spaced registers"><div className="panel-heading"><div><h2>Fines on books still borrowed</h2><p>Live overdue fines appear before return. Existing rate, grace days and library closure rules apply.</p></div><strong>{money(page.balance)} payable</strong></div><div className="section-actions"><label>Search current fines<input aria-label="Search current fines" value={q} onChange={e=>setQ(e.target.value)} placeholder="Student name, code or accession"/></label></div>{error&&<p role="alert">{error}</p>}<div className="table-wrap"><table><thead><tr>{['Borrower','Book / accession','Due','Fine','Collected','Payable','Action'].map(h=><th key={h}>{h}</th>)}</tr></thead><tbody>{page.rows.map(r=><tr key={r.loan_id}><td>{r.patron_name}<br/>{r.patron_code}</td><td>{r.title}<br/>{r.accession}</td><td>{r.due}</td><td>{money(r.amount)}</td><td>{money(r.paid)}</td><td><strong>{money(r.balance)}</strong></td><td>{canReturn&&<button className="button small" onClick={()=>setLoan(r.loan_id)}>Review fine / return</button>}</td></tr>)}</tbody></table></div>{!busy&&!page.rows.length&&<p>No unpaid fines on active loans.</p>}{busy&&<p role="status">Loading…</p>}{page.next_id&&<button className="button" disabled={busy} onClick={more}>Load more</button>}</section>{loan&&<LoanFineDesk key={loan} institution={institution} loanId={loan} canCollect={canCollect} canReturn={canReturn} onChanged={onChanged} onClose={()=>setLoan(null)}/>}</>;
}
