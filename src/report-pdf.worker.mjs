import {buildReportPDF} from './report-pdf.mjs';
self.onmessage=async({data})=>{
 try{
  const [fontResponse,logoResponse]=await Promise.all([fetch(data.fontURL),fetch(data.logoURL)]);
  if(!fontResponse.ok)throw Error('Report font could not be loaded. Refresh the page and retry.');
  const [fontBytes,logoBytes]=await Promise.all([fontResponse.arrayBuffer(),logoResponse.ok?logoResponse.arrayBuffer():null]);
  const buffer=buildReportPDF(data.report,{fontBytes,logoBytes,onPage:pages=>{if(pages%10===0)self.postMessage({type:'progress',pages});}});
  self.postMessage({type:'complete',buffer},[buffer]);
 }catch(error){self.postMessage({type:'error',message:error.message||'PDF export failed'});}
};
