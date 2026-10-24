const c=(key,label,format)=>({key,label,format});
const scope=(rows,i)=>(rows||[]).filter(r=>r.institution_id===i);
const number=v=>Number.isFinite(Number(v))?Number(v):0;
const library=c('library','Library'),rowNumber=c('row_no','#');
export function makeReport(id,name,description,rows,columns,institution){
 const safeColumns=[rowNumber,...columns.filter(x=>!/(password|secret|token|policy)/i.test(x.key))];
 return {id,name,description,institution,columns:safeColumns,rows:rows.map((r,n)=>Object.fromEntries(safeColumns.map(col=>[col.key,col.key==='row_no'?n+1:r[col.key]??''])))};
}
export function buildStandardReports(data,i,today){
 const titles=new Map(scope(data.titles,i).map(t=>[t.id,t])),copies=new Map(scope(data.copies,i).map(c=>[c.id,c])),patrons=new Map(scope(data.patrons,i).map(p=>[p.id,p])),vendors=new Map(scope(data.vendors,i).map(v=>[v.id,v]));
 const loans=scope(data.loans,i).map(l=>{const copy=copies.get(l.copy_id),title=titles.get(copy?.title_id),patron=patrons.get(l.patron_id);return {library:i,accession:copy?.accession||l.issue_accession||'',barcode:copy?.barcode||l.issue_barcode||'',title:title?.title||l.issue_title||'',patron_code:patron?.code||l.issue_patron_code||'',patron:patron?.name||l.issue_patron_name||'',issued:l.issued,due:l.due,returned:l.returned||'',renewals:l.renewals,status:l.returned?'Returned':l.due<today?'Overdue':'On loan'};});
 const loanColumns=[library,c('accession','Accession'),c('barcode','Barcode'),c('title','Title'),c('patron_code','Patron code'),c('patron','Patron'),c('issued','Issued'),c('due','Due'),c('returned','Returned'),c('renewals','Renewals'),c('status','Status')];
 const counts=new Map();for(const l of scope(data.loans,i)){const tid=copies.get(l.copy_id)?.title_id;if(tid)counts.set(tid,(counts.get(tid)||0)+1);}
 return [
  makeReport('collection','Collection register','All physical copies and their current status.',scope(data.copies,i).map(copy=>{const t=titles.get(copy.title_id)||{};return {library:i,accession:copy.accession,barcode:copy.barcode,title:t.title,author:t.author,isbn:t.isbn,classification:t.classification,shelf:copy.shelf,status:copy.status,price:number(copy.price)};}).sort((a,b)=>String(a.accession).localeCompare(String(b.accession),undefined,{numeric:true})),[library,c('accession','Accession'),c('barcode','Barcode'),c('title','Title'),c('author','Author'),c('isbn','ISBN'),c('classification','Class / DDC'),c('shelf','Shelf'),c('status','Status'),c('price','Price (INR)','money')],i),
  makeReport('circulation','Circulation history','Issue, renewal and return history.',loans,loanColumns,i),
  makeReport('overdue','Overdue register','Active loans past their due date.',loans.filter(l=>l.status==='Overdue'),loanColumns.filter(x=>!['returned','renewals'].includes(x.key)),i),
  makeReport('fines','Fine balances','Assessed, paid, waived and outstanding amounts.',scope(data.fines,i).map(f=>{const p=patrons.get(f.patron_id);return {library:i,patron_code:p?.code,patron:p?.name,assessed:number(f.amount),paid:number(f.paid),waived:number(f.waived),balance:Math.round((number(f.amount)-number(f.paid)-number(f.waived))*100)/100};}),[library,c('patron_code','Patron code'),c('patron','Patron'),c('assessed','Assessed (INR)','money'),c('paid','Paid (INR)','money'),c('waived','Waived (INR)','money'),c('balance','Balance (INR)','money')],i),
  makeReport('patrons','Patron register','Student, faculty and other borrowing memberships.',scope(data.patrons,i).map(p=>({library:i,code:p.code,name:p.name,email:p.email,category:p.category,institute:p.profile?.institute||i,department:p.department,active:!p.active?'Inactive':p.expires&&p.expires<today?'Expired':'Active',expires:p.expires||''})),[library,c('code','Patron code'),c('name','Name'),c('email','Email'),c('category','Category'),c('institute','Institute'),c('department','Department'),c('active','Membership'),c('expires','Expires')],i),
  makeReport('acquisitions','Acquisition register','Orders, vendors, quantities, values and received stock.',scope(data.acquisitions,i).map(a=>({library:i,reference:a.invoice,title:titles.get(a.title_id)?.title,vendor:vendors.get(a.vendor_id)?.name,quantity:a.quantity,unit_price:number(a.unit_price),value:number(a.quantity)*number(a.unit_price),ordered:a.ordered_at,received:a.received_at||'',status:a.status})),[library,c('reference','Reference'),c('title','Title'),c('vendor','Vendor'),c('quantity','Copies'),c('unit_price','Unit price (INR)','money'),c('value','Value (INR)','money'),c('ordered','Ordered'),c('received','Received'),c('status','Status')],i),
  makeReport('borrowed','Most borrowed titles','Titles ranked by number of recorded issues.',[...titles.values()].map(t=>({library:i,title:t.title,author:t.author,isbn:t.isbn,issues:counts.get(t.id)||0})).filter(t=>t.issues).sort((a,b)=>b.issues-a.issues||a.title.localeCompare(b.title)),[library,c('title','Title'),c('author','Author'),c('isbn','ISBN'),c('issues','Total issues')],i)
 ];
}
export function buildSavedReport(definition,rows,data,i,today){
 const id={copies:'collection',loans:'circulation',patrons:'patrons',fines:'fines',acquisitions:'acquisitions'}[definition.dataset];
 let report;
 if(id)report=buildStandardReports({...data,[definition.dataset]:rows},i,today).find(r=>r.id===id);
 else if(definition.dataset==='serial_issues'){
  const subscriptions=new Map(scope(data.subscriptions,i).map(s=>[s.id,s]));
  report=makeReport('serial_issues',definition.name,'Predicted and received journal issues.',scope(rows,i).map(r=>({library:i,title:subscriptions.get(r.subscription_id)?.title||'',sequence:r.number,due:r.due,received:r.received||'',status:r.status})),[library,c('title','Journal'),c('sequence','Sequence'),c('due','Expected'),c('received','Received'),c('status','Status')],i);
 }else throw Error('Unsupported report dataset');
 const dated=['loans','acquisitions','serial_issues'].includes(definition.dataset),dates=dated?(definition.definition||{}):{};
 return {...report,id:'saved-'+definition.id,name:definition.name,dateDescription:[dates.start?'From '+dates.start:'',dates.end?'Through '+dates.end:''].filter(Boolean).join(' | '),description:`Saved ${definition.dataset} report. ${dated?'':'Current snapshot; date limits do not apply. '}${dates.start?'From '+dates.start+'. ':''}${dates.end?'Through '+dates.end+'. ':''}`.trim()};
}
export function formatReportValue(value,column){if(value==null)return '';if(column.format==='money')return number(value).toFixed(2);return String(value);}
export function filterReportRows(report,query){const q=query.trim().toLocaleLowerCase();return q?report.rows.filter(row=>report.columns.some(col=>formatReportValue(row[col.key],col).toLocaleLowerCase().includes(q))):report.rows;}
export function reportFileName(report,extension,date){return `${report.institution}-${report.name.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')||'report'}-${date}.${extension}`;}
