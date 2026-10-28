import {admissionYear as parseAdmissionYear} from './student-lifecycle.mjs';
export function normalizePatronRow(row) {
 const active=String(row.active??'').trim().toLowerCase(),expires=String(row.expires??'').trim();
 const errors=[];
 const status=String(row.status??'').trim().toLowerCase();
 if(status&&!['active','inactive','passed_out'].includes(status))errors.push('status must be active, inactive or passed_out');
 const admissionYear=String(row.admission_year??'').trim();
 if(admissionYear&&!parseAdmissionYear(admissionYear))errors.push('admission_year must be a four-digit year or academic year such as 2026-2027');
 if(row.course_end_date){const date=new Date(row.course_end_date+'T00:00:00Z');if(!/^\d{4}-\d{2}-\d{2}$/.test(row.course_end_date)||!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==row.course_end_date)errors.push('course_end_date must be a valid YYYY-MM-DD date');}
 if(active&&!['true','false'].includes(active))errors.push('active must be TRUE or FALSE (blank means TRUE)');
 if(expires){
  const date=new Date(expires+'T00:00:00Z');
  if(!/^\d{4}-\d{2}-\d{2}$/.test(expires)||!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==expires)errors.push('expires must be a valid YYYY-MM-DD date, for example 2029-12-31, or blank');
 }
 const normalized={...row,active:status?status==='active':active===''||active==='true',expires};
 for(const key of ['course','admission_year','course_end_date','status'])if(!String(normalized[key]??'').trim())delete normalized[key];
 return {row:normalized,errors};
}
