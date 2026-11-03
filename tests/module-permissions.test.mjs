import {test,before,after,beforeEach,afterEach} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {actors,authStub,seedDemo} from '../scripts/demo.mjs';
let db;
const as=id=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
const rpc=async(name,args=[])=>{const r=await db.query(`select public.${name}(${args.map((_,n)=>'$'+(n+1)).join(',')}) d`,args);return r.rows[0].d;};
const action=(name,p={},i='RBCET')=>rpc('library_action',[i,name,p]);
const save=(target,modules,revision=0,i='RBCET',reason='Approved module assignment')=>rpc('library_set_modules',[i,target,modules,revision,reason]);
async function denied(fn,pattern=/Access denied/){await db.exec('savepoint forbidden');await assert.rejects(fn,pattern);await db.exec('rollback to savepoint forbidden;release savepoint forbidden');}
before(async()=>{
 db=new PGlite();await db.exec(authStub);const files=(await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();
 await db.exec(await readFile('supabase/migrations/'+files[0],'utf8'));await db.exec(await readFile('supabase/seed.sql','utf8'));await seedDemo(db);
 for(const f of files.slice(1))await db.exec(await readFile('supabase/migrations/'+f,'utf8'));
 await db.exec("alter table auth.users add column email text;alter table auth.users add column raw_user_meta_data jsonb default '{}';");
 await db.query("update auth.users set email='operator@example.invalid',raw_user_meta_data=$1 where id=$2",[{full_name:'Module Test Operator'},actors.assistant]);
});
after(async()=>db.close());beforeEach(async()=>{await db.exec('begin');await as(actors.admin);});afterEach(async()=>db.exec('rollback'));

test('defaults retain existing roles; search and paginated user lists disclose no credentials',async()=>{
 const defaults=await rpc('library_my_modules',['RBCET']);assert.ok(defaults.modules.includes('Permissions'));
 const found=await rpc('library_permissions',['RBCET','module test',null,50]);assert.equal(found.total,1);assert.equal(found.rows[0].email,'operator@example.invalid');assert.equal(found.rows[0].name,'Module Test Operator');
 assert.equal(found.rows[0].revision,0);assert.equal(found.rows[0].custom,false);assert.ok(!JSON.stringify(found).includes('raw_user_meta_data'));
 const first=await rpc('library_permissions',['RBCET','',null,2]),next=await rpc('library_permissions',['RBCET','',first.next_id,2]);assert.equal(new Set([...first.rows,...next.rows].map(u=>u.id)).size,4);
 await as(actors.accountant);assert.deepEqual((await rpc('library_my_modules',['RBCET'])).modules,['Fines']);
});
test('only admin assigns permissions; administrator cannot be locked out or roles elevated',async()=>{
 await as(actors.librarian);await denied(()=>save(actors.assistant,[]));await denied(()=>rpc('library_permissions',['RBCET']));
 await as(actors.admin);await denied(()=>save(actors.admin,[]),/Administrator permissions cannot be revoked/);
 await denied(()=>save(actors.accountant,['Catalogue']),/unavailable for this role/);
 await denied(()=>save(actors.patron,['Settings']),/Student accounts are excluded/);
 await denied(()=>save(actors.assistant,['Permissions']),/unavailable for this role/);
 await denied(()=>save(actors.assistant,['Not a module']),/invalid/);
 await denied(()=>save(actors.assistant,[],0,'RBCET',' '),/reason/);
 await denied(()=>save('99999999-9999-9999-9999-999999999999',[]),/not assigned/);
 assert.equal((await db.query("select has_table_privilege('authenticated','app.user_modules','UPDATE') allowed")).rows[0].allowed,false);
 assert.equal((await db.query("select has_function_privilege('anon','public.library_set_modules(text,uuid,text[],bigint,text)','EXECUTE') allowed")).rows[0].allowed,false);
});
test('revoked circulation blocks direct API calls and restores through explicit assignment',async()=>{
 await save(actors.assistant,['Catalogue']);await as(actors.assistant);
 await denied(()=>action('issue',{}));await denied(()=>action('return',{}));await denied(()=>rpc('library_circulation_page',['RBCET']));
 assert.ok((await rpc('library_collection_page',['RBCET','titles'])).rows.length);
 await as(actors.admin);await save(actors.assistant,['Circulation'],1);await as(actors.assistant);
 assert.ok((await rpc('library_circulation_page',['RBCET'])).rows.length);
 // An assigned page does not grant librarian-level catalogue mutations to an assistant.
 await as(actors.admin);await save(actors.assistant,['Catalogue'],2);await as(actors.assistant);await denied(()=>action('title',{title:'Forbidden role elevation',author:'QA'}));
});
test('revoke all removes bootstrap data and blocks alternate exports, fines and edit endpoints',async()=>{
 await save(actors.librarian,[]);await as(actors.librarian);
 const w=await rpc('library_workspace',['RBCET']);assert.deepEqual(w.module_permissions.modules,[]);assert.deepEqual(w.readable_datasets,[]);
 for(const k of ['patrons','loans','holds','fines','payments','audit','memberships','acquisitions','holidays'])assert.deepEqual(w[k],[],k);
 assert.equal(w.counts.fine_balance,undefined);assert.equal(w.counts.copies,undefined);
 assert.deepEqual((await rpc('library_snapshot',['RBCET'])).titles,[]);
 await denied(()=>rpc('library_records_page',['RBCET','audit']));await denied(()=>rpc('library_collection_page',['RBCET','copies']));
 await denied(()=>rpc('library_register_page',['RBCET','collections']));await denied(()=>rpc('library_book_edits',['RBCET']));
 await denied(()=>rpc('library_book_edit_action',['RBCET','book_edit_request',{}]));await denied(()=>action('holiday',{day:'2042-01-01',name:'Forbidden'}));
 await denied(()=>action('collect_loan_fine',{}));assert.deepEqual(await rpc('library_notifications',['RBCET']),[]);
});
test('revocations apply immediately to an existing identity and remain library scoped',async()=>{
 await save(actors.accountant,[]);await as(actors.accountant);await denied(()=>rpc('library_fine_month',['RBCET','2026-10-01']));
 assert.ok((await rpc('library_my_modules',['RBCP'])).modules.includes('Fines'));
 await denied(()=>rpc('library_fine_months',['RBCP','2026-10-01','2026-10-01',true]),/permission is required/);
 await as(actors.admin);await denied(()=>save(actors.librarian,[],0,'RBCN'),/not assigned/);
});
test('changes require fresh revision, keep before/after/reason history, and restore role defaults',async()=>{
 const first=await save(actors.assistant,[]);assert.equal(first.revision,1);
 await denied(()=>save(actors.assistant,['Circulation'],0),/changed since this form/);
 const reset=await save(actors.assistant,null,1);assert.ok(reset.modules.includes('Circulation'));assert.equal(reset.revision,2);
 const log=(await db.query("select details from app.audit where action='module_permissions' and details->>'user_id'=$1 order by id",[actors.assistant])).rows;
 assert.equal(log.length,2);assert.deepEqual(log[0].details.after,[]);assert.ok(log[0].details.before.includes('Circulation'));
 assert.equal(log[1].details.restored_defaults,true);assert.equal(log[1].details.reason,'Approved module assignment');
 await as(actors.assistant);assert.equal((await rpc('library_my_modules',['RBCET'])).revision,2);
});
test('fine and catalogue revocation does not break permitted circulation dependency reads',async()=>{
 await save(actors.librarian,['Circulation']);await as(actors.librarian);
 assert.ok((await rpc('library_collection_page',['RBCET','copies'])).rows.length);
 const p=await rpc('library_circulation_page',['RBCET']);assert.ok(p.rows.length);assert.ok(await rpc('library_fine_quote',['RBCET',p.rows[0].id]));
 await denied(()=>action('collect_loan_fine',{}));await denied(()=>action('book',{title:'Denied',accession:'NO'}));
 await denied(()=>rpc('library_records_page',['RBCET','audit']));await denied(()=>action('book_edit_request',{}));
});

test('student accounts are excluded from listing and direct edits; faculty and Accounts remain assignable',async()=>{
 const listed=await rpc('library_permissions',['RBCET','',null,100]);assert.ok(!listed.rows.some(u=>u.id===actors.patron));
 assert.ok(listed.rows.some(u=>u.id===actors.librarian));assert.ok(listed.rows.some(u=>u.id===actors.accountant));
 await denied(()=>save(actors.patron,[]),/Student accounts are excluded/);
 await db.query("update app.patrons set category='faculty' where id=(select patron_id from app.memberships where institution_id='RBCET' and user_id=$1)",[actors.patron]);
 const faculty=await rpc('library_permissions',['RBCET','',null,100]);assert.ok(faculty.rows.some(u=>u.id===actors.patron));
 assert.deepEqual((await save(actors.patron,['Catalogue'])).modules,['Catalogue']);
});
