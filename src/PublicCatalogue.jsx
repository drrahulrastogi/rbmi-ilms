import React,{useEffect,useRef,useState} from 'react';
import {rpc,assetURL} from './api';
import {InstituteFilter} from './InstituteFilter';
export function PublicCatalogue({onClose}){
 const [library,setLibrary]=useState('RBCET'),[institute,setInstitute]=useState('');
 const [data,setData]=useState({libraries:[],titles:[],copies:[],copy_counts:[]});
 const [term,setTerm]=useState(''),[cursor,setCursor]=useState(null),[previous,setPrevious]=useState([]);
 const [error,setError]=useState(''),[cart,setCart]=useState([]),[loading,setLoading]=useState(true);
 const [detail,setDetail]=useState(null),[copiesBusy,setCopiesBusy]=useState(false),copyRequest=useRef(0);
 const campuses=data.libraries.find(l=>l.id===library)?.campuses||[];
 function reset(clearCart=true){copyRequest.current++;setDetail(null);setCopiesBusy(false);if(clearCart)setCart([]);setCursor(null);setPrevious([]);setLoading(true);}
 useEffect(()=>{
  let active=true;setError('');setLoading(true);
  const timer=setTimeout(()=>{
   rpc('library_institute_titles_page',{library_code:library,institute,q:term,after_id:cursor,page_size:40})
    .then(d=>{if(active)setData(d);}).catch(e=>{if(active)setError(e.message);})
    .finally(()=>{if(active)setLoading(false);});
  },250);
  return()=>{active=false;clearTimeout(timer);};
 },[library,institute,term,cursor]);
 useEffect(()=>()=>{copyRequest.current++;},[]);
 async function copies(t,after_id=null){
  const request=++copyRequest.current;setCopiesBusy(true);setError('');
  try{
   const page=await rpc('library_institute_copies_page',{library_code:library,title:t.id,institute,after_id,page_size:50});
   if(request===copyRequest.current)setDetail({title:t,...page});
  }catch(e){if(request===copyRequest.current)setError(e.message);}
  finally{if(request===copyRequest.current)setCopiesBusy(false);}
 }
 return <div className="public-catalogue">
  <header><img src={assetURL('rbmi-logo.png')} alt="RBMI"/><div><h1>Library public catalogue</h1><p>Discover books across the RBMI library network.</p></div><button className="button" onClick={onClose}>Staff / reader sign in</button></header>
  <section className="panel">
   <div className="search-filters">
    <label>Library<select value={library} onChange={e=>{reset();setLibrary(e.target.value);setInstitute('');}}>{data.libraries.map(l=><option key={l.id} value={l.id}>{l.name}</option>)}</select></label>
    <InstituteFilter campuses={campuses} value={institute} onChange={value=>{reset();setInstitute(value);}}/>
    <label>Search title, author, ISBN, subject or accession<input maxLength={200} value={term} onChange={e=>{reset(false);setTerm(e.target.value);}}/></label>
   </div>
   <p className="muted">Availability and copy lists follow the selected institute. RBCET, RBMI and RBTTI share one issuing library.</p>
   {error&&<p role="alert" className="alert error">{error}</p>}
   {loading&&<p role="status">Loading catalogue…</p>}
   {!loading&&!error&&data.titles.map(t=>{
    const count=data.copy_counts.find(c=>c.title_id===t.id)||{total:0,available:0};
    return <article key={t.id} className="copy-card"><div><h2>{t.title}</h2><p>{t.author} · ISBN {t.isbn||'—'} · {t.publisher} {t.year}</p>
     <p>{count.available} of {count.total} copies available · Call number {t.classification||'—'}</p>
     <p>{data.copies.filter(c=>c.title_id===t.id).map(c=>`${c.accession} / ${c.institute||'Institute not assigned'} / ${c.shelf} / ${c.status}`).join('; ')}</p>
     <button className="text-button" disabled={copiesBusy} onClick={()=>copies(t)}>Browse physical copies</button></div>
     <button className="button" onClick={()=>setCart(cart.some(x=>x.id===t.id)?cart.filter(x=>x.id!==t.id):[...cart,t])}>{cart.some(x=>x.id===t.id)?'Remove from cart':'Add to cart'}</button></article>;
   })}
   <div className="table-footer"><button className="button" disabled={loading||!previous.length} onClick={()=>{setLoading(true);setCursor(previous.at(-1));setPrevious(p=>p.slice(0,-1));}}>Previous titles</button><span>Page {previous.length+1}</span><button className="button" disabled={loading||!data.next_id} onClick={()=>{setLoading(true);setPrevious(p=>[...p,cursor]);setCursor(data.next_id);}}>Next titles</button></div>
   {!loading&&!error&&!data.titles.length&&<p className="drawer-description">No matching catalogue records for this institute.</p>}
  </section>
  {detail&&<section className="panel spaced"><div className="panel-heading"><h2>Copies: {detail.title.title}</h2><button className="button" onClick={()=>{copyRequest.current++;setCopiesBusy(false);setDetail(null);}}>Close copies</button></div>
   <div className="table-scroll"><table><thead><tr><th>Accession</th><th>Institute</th><th>Shelf</th><th>Status</th></tr></thead><tbody>{detail.rows.map(c=><tr key={c.id}><td>{c.accession}</td><td>{c.institute||'Institute not assigned'}</td><td>{c.shelf}</td><td>{c.status}</td></tr>)}</tbody></table></div>
   <div className="section-actions"><button className="button" disabled={copiesBusy} onClick={()=>copies(detail.title)}>First copies</button><button className="button" disabled={copiesBusy||!detail.next_id} onClick={()=>copies(detail.title,detail.next_id)}>Next copies</button></div>
  </section>}
  <section className="panel spaced"><div className="panel-heading"><div><h2>Your temporary cart ({cart.length})</h2><p>{cart.map(t=>t.title).join('; ')||'Select titles to build a temporary reading selection.'}</p></div><button className="button" onClick={()=>window.print()}>Print selection / catalogue</button></div></section>
 </div>;
}
