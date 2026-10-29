import Papa from 'papaparse';

export function normalizeHolidayDate(value) {
 const text=String(value??'').trim();
 const iso=text.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$/);
 const indian=text.match(/^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})$/);
 if(!iso&&!indian)return null;
 const [year,month,day]=(iso?[iso[1],iso[2],iso[3]]:[indian[3],indian[2],indian[1]]).map(Number);
 if(year<1900||year>2100||month<1||month>12||day<1||day>31)return null;
 const date=new Date(Date.UTC(year,month-1,day));
 if(date.getUTCFullYear()!==year||date.getUTCMonth()!==month-1||date.getUTCDate()!==day)return null;
 return `${year}-${String(month).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
}

export function parseHolidayCSV(text) {
 const parsed=Papa.parse(text.replace(/^\uFEFF/,''),{header:true,skipEmptyLines:'greedy',transformHeader:h=>h.trim().toLowerCase()});
 const errors=parsed.errors.map(e=>`CSV row ${(e.row??0)+2}: ${e.message}`),fields=parsed.meta.fields||[];
 if(fields.length!==2||!fields.includes('date')||!fields.includes('name'))errors.push('Use exactly these two column headers: date,name.');
 if(parsed.data.length<1||parsed.data.length>1000)errors.push('Upload 1 to 1000 holidays per file.');
 const dates=new Set(),rows=parsed.data.map((r,n)=>{
  const sourceDate=String(r.date||'').trim(),day=normalizeHolidayDate(sourceDate),name=String(r.name||'').trim();
  if(!day)errors.push(`Row ${n+2}: invalid date ${JSON.stringify(sourceDate)}. Use YYYY-MM-DD (2027-01-26) or DD/MM/YYYY (26/01/2027), within 1900–2100. Enter an actual date, not the format label.`);
  if(!name||name.length>200)errors.push(`Row ${n+2}: holiday name must contain 1 to 200 characters.`);
  if(day&&dates.has(day))errors.push(`Row ${n+2}: duplicate date ${day}.`);
  if(day)dates.add(day);return {day:day||sourceDate,name};
 });
 return {rows,errors};
}
