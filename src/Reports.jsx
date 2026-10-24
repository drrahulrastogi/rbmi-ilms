import React,{useDeferredValue,useEffect,useMemo,useRef,useState} from 'react';
import {assetURL,rpc,today} from './api';
import {buildStandardReports,buildSavedReport,filterReportRows,formatReportValue,reportFileName} from './report-model.mjs';
import {reportCSV,saveReportFile} from './report-download.mjs';

export function Reports({data,institution,manage,form}){
 const reports=useMemo(()=>buildStandardReports(data,institution,today()),[data,institution]);
 const [selected,setSelected]=useState(''),[saved,setSaved]=useState(null),[query,setQuery]=useState(''),[page,setPage]=useState(1),[pageSize,setPageSize]=useState(50),[running,setRunning]=useState(false),[pdf,setPdf]=useState(null),[notice,setNotice]=useState(''),[error,setError]=useState('');
 const workerRef=useRef(null),headingRef=useRef(null),deferred=useDeferredValue(query),filtering=query!==deferred;
 const report=reports.find(r=>r.id===selected)||(saved?.id===selected?saved:null);
 const filtered=useMemo(()=>report?filterReportRows(report,deferred):[],[report,deferred]);
 const pages=Math.max(1,Math.ceil(filtered.length/pageSize)),currentPage=Math.min(page,pages),start=(currentPage-1)*pageSize;
 useEffect(()=>()=>{workerRef.current?.terminate();workerRef.current=null;},[]);
 useEffect(()=>{if(selected){headingRef.current?.focus({preventScroll:true});headingRef.current?.scrollIntoView({block:'start'});}},[selected]);
 function view(r){setSelected(r.id);setQuery('');setPage(1);setError('');}
 function csv(r){saveReportFile(reportFileName(r,'csv',today()),reportCSV(r),'text/csv;charset=utf-8');setNotice(`${r.rows.length.toLocaleString('en-IN')} records exported to CSV.`);}
 function cancelPDF(){workerRef.current?.terminate();workerRef.current=null;setPdf(null);setNotice('PDF export cancelled.');}
 function pdfExport(r){
  if(workerRef.current)return;setError('');setNotice('');setPdf({name:r.name,pages:0});
  try{
   const worker=new Worker(new URL('./report-pdf.worker.mjs',import.meta.url),{type:'module'});workerRef.current=worker;
   const finish=()=>{worker.terminate();workerRef.current=null;setPdf(null);};
   worker.onmessage=({data:message})=>{if(workerRef.current!==worker)return;
    if(message.type==='progress')setPdf({name:r.name,pages:message.pages});
    if(message.type==='error'){setError(message.message);finish();}
    if(message.type==='complete'){saveReportFile(reportFileName(r,'pdf',today()),message.buffer,'application/pdf');setNotice(`${r.rows.length.toLocaleString('en-IN')} records exported to PDF.`);finish();}
   };
   worker.onerror=()=>{if(workerRef.current!==worker)return;setError('PDF export could not finish. Please retry.');finish();};
   worker.postMessage({report:{...r,libraryName:data.library?.name||institution},fontURL:new URL(assetURL('fonts/NotoSans-Regular.ttf'),location.href).href,logoURL:new URL(assetURL('rbmi-logo.png'),location.href).href});
  }catch{workerRef.current?.terminate();workerRef.current=null;setPdf(null);setError('PDF export is unavailable in this browser. Please use a current browser.');}
 }
 async function runSaved(definition){setRunning(true);setError('');try{const rows=await rpc('library_report',{i:institution,report_id:definition.id}),result=buildSavedReport(definition,rows,data,institution,today());setSaved(result);view(result);}catch(err){setError(err.message);}finally{setRunning(false);}}
 const selectedExport=report?{...report,rows:filtered,filterDescription:deferred.trim()?'Search: '+deferred.trim():''}:null;
 const field=(name,label,type='text',extra={})=>({name,label,type,...extra});
 return <>
  {notice&&<p className="alert success" role="status">{notice}</p>}{error&&<p className="alert error" role="alert">{error}</p>}
  {pdf&&<div className="alert report-progress" role="status"><span>Preparing {pdf.name} PDF{pdf.pages?` · ${pdf.pages} pages prepared`:'…'} · You can keep using this page.</span><button className="button small" onClick={cancelPDF}>Cancel PDF</button></div>}
  <div className="report-grid">{reports.map(r=><section className="panel report-card" key={r.id}><h2>{r.name}</h2><p>{r.description}</p><span>{r.rows.length.toLocaleString('en-IN')} records</span><div className="report-actions"><button className="button primary" onClick={()=>view(r)} aria-label={'View '+r.name}>View report</button><button className="button" onClick={()=>csv(r)} aria-label={'Export '+r.name+' CSV'}>Export CSV</button><button className="button" disabled={!!pdf} onClick={()=>pdfExport(r)} aria-label={'Export '+r.name+' PDF'}>Export PDF</button></div></section>)}</div>
  <section className="panel spaced"><div className="panel-heading"><div><h2>Saved report builder</h2><p>Run a saved report to view its results below, then export CSV or PDF. Date limits apply to circulation, acquisitions and journal issues.</p></div>{manage&&<button className="button" onClick={()=>form('Save report definition','save_report',[field('name','Report name'),field('dataset','Dataset','select',{options:['loans','copies','patrons','fines','acquisitions','serial_issues']}),field('start','From date','date',{required:false}),field('end','To date','date',{required:false})])}>Create report</button>}</div><div className="table-scroll"><table><thead><tr><th>Report</th><th>Dataset</th><th>Date limits</th><th>Action</th></tr></thead><tbody>{(data.saved_reports||[]).map(r=><tr key={r.id}><td>{r.name}</td><td>{r.dataset}</td><td>{['loans','acquisitions','serial_issues'].includes(r.dataset)?(r.definition?.start||'Any start')+' — '+(r.definition?.end||'Any end'):'Current snapshot'}</td><td><button className="button small" disabled={running} onClick={()=>runSaved(r)}>Run / view report</button></td></tr>)}</tbody></table>{!data.saved_reports?.length&&<p className="drawer-description">No saved report definitions yet. You can view the standard reports above.</p>}</div></section>
  {report&&<section className="panel spaced report-viewer" aria-labelledby="report-view-title"><div className="panel-heading"><div><h2 id="report-view-title" tabIndex={-1} ref={headingRef}>{report.name}</h2><p>{institution} · {report.description}</p></div><div className="report-actions"><button className="button" disabled={filtering} onClick={()=>csv(selectedExport)}>Export CSV</button><button className="button primary" disabled={!!pdf||filtering} onClick={()=>pdfExport(selectedExport)}>Export PDF</button><button className="button" onClick={()=>setSelected('')}>Close report</button></div></div><div className="report-filters"><label>Search this report<input type="search" maxLength={200} value={query} onChange={e=>{setQuery(e.target.value);setPage(1);}} placeholder="Search any displayed column"/></label><label>Rows per page<select value={pageSize} onChange={e=>{setPageSize(Number(e.target.value));setPage(1);}}>{[25,50,100].map(n=><option key={n} value={n}>{n}</option>)}</select></label><p role="status">{filtered.length?`${start+1}–${Math.min(start+pageSize,filtered.length)}`:'0'} of {filtered.length.toLocaleString('en-IN')} matching records ({report.rows.length.toLocaleString('en-IN')} total). Exports include every matching row.</p></div><div className="table-scroll report-table" tabIndex={0} role="region" aria-label={report.name+' results'}><table><thead><tr>{report.columns.map(col=><th key={col.key} data-col={col.key}>{col.label}</th>)}</tr></thead><tbody>{filtered.slice(start,start+pageSize).map((row,n)=><tr key={start+n}>{report.columns.map(col=><td key={col.key} data-col={col.key}>{formatReportValue(row[col.key],col)}</td>)}</tr>)}</tbody></table>{!filtered.length&&<p className="drawer-description">{report.rows.length?'No records match your search.':'No records in this report.'}</p>}</div><div className="report-pagination"><button className="button" disabled={currentPage===1} onClick={()=>setPage(Math.max(1,currentPage-1))}>Previous page</button><span>Page {currentPage} of {pages}</span><button className="button" disabled={currentPage===pages} onClick={()=>setPage(Math.min(pages,currentPage+1))}>Next page</button></div></section>}
 </>;
}
