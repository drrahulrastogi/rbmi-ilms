export async function readAllPages(request,name,args,{limit=50000,onProgress=()=>{},signal}={}){
 let rows=[],after_id=null;const seen=new Set();do{
  if(signal?.aborted)throw Error('Report preparation cancelled');
  const page=await request(name,{...args,after_id,page_size:1000});
  if(!Array.isArray(page?.rows))throw Error('Invalid page response');
  rows.push(...page.rows);if(rows.length>limit)throw Error('Report exceeds 50,000 records. Use a saved report with a narrower date range.');onProgress(rows.length);
  after_id=page.next_id;if(after_id&&seen.has(after_id))throw Error('Page cursor repeated; refresh and retry');if(after_id)seen.add(after_id);
 }while(after_id);return rows;
}
export async function reportSources(request,data,institution,id,options){
 const needs={collection:[],circulation:['patrons','loans'],overdue:['patrons','loans'],fines:['patrons','fines'],patrons:['patrons'],acquisitions:['acquisitions','vendors'],borrowed:['loans'],serial_issues:['subscriptions']}[id]||[];
 const parts=await Promise.all(needs.map(async kind=>[kind,await readAllPages(request,'library_records_page',{i:institution,kind,q:''},options)]));return {...data,...Object.fromEntries(parts)};
}
