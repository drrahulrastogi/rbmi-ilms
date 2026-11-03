import React,{useState} from 'react';
import {assetURL} from './api';
import {parseHolidayCSV} from './holiday-import.mjs';

export function HolidayCalendar({institution,holidays,canManage,busy,form,run}) {
 const [upload,setUpload]=useState(null),[errors,setErrors]=useState([]),[reading,setReading]=useState(false);
 async function choose(e){
  const file=e.target.files?.[0];setUpload(null);setErrors([]);if(!file)return;
  if(file.size>512000){setErrors(['Choose a CSV or TXT file smaller than 500 KB.']);return;}
  setReading(true);
  try{const result=parseHolidayCSV(await file.text());setErrors(result.errors);setUpload({file:file.name,rows:result.rows});}
  catch{setErrors(['The file could not be read. Save the template as CSV UTF-8 and try again.']);}
  finally{setReading(false);}
 }
 return <section className="panel spaced" aria-labelledby="holiday-heading">
  <div className="panel-heading"><div><h2 id="holiday-heading">Holiday calendar</h2><p>{institution} · Holiday dates are excluded from overdue fines. New due dates move to the next open day.</p></div>{canManage&&<button className="button" disabled={busy} onClick={()=>form('Add / update holiday','holiday',[{name:'day',label:'Date',type:'date'},{name:'name',label:'Holiday name',type:'text',maxLength:200}])}>Add additional holiday</button>}</div>
  <div className="section-actions"><a className="button" href={assetURL('templates/holiday-calendar-template.csv')} download="RBMI-Holiday-Calendar-Template.csv">Download holiday template (CSV)</a></div>
  {canManage?<div className="holiday-import">
   <p>Fill the template with one approved holiday per row: <code>date,name</code>, for example <code>2027-01-26,Republic Day</code>. Dates may use YYYY-MM-DD, DD/MM/YYYY, DD-MM-YYYY or DD.MM.YYYY. For example, <code>05/06/2027</code> means 5 June. Enter actual dates, not the format labels. Save as CSV UTF-8 or comma/tab-separated text. Review the dates shown as YYYY-MM-DD below before approving. Upload up to 1,000 dates for <strong>{institution}</strong>. Other libraries keep their own calendars.</p>
   <label>Upload holiday calendar (CSV or TXT)<input type="file" accept=".csv,.txt,text/csv,text/plain" disabled={busy||reading} onChange={choose}/></label>
   {reading&&<p role="status">Reading holiday file…</p>}
   {!!errors.length&&<div className="alert error" role="alert"><strong>Nothing saved. Correct the following and upload again:</strong><ul>{errors.slice(0,20).map((e,n)=><li key={n}>{e}</li>)}</ul>{errors.length>20&&<p>{errors.length-20} more errors.</p>}</div>}
   {upload&&!errors.length&&<><p role="status"><strong>{upload.rows.length} holidays ready for {institution}</strong> · {upload.file}. Existing dates update their names; all other calendar dates are retained.</p><div className="table-scroll"><table><thead><tr><th>Date</th><th>Holiday</th><th>Action</th></tr></thead><tbody>{upload.rows.slice(0,25).map(r=><tr key={r.day}><td>{r.day}</td><td>{r.name}</td><td>{holidays.some(h=>h.day===r.day)?'Update name':'Add holiday'}</td></tr>)}</tbody></table></div>{upload.rows.length>25&&<p>Showing the first 25 of {upload.rows.length} holidays.</p>}<button className="button primary" disabled={busy||reading} onClick={async()=>{if(await run('holiday_import',{rows:upload.rows},`${upload.rows.length} holidays saved for ${institution}. These dates are excluded from fines.`))setUpload(null);}}>{busy?'Saving…':`Approve and import ${upload.rows.length} holidays`}</button></>}
   <p>Administrators and the assigned librarian can upload or add holidays for this library. Calendar changes apply when an overdue fine is assessed on return. Already assessed fines remain in the audit history; fine waivers are disabled for everyone.</p>
  </div>:<p className="drawer-description">Ask the administrator or assigned librarian to upload the calendar or add a holiday.</p>}
  <div className="table-scroll"><table><thead><tr><th>Date</th><th>Holiday</th></tr></thead><tbody>{[...holidays].sort((a,b)=>a.day.localeCompare(b.day)).map(h=><tr key={h.id||h.day}><td>{h.day}</td><td>{h.name}</td></tr>)}</tbody></table>{!holidays.length&&<p className="drawer-description">No holidays recorded for this library.</p>}</div>
 </section>;
}
