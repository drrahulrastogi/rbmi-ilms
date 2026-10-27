const text=value=>String(value??'').trim().toLocaleLowerCase();
export function availableBookSuggestions(titles,copies,query,institution,limit=20){
 const q=text(query);if(!q)return [];
 const byId=new Map(titles.filter(t=>t.institution_id===institution).map(t=>[t.id,t]));
 const results=[];
 for(const copy of copies){
  const title=byId.get(copy.title_id);
  if(copy.institution_id!==institution||copy.status!=='available'||!title)continue;
  if(q.length===1?![copy.barcode,copy.accession].some(value=>text(value)===q):![title.title,title.author,title.isbn,copy.barcode,copy.accession].some(value=>text(value).includes(q)))continue;
  results.push({id:copy.id,title:title.title,author:title.author,barcode:copy.barcode,accession:copy.accession,shelf:copy.shelf});
  if(results.length>=limit)break;
 }
 return results;
}
