import {fineMoney,fineText} from './fine-amount.jsx';
import React,{useEffect,useState} from 'react';
import {rpc,money} from './api';
import {paymentReceipt,receiptNumber} from './register-print.mjs';

export function MyPaymentReceipts({institution,refreshKey}){
 const [page,setPage]=useState({rows:[],total:0}),[loading,setLoading]=useState(false),[printing,setPrinting]=useState(null),[error,setError]=useState('');
 useEffect(()=>{let live=true;setLoading(true);setError('');setPage({rows:[],total:0});rpc('library_my_receipts',{i:institution,after_id:null,page_size:100}).then(r=>{if(live)setPage(r);}).catch(e=>{if(live)setError(e.message);}).finally(()=>{if(live)setLoading(false);});return()=>{live=false;};},[institution,refreshKey]);
 async function more(){setLoading(true);setError('');try{const r=await rpc('library_my_receipts',{i:institution,after_id:page.next_id,page_size:100});setPage(old=>({...r,rows:[...old.rows,...r.rows]}));}catch(e){setError(e.message);}finally{setLoading(false);}}
 async function download(row){setPrinting(row.id);setError('');try{await paymentReceipt(row,institution);}catch(e){setError('Unable to download receipt: '+e.message);}finally{setPrinting(null);}}
 return <section className="panel spaced registers"><div className="panel-heading"><div><h2>My paid fines & receipts</h2><p>Download a receipt for each payment recorded by your library. Reprints keep the original slip number.</p></div></div>{error&&<p className="alert error" role="alert">{fineText(error)}</p>}
  <div className="table-wrap"><table><thead><tr>{['Payment date','Slip number','Amount paid','Method','Collected by','Receipt'].map(h=><th key={h}>{h}</th>)}</tr></thead><tbody>{page.rows.map(r=><tr key={r.id}><td>{r.collected_on}</td><td>{receiptNumber(r)}</td><td>{fineMoney(r.amount)}</td><td>{r.payment_method}</td><td>{r.actor_name||'Name not recorded'}</td><td><button className="button small" disabled={printing!==null} onClick={()=>download(r)}>{printing===r.id?'Preparing…':'Download receipt PDF'}</button></td></tr>)}</tbody></table></div>
  {loading&&<p role="status">Loading your receipts…</p>}{!loading&&!page.rows.length&&!error&&<p>No fine payments have been recorded for your account yet.</p>}{page.next_id&&<button className="button" disabled={loading} onClick={more}>Load more receipts</button>}
 </section>;
}
