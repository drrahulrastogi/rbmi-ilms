const staffRoles=new Set(['admin','librarian','assistant','accountant','auditor']);

export function selectWorkspaceInstitution(memberships,currentInstitution){
 const current=memberships.find(m=>m.institution_id===currentInstitution);
 const staff=memberships.find(m=>staffRoles.has(String(m.role||'').trim().toLowerCase()));
 return (current||staff||memberships[0])?.institution_id||'';
}

export function createWorkspaceRequestGuard(readActive){
 let version=0;
 return {
  invalidate(){version++;},
  begin(context){
   const matches=()=>{const active=readActive();return ['institution','owner','token'].every(key=>context[key]===active[key]);};
   if(!matches())return ()=>false;
   const request=++version;
   return ()=>request===version&&matches();
  }
 };
}
