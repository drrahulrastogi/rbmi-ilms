import React from 'react';
export function InstituteFilter({value,onChange,campuses,id='catalogue-institute'}){
 return <label htmlFor={id}>Institute<select id={id} value={value} onChange={e=>onChange(e.target.value)}>
  <option value="">All institutes</option>
  {campuses.map(code=><option value={code} key={code}>{code}</option>)}
  <option value="UNASSIGNED">Institute not assigned</option>
 </select></label>;
}
