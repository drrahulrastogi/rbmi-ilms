import {test} from 'node:test';import assert from 'node:assert/strict';
import {availableBookSuggestions} from '../src/issue-search.mjs';
const titles=[{id:'a',institution_id:'RBCET',title:'हिन्दी शिक्षण',author:'लाल',isbn:'123'},{id:'b',institution_id:'RBCP',title:'हिन्दी शिक्षण',author:'Other'}];
const copies=['available','loaned','lost','damaged','missing','withdrawn'].map((status,n)=>({id:'copy'+n,title_id:'a',institution_id:'RBCET',status,barcode:'BOOK-'+n,accession:'A-'+n}));
test('issue suggestions exclude every unavailable status and other libraries',()=>{
 const rows=availableBookSuggestions(titles,[...copies,{...copies[0],id:'foreign',title_id:'b',institution_id:'RBCP'}],'हिन्दी','RBCET');
 assert.deepEqual(rows.map(r=>r.id),['copy0']);assert.equal(rows[0].barcode,'BOOK-0');assert.equal(rows[0].accession,'A-0');
});
test('title, author, barcode and accession searches choose exact physical copy',()=>{
 const extra={...copies[0],id:'second',barcode:'EXACT-22',accession:'ACC-22'};
 assert.equal(availableBookSuggestions(titles,[...copies,extra],'exact-22','RBCET')[0].id,'second');
 assert.equal(availableBookSuggestions(titles,[...copies,extra],'acc-22','RBCET')[0].barcode,'EXACT-22');
 assert.equal(availableBookSuggestions(titles,copies,'  लाल  ','RBCET').length,1);
});
test('suggestions stay bounded and do not offer every copy for an empty query',()=>{
 const many=Array.from({length:10000},(_,n)=>({...copies[0],id:'many'+n}));
 assert.equal(availableBookSuggestions(titles,many,'हिन्दी','RBCET').length,20);
 assert.deepEqual(availableBookSuggestions(titles,many,'','RBCET'),[]);
 assert.deepEqual(availableBookSuggestions(titles,many,'ह','RBCET'),[]);
 assert.deepEqual(availableBookSuggestions(titles,[{...copies[0],title_id:'unknown'}],'BOOK','RBCET'),[]);
});
