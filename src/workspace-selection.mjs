const staffRoles=new Set(['admin','librarian','assistant','accountant','auditor']);

export function selectWorkspaceInstitution(memberships,currentInstitution){
 const current=memberships.find(m=>m.institution_id===currentInstitution);
 const staff=memberships.find(m=>staffRoles.has(String(m.role||'').trim().toLowerCase()));
 return (current||staff||memberships[0])?.institution_id||'';
}
