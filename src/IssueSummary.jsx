import React,{useEffect,useState} from 'react';
import {rpc} from './api';

const date=value=>value?new Intl.DateTimeFormat('en-IN',{day:'2-digit',month:'short',year:'numeric'}).format(new Date(value+'T12:00:00')):'—';

export function IssueSummary({institution,loan,onClose}){
 const [quote,setQuote]=useState(null),[error,setError]=useState(''),[attempt,setAttempt]=useState(0);
 useEffect(()=>{let live=true;setError('');rpc('library_fine_quote',{i:institution,loan_id:loan.id}).then(q=>{if(live)setQuote(q);}).catch(e=>{if(live)setError(e.message);});return()=>{live=false;};},[institution,loan.id,attempt]);
 return <section className="issue-summary" aria-label="Book issue summary" aria-live="polite">
  <p>The book has been issued successfully.</p>
  <dl><dt>Student / borrower name</dt><dd>{quote?.patron_name||'Loading borrower name…'}</dd>
   <dt>Student / borrower code</dt><dd>{quote?.patron_code||loan.patron_code_snapshot}</dd>
   <dt>Book</dt><dd>{quote?.title||loan.issue_title}</dd>
   <dt>Accession number</dt><dd>{quote?.accession||loan.issue_accession}</dd>
   <dt>Issue date</dt><dd>{date(loan.issued)}</dd>
   <dt>Return due date</dt><dd>{date(loan.due)}</dd>
   <dt>Fine starts on</dt><dd>{quote?(quote.fine_starts?date(quote.fine_starts):'No fine under this loan policy'):'Loading fine start date…'}</dd>
  </dl>
  {error?<div className="alert error" role="alert"><p>The book is already issued. Its remaining summary details could not be loaded: {error}</p><button className="button" onClick={()=>setAttempt(n=>n+1)}>Retry summary</button></div>:<p className="muted">Return by the due date. The fine start date accounts for grace days, holidays and library closures.</p>}
  <button className="button primary" onClick={onClose}>Done</button>
 </section>;
}
