import React,{useEffect,useId,useMemo,useRef,useState} from 'react';
import {rpc,today} from './api';
import {availableBookSuggestions} from './issue-search.mjs';

function Suggestions({label,value,onChange,items,onSelect,render,busy,error,disabled,inputRef}){
 const id=useId(),[open,setOpen]=useState(false),[active,setActive]=useState(-1);
 useEffect(()=>{setActive(-1);},[value,items]);
 const visible=open&&value.trim().length>=2;
 return <div className="issue-combobox"><label htmlFor={id}>{label}</label><input id={id} ref={inputRef} role="combobox" aria-autocomplete="list" aria-expanded={visible} aria-controls={id+'-list'} aria-activedescendant={visible&&active>=0?id+'-'+active:undefined} autoComplete="off" value={value} disabled={disabled} maxLength={200} placeholder="Type at least 2 letters…" onChange={e=>{onChange(e.target.value);setOpen(true);}} onFocus={()=>setOpen(true)} onBlur={()=>setOpen(false)} onKeyDown={e=>{
  if(e.key==='Escape'){setOpen(false);return;}
  if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();setOpen(true);setActive(n=>items.length?(n<0?(e.key==='ArrowDown'?0:items.length-1):(n+(e.key==='ArrowDown'?1:-1)+items.length)%items.length):-1);}
  if(e.key==='Enter'){e.preventDefault();if(visible&&active>=0&&items[active]){onSelect(items[active]);setOpen(false);}}
 }}/>{visible&&<div className="issue-suggestions"><div id={id+'-list'} role="listbox" aria-label={label+' suggestions'}>{!busy&&items.map((item,n)=><button key={item.id} id={id+'-'+n} type="button" role="option" aria-selected={active===n} disabled={disabled} tabIndex={-1} className={active===n?'active':''} onMouseDown={e=>e.preventDefault()} onMouseEnter={()=>setActive(n)} onClick={()=>{onSelect(item);setOpen(false);}}>{render(item)}</button>)}</div><p role="status">{busy?'Searching…':error||(!items.length?'No matching records.':`Showing ${items.length} matches. Refine your search if needed.`)}</p></div>}</div>;
}

export function IssueForm({institution,libraryName,titles,copies,onSubmit,busy}){
 const [bookQuery,setBookQuery]=useState(''),[patronQuery,setPatronQuery]=useState(''),[barcode,setBarcode]=useState(''),[patronCode,setPatronCode]=useState(''),[patrons,setPatrons]=useState([]),[searching,setSearching]=useState(false),[error,setError]=useState('');
 const patronRef=useRef(null);
 const books=useMemo(()=>availableBookSuggestions(titles,copies,bookQuery,institution),[titles,copies,bookQuery,institution]);
 useEffect(()=>{
  let current=true;setPatrons([]);setError('');const q=patronQuery.trim();
  if(q.length<2){setSearching(false);return;}
  setSearching(true);
  const timer=setTimeout(()=>{rpc('library_records_page',{i:institution,kind:'patrons',after_id:null,page_size:20,q}).then(result=>{if(current)setPatrons(result.rows);}).catch(()=>{if(current)setError('Could not search patrons. Retry or enter the patron code below.');}).finally(()=>{if(current)setSearching(false);});},250);
  return()=>{current=false;clearTimeout(timer);};
 },[institution,patronQuery]);
 return <form className="editor-form issue-form" onSubmit={e=>{e.preventDefault();if(!busy)onSubmit({library_code:institution,barcode:barcode.trim(),patron_code:patronCode.trim()});}}>
  <label><span>Issuing library</span><input readOnly value={institution+' — '+(libraryName||institution)}/></label>
  <Suggestions label="Find book by name / author / barcode" value={bookQuery} onChange={value=>{setBookQuery(value);setBarcode('');}} items={books} disabled={busy} onSelect={book=>{setBookQuery(book.title);setBarcode(book.barcode||book.accession);patronRef.current?.focus();}} render={book=><><strong>{book.title}</strong><small>{book.author} · Barcode {book.barcode} · Accession {book.accession}{book.shelf?' · Shelf '+book.shelf:''}</small></>}/>
  <label><span>Scan barcode / accession *</span><input name="barcode" required autoFocus autoComplete="off" disabled={busy} value={barcode} onChange={e=>{setBarcode(e.target.value);setBookQuery('');}}/><small>Choose an available physical copy above, or scan/type its identifier.</small></label>
  <Suggestions label="Find patron by student / faculty name or code" inputRef={patronRef} value={patronQuery} onChange={value=>{setPatronQuery(value);setPatronCode('');}} items={patrons} busy={searching} error={error} disabled={busy} onSelect={person=>{setPatronQuery(person.name);setPatronCode(person.code);}} render={person=><><strong>{person.name} · {person.code}</strong><small>{person.category} · {person.profile?.institute||person.institution_id} · {person.department||'No department'}{!person.active?' · Inactive':person.expires&&person.expires<today()?' · Expired':''}</small></>}/>
  <label><span>Patron code *</span><input name="patron_code" required autoComplete="off" disabled={busy} value={patronCode} onChange={e=>{setPatronCode(e.target.value);setPatronQuery('');}}/><small>Select a person above to fill their exact code, or enter it directly.</small></label>
  <p className="muted">Selections do not issue a book until you press Issue book. Availability and all circulation rules are checked again when saving.</p>
  <button className="button primary" type="submit" disabled={busy||!barcode.trim()||!patronCode.trim()}>{busy?'Issuing…':'Issue book'}</button>
 </form>;
}
