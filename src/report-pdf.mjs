import {jsPDF} from 'jspdf';
import {autoTable} from 'jspdf-autotable';
import {formatReportValue} from './report-model.mjs';

export function buildReportPDF(report,{fontBytes,logoBytes,generatedAt=new Date(),onPage=()=>{}}){
 const doc=new jsPDF({orientation:'landscape',unit:'pt',format:'a4',compress:true});
 const bytes=new Uint8Array(fontBytes);if(bytes.length<10000)throw Error('Report font could not be loaded');
 let binary='';for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));
 doc.addFileToVFS('NotoSans-Regular.ttf',btoa(binary));doc.addFont('NotoSans-Regular.ttf','RBMINoto','normal');doc.setFont('RBMINoto','normal');
 doc.setProperties({title:report.name,subject:report.institution+' library report',author:'RBMI Library Network',creator:'RBMI ILMS'});
 const width=doc.internal.pageSize.getWidth(),height=doc.internal.pageSize.getHeight();
 const stamp=new Intl.DateTimeFormat('en-IN',{timeZone:'Asia/Kolkata',dateStyle:'medium',timeStyle:'short'}).format(new Date(generatedAt));
 const filters=[report.dateDescription,report.filterDescription].filter(Boolean).join(' | ');
 doc.setFontSize(9);const filterLines=filters?doc.splitTextToSize(filters,width-72).slice(0,2):[],tableTop=96+13*filterLines.length;
 const count=report.rows.length.toLocaleString('en-IN'),header=()=>{
  if(logoBytes)doc.addImage(new Uint8Array(logoBytes),'PNG',36,22,72,20);
  doc.setFont('RBMINoto','normal');doc.setTextColor(24,61,43);doc.setFontSize(14);doc.text(doc.splitTextToSize(report.name,width-164).slice(0,2),122,35);
  doc.setFontSize(9);doc.setTextColor(45,61,53);doc.text(`${report.institution} | ${report.libraryName||'RBMI Library Network'}`,36,68);doc.text(`${count} matching records | Generated ${stamp} IST`,36,82);
  if(filterLines.length)doc.text(filterLines,36,95);
 };
 if(report.rows.length){
  autoTable(doc,{columns:report.columns.map(c=>({header:c.label,dataKey:c.key})),body:report.rows.map(row=>Object.fromEntries(report.columns.map(col=>[col.key,formatReportValue(row[col.key],col)]))),startY:tableTop,margin:{top:tableTop,bottom:42,left:36,right:36},styles:{font:'RBMINoto',fontStyle:'normal',fontSize:7.5,cellPadding:4,overflow:'linebreak',minCellWidth:32,lineColor:[218,228,222],lineWidth:0.2},columnStyles:{row_no:{cellWidth:30},library:{cellWidth:43}},headStyles:{fillColor:[29,85,61],textColor:[255,255,255],fontStyle:'normal'},alternateRowStyles:{fillColor:[245,249,246]},showHead:'everyPage',rowPageBreak:'avoid',horizontalPageBreak:true,horizontalPageBreakRepeat:'row_no',didDrawPage:()=>{header();onPage(doc.getNumberOfPages());}});
 }else{header();doc.setFontSize(11);doc.text('No matching records.',36,126);}
 const pages=doc.getNumberOfPages();
 for(let p=1;p<=pages;p++){doc.setPage(p);doc.setFont('RBMINoto','normal');doc.setFontSize(8);doc.setTextColor(80,97,88);doc.setDrawColor(207,222,213);doc.line(36,height-30,width-36,height-30);doc.text(`${report.institution} | ${count} matching records`,36,height-17);doc.text(`Page ${p} of ${pages}`,width-36,height-17,{align:'right'});}
 return doc.output('arraybuffer');
}
