import {makeReport} from './report-model.mjs';
export function circulationReport(rows,institution,libraryName,filters,today){
 const columns=[['accession','Accession'],['barcode','Barcode'],['title','Book'],['patron_code','Patron code'],['patron','Patron'],['issued','Issued'],['due','Due'],['returned','Returned'],['status','Status']].map(([key,label])=>({key,label}));
 return {...makeReport('circulation','Circulation history','Issues and returns matching the selected filters.',rows.map(l=>({accession:l._accession||l.issue_accession||'',barcode:l._barcode||l.issue_barcode||'',title:l._title||l.issue_title||'',patron_code:l._patron_code||l.patron_code_snapshot||'',patron:l._patron_name||'',issued:l.issued,due:l.due,returned:l.returned||'',status:l.returned?'Returned':l.due<today?'Overdue':'On loan'})),columns,institution),libraryName,
 dateDescription:filters.day?`${filters.dateField} on ${filters.day}`:'All dates',filterDescription:`Status: ${filters.status}${filters.query?' | Search: '+filters.query:''}`};
}
