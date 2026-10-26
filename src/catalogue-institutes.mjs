export function instituteCopies(copies,institute=''){
 return institute?copies.filter(c=>institute==='UNASSIGNED'?!c.institute:c.institute===institute):copies;
}
export function catalogueTitles(titles,copies,search='',institute=''){
 const byTitle=new Map();
 for(const c of instituteCopies(copies,institute)){
  if(!byTitle.has(c.title_id))byTitle.set(c.title_id,[]);
  byTitle.get(c.title_id).push(c);
 }
 const term=search.trim().toLowerCase();
 return titles.filter(t=>(!institute||byTitle.has(t.id))&&
  [t.title,t.author,t.isbn,t.subject,t.classification,...(byTitle.get(t.id)||[]).flatMap(c=>[c.barcode,c.accession])]
   .join(' ').toLowerCase().includes(term));
}
export function catalogueExportRows(titles,copies,search='',institute=''){
 const matching=new Map(catalogueTitles(titles,copies,search,institute).map(t=>[t.id,t]));
 return instituteCopies(copies,institute).filter(c=>matching.has(c.title_id)).map(c=>({...matching.get(c.title_id),...c}));
}
