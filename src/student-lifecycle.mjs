export function admissionYear(value){
 const match=String(value||'').match(/^([12]\d{3})(?:-(\d{2}|[12]\d{3}))?$/);
 if(!match)return null;
 const year=Number(match[1]);
 if(match[2]&&Number(match[2])!==(match[2].length===2?(year+1)%100:year+1))return null;
 return year;
}
export function completionDate(patron,policies=[]){
 if(patron.category!=='student')return null;
 if(patron.course_end_date)return patron.course_end_date;
 const year=admissionYear(patron.profile?.admission_year);
 const policy=policies.find(p=>p.course===patron.profile?.course&&[2,3,4].includes(Number(p.duration_years)));
 if(!year||!policy)return null;
 const endYear=Number(year)+Number(policy.duration_years),month=Number(policy.completion_month)||6;
 const day=Math.min(Number(policy.completion_day)||30,new Date(Date.UTC(endYear,month,0)).getUTCDate());
 return String(endYear)+'-'+String(month).padStart(2,'0')+'-'+String(day).padStart(2,'0');
}
export function studentStatus(patron,policies,today){
 if(patron.category==='student'&&!patron.graduation_override&&(patron.status==='passed_out'||(completionDate(patron,policies)&&completionDate(patron,policies)<today)))return 'passed_out';
 return patron.active&&(!patron.expires||patron.expires>=today)?'active':'inactive';
}
