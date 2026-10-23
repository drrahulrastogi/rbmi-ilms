import Papa from 'papaparse';

export function parseHolidayCSV(text) {
 const parsed=Papa.parse(text.replace(/^\uFEFF/,''),{header:true,skipEmptyLines:'greedy',transformHeader:h=>h.trim().toLowerCase()});
 const errors=parsed.errors.map(e=>`CSV row ${(e.row??0)+2}: ${e.message}`),fields=parsed.meta.fields||[];
 if(fields.length!==2||!fields.includes('date')||!fields.includes('name'))errors.push('Use exactly these two column headers: date,name.');
 if(parsed.data.length<1||parsed.data.length>1000)errors.push('Upload 1 to 1000 holidays per file.');
 const dates=new Set(),rows=parsed.data.map((r,n)=>{
  const day=String(r.date||'').trim(),name=String(r.name||'').trim(),d=new Date(day+'T00:00:00Z');
  if(!/^\d{4}-\d{2}-\d{2}$/.test(day)||!Number.isFinite(d.getTime())||d.toISOString().slice(0,10)!==day||day<'1900-01-01'||day>'2100-12-31')errors.push(`Row ${n+2}: use a valid date in YYYY-MM-DD format (1900–2100).`);
  if(!name||name.length>200)errors.push(`Row ${n+2}: holiday name must contain 1 to 200 characters.`);
  if(dates.has(day))errors.push(`Row ${n+2}: duplicate date ${day}.`);
  dates.add(day);return {day,name};
 });
 return {rows,errors};
}
