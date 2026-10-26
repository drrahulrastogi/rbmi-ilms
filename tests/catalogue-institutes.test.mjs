import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {fixture,actors} from './helpers/fixture.mjs';
import {catalogueTitles,instituteCopies,catalogueExportRows} from '../src/catalogue-institutes.mjs';
let db,title,copies={};
const q='QA institute shared title';
before(async()=>{
 db=await fixture({beforeMigration:async(db,file)=>{
  if(!file.includes('rbtti_shared_library_catalogue_institutes'))return;
  title=(await db.query("insert into app.titles(institution_id,title,author) values('RBCET',$1,'Test author') returning id",[q])).rows[0].id;
  const batch=(await db.query("insert into app.import_batches(institution_id,source_name,source_hash) values('RBCET','Synthetic institute test','qa-institutes') returning id")).rows[0].id;
  for(const [n,sheet,status] of [[1,'B.Ed','available'],[2,'B.Ed (Book Bank)','loaned'],[3,'B.COM','available'],[4,'C','loaned'],[5,'AM','available']]){
   const row=(await db.query("insert into app.copies(institution_id,title_id,accession,barcode,status) values('RBCET',$1,$2,$2,$3) returning id",[title,'QA-INST-'+n,status])).rows[0];
   copies[n]=row.id;
   await db.query("insert into app.import_records(batch_id,kind,source_sheet,source_row,entity_id,source_data) values($1,'book',$2,$3,$4,'{}')",[batch,sheet,n,row.id]);
  }
 }});
});
after(async()=>{await db?.close();});
const action=(name,p)=>db.query("select public.library_action('RBCET',$1,$2) d",[name,p]);
const page=async(institute='',search=q,after=null,size=40)=>(await db.query("select public.library_institute_titles_page('RBCET',$1,$2,$3,$4) d",[institute,search,after,size])).rows[0].d;
async function as(role){await db.query("select set_config('request.jwt.claim.sub',$1,false)",[actors[role]]);}

test('approved workbook mapping is stored on copies without splitting physical library',async()=>{
 const rows=(await db.query('select id,institution_id,institute from app.copies where title_id=$1 order by barcode',[title])).rows;
 assert.deepEqual(rows.map(c=>c.institute),['RBTTI','RBTTI','RBMI','RBCET','RBCET']);
 assert.ok(rows.every(c=>c.institution_id==='RBCET'));
 const libraries=(await db.query("select id,campuses,active from app.institutions where id in ('RBCET','RBTTI') order by id")).rows;
 assert.deepEqual(libraries[0].campuses,['RBCET','RBMI','RBTTI']);assert.equal(libraries[1].active,false);
 assert.equal((await db.query("select user_id from app.library_staff where institution_id='RBCET'")).rows[0].user_id,actors.librarian);
});
test('anonymous institute search scopes availability and previews per physical copy',async()=>{
 await db.exec('set role anon');
 try{for(const [institute,total,available] of [['RBTTI',2,1],['RBMI',1,1],['RBCET',2,1],['',5,3]]){
  const p=await page(institute);assert.equal(p.titles.length,1);
  assert.equal(p.copy_counts[0].total,total);assert.equal(p.copy_counts[0].available,available);
  assert.ok(p.copies.every(c=>!institute||c.institute===institute));
  assert.ok(p.copies.every(c=>!('price' in c)&&!('patron_id' in c)));
  assert.ok(p.libraries.find(l=>l.id==='RBCET').campuses.includes('RBTTI'));
 }}finally{await db.exec('reset role');}
});
test('barcode search cannot match a copy from another selected institute',async()=>{
 assert.equal((await page('RBTTI','QA-INST-3')).titles.length,0);
 assert.equal((await page('RBMI','qa-inst-3')).titles.length,1);
 for(const institute of ['RBCP',"RBTTI');drop table app.copies;--"])
  await assert.rejects(page(institute),/Institute must belong/);
 await assert.rejects(page('RBMI','a'.repeat(201)),/200 search/);
 await assert.rejects(page('RBMI',q,null,101),/1 to 100/);
});
test('public copy pagination and title pagination retain institute scope without duplicates',async()=>{
 await db.exec('set role anon');
 try{
  let cursor=null,ids=[];do{
   const p=(await db.query("select public.library_institute_copies_page('RBCET',$1,'RBTTI',$2,1) d",[title,cursor])).rows[0].d;
   assert.ok(p.rows.every(c=>c.institute==='RBTTI'&&!('price' in c)));ids.push(...p.rows.map(c=>c.id));cursor=p.next_id;
  }while(cursor);
  assert.equal(ids.length,2);assert.equal(new Set(ids).size,2);
  let after=null,titles=[];do{const p=await page('RBCET','',after,3);titles.push(...p.titles.map(t=>t.id));after=p.next_id;}while(after);
  assert.equal(titles.length,new Set(titles).size);assert.ok(titles.includes(title));
 }finally{await db.exec('reset role');}
});
test('students cannot reassign copy ownership or create copies',async()=>{
 await as('patron');await db.exec('set role authenticated');
 try{
  await assert.rejects(action('copy_institute',{id:copies[1],institute:'RBMI'}),/Access denied/);
  await assert.rejects(action('copy',{title_id:title,accession:'QA-BAD',barcode:'QA-BAD',institute:'RBMI'}),/Access denied/);
  await assert.rejects(db.query("update app.copies set institute='RBMI' where id=$1",[copies[1]]),/permission denied/);
 }finally{await db.exec('reset role');await as('admin');}
});
test('librarian may reassign copies in shared library with an audit, never a foreign library',async()=>{
 await as('librarian');await db.exec('set role authenticated');
 try{
  await action('copy_institute',{id:copies[1],institute:' rbmi '});
  const foreign=(await db.query("select public.library_collection_page('RBCET','copies',null,5000) d")).rows[0].d.rows.find(c=>c.id===copies[1]);
  assert.equal(foreign.institute,'RBMI');
  await assert.rejects(action('copy_institute',{id:copies[1],institute:'RBCP'}),/Institute must belong/);
 }finally{await db.exec('reset role');await as('admin');}
 const audit=(await db.query("select details from app.audit where action='copy_institute' order by id desc limit 1")).rows[0].details;
 assert.equal(audit.before,'RBTTI');assert.equal(audit.institute,'RBMI');
 const foreign=(await db.query("select id from app.copies where institution_id='RBCP' limit 1")).rows[0].id;
 await assert.rejects(action('copy_institute',{id:foreign,institute:'RBCET'}),/Copy not found/);
 await action('copy_institute',{id:copies[1],institute:'RBTTI'});
});
test('single copy and bulk book creation preserve ownership and bad batches roll back',async()=>{
 await as('admin');
 await action('copy',{title_id:title,accession:'QA-NEW',barcode:'QA-NEW',institute:'RBTTI'});
 await action('import',{kind:'books',rows:[{title:'QA new management',author:'QA author',accession:'QA-BULK',barcode:'QA-BULK',institute:'RBMI'}]});
 const rows=(await db.query("select barcode,institute from app.copies where barcode in ('QA-NEW','QA-BULK') order by barcode")).rows;
 assert.deepEqual(rows.map(c=>c.institute),['RBMI','RBTTI']);
 await assert.rejects(action('import',{kind:'books',rows:[{title:'QA rollback',author:'QA author',accession:'QA-ROLL',barcode:'QA-ROLL',institute:'RBMI'},{institute:'RBCP'}]}),/Institute must belong/);
 assert.equal((await db.query("select count(*) n from app.copies where barcode='QA-ROLL'")).rows[0].n,0);
 await assert.rejects(db.query("update app.copies set institute='RBCP' where id=$1",[copies[1]]),/Institute must belong/);
});
test('unassigned copies remain discoverable and never appear as a named institute',async()=>{
 await action('copy',{title_id:title,accession:'QA-UNKNOWN',barcode:'QA-UNKNOWN'});
 const p=await page('UNASSIGNED');assert.equal(p.copy_counts[0].total,1);assert.equal(p.copies[0].institute,null);
 assert.equal((await page('RBMI','QA-UNKNOWN')).titles.length,0);
});
test('client filtering, copy counts and export share institute ownership and text search',()=>{
 const titles=[{id:'a',title:'हिन्दी शिक्षण',author:'आर. लाल'},{id:'b',title:'Engineering',author:'Writer'}];
 const copies=[{id:'1',title_id:'a',institute:'RBTTI',barcode:'BED-1',status:'available'},{id:'2',title_id:'a',institute:'RBMI',barcode:'COM-1',status:'loaned'},{id:'3',title_id:'b',institute:'RBCET',barcode:'ENG-1',status:'available'},{id:'4',title_id:'a',institute:null,barcode:'UNCLASSIFIED'}];
 assert.deepEqual(catalogueTitles(titles,copies,'हिन्दी','RBTTI').map(t=>t.id),['a']);
 assert.equal(catalogueTitles(titles,copies,'COM-1','RBTTI').length,0);
 assert.deepEqual(instituteCopies(copies,'RBMI').map(c=>c.id),['2']);
 assert.deepEqual(catalogueExportRows(titles,copies,'लाल','RBTTI').map(c=>c.barcode),['BED-1']);
 assert.deepEqual(instituteCopies(copies,'UNASSIGNED').map(c=>c.id),['4']);
 assert.equal(catalogueTitles(titles,copies).length,2);
});
