import Papa from 'papaparse';
import {formatReportValue} from './report-model.mjs';
export function reportCSV(report){
 const safe=v=>typeof v==='string'&&/^\s*[=+@\-]/.test(v)?"'"+v:v;
 return '\ufeff'+Papa.unparse({fields:report.columns.map(c=>c.label),data:report.rows.map(row=>report.columns.map(col=>safe(formatReportValue(row[col.key],col))))});
}
export function saveReportFile(name,content,type){
 const blob=new Blob([content],{type}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);
}
