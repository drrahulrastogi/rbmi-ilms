export function normalizePatronRow(row) {
 const active=String(row.active??'').trim().toLowerCase(),expires=String(row.expires??'').trim();
 const errors=[];
 if(active&&!['true','false'].includes(active))errors.push('active must be TRUE or FALSE (blank means TRUE)');
 if(expires){
  const date=new Date(expires+'T00:00:00Z');
  if(!/^\d{4}-\d{2}-\d{2}$/.test(expires)||!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==expires)errors.push('expires must be a valid YYYY-MM-DD date, for example 2029-12-31, or blank');
 }
 return {row:{...row,active:active===''||active==='true',expires},errors};
}
