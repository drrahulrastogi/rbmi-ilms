import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {authStub,seedDemo,actors} from '../scripts/demo.mjs';
let db,borrower,loans=[],copies=[];
const user='00000000-0000-0000-0000-000000000077';
const as=id=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
const action=async(name,p,i='RBCET')=>(await db.query('select public.library_action($1,$2,$3) d',[i,name,p])).rows[0].d;
const alerts=async i=>(await db.query('select public.library_notifications($1) d',[i])).rows[0].d;
const page=async({i='RBCET',after_id=null,page_size=50,q='',from_day=null,to_day=null,date_field='issued',loan_status='all'}={})=>(await db.query('select public.library_circulation_page($1,$2,$3,$4,$5,$6,$7,$8) d',[i,after_id,page_size,q,from_day,to_day,date_field,loan_status])).rows[0].d;
before(async()=>{
 db=new PGlite();await db.exec(authStub);
 const files=(await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();
 await db.exec(await readFile('supabase/migrations/'+files[0],'utf8'));await db.exec(await readFile('supabase/seed.sql','utf8'));await seedDemo(db);
 for(const f of files.slice(1))await db.exec(await readFile('supabase/migrations/'+f,'utf8'));
 await db.query('insert into auth.users(id) values($1)',[user]);await as(actors.admin);
 await action('patron',{code:'QA-ALERT-USER',name:'Faculty Reminder Recipient',category:'faculty',email:'reminder@example.invalid',active:true});
 borrower=(await db.query("select * from app.patrons where institution_id='RBCET' and code='QA-ALERT-USER'")).rows[0];
 await db.query("insert into app.memberships(user_id,institution_id,role,patron_id) values($1,'RBCET','patron',$2)",[user,borrower.id]);
 copies=(await db.query("select c.* from app.copies c where c.institution_id='RBCET' and c.status='available' and not exists(select 1 from app.holds h where h.title_id=c.title_id and h.status='waiting') order by c.id limit 5")).rows;
 for(const c of copies.slice(0,3))loans.push(await action('issue',{library_code:'RBCET',barcode:c.barcode.toLowerCase(),patron_code:borrower.code}));
 await db.query('update app.loans set due=app.today()+2 where id=any($1::uuid[])',[loans.map(l=>l.id)]);
});
after(async()=>db.close());

test('borrower notifications include only their library closure, due-soon books and unpaid fines',async()=>{
 await as(actors.admin);await action('availability',{day:(await db.query('select app.today()::text d')).rows[0].d,available:false,reason:'Staff member on leave'});
 await db.query("insert into app.fines(institution_id,patron_id,loan_id,amount) values('RBCET',$1,$2,25)",[borrower.id,loans[0].id]);
 await as(user);const notices=await alerts('RBCET');
 assert.equal(notices.filter(a=>a.type==='unavailable').length,1);
 assert.equal(notices.filter(a=>a.type==='due_soon').length,3);
 assert.equal(notices.filter(a=>a.type==='fine_due').length,1);
 assert.equal(Number(notices.find(a=>a.type==='fine_due').amount),25);
 assert.ok(notices.filter(a=>a.type==='due_soon').every(a=>loans.some(l=>a.id.includes(l.id))));
 await assert.rejects(alerts('RBCP'),/Access denied/);
 await as(actors.admin);assert.deepEqual(await alerts('RBCET'),[]);
});

test('paid fines, returned books and available-again status clear the corresponding notifications',async()=>{
 await as(actors.admin);await db.query('update app.fines set paid=amount where loan_id=$1',[loans[0].id]);
 await db.query('update app.loans set returned=app.today() where id=$1',[loans[0].id]);
 await action('availability',{day:(await db.query('select app.today()::text d')).rows[0].d,available:true,reason:'Available again'});
 await as(user);const notices=await alerts('RBCET');assert.equal(notices.length,2);assert.ok(notices.every(a=>a.type==='due_soon'));
 await db.query('update app.patrons set active=false where id=$1',[borrower.id]);assert.deepEqual(await alerts('RBCET'),[]);await db.query('update app.patrons set active=true where id=$1',[borrower.id]);
});

test('circulation filters use the requested date, preserve pagination and enforce borrower ownership',async()=>{
 await as(actors.admin);const due=(await db.query('select (app.today()+2)::text d')).rows[0].d;
 const first=await page({q:'faculty reminder',page_size:2,date_field:'due',from_day:due,to_day:due});assert.equal(first.total,3);assert.equal(first.rows.length,2);assert.ok(first.next_id);
 const next=await page({q:'FACULTY REMINDER',page_size:2,date_field:'due',from_day:due,to_day:due,after_id:first.next_id});assert.equal(next.rows.length,1);assert.equal(new Set([...first.rows,...next.rows].map(r=>r.id)).size,3);
 assert.ok(first.rows.every(r=>r._patron_name===borrower.name&&r._accession));
 assert.equal((await page({q:borrower.name,loan_status:'returned'})).total,1);
 assert.equal((await page({q:borrower.name,loan_status:'active'})).total,2);
 assert.equal((await page({q:borrower.name,date_field:'due',from_day:'2040-01-01',to_day:'2040-01-01'})).total,0);
 await assert.rejects(page({date_field:'not_a_field'}),/Invalid circulation/);
 await as(user);assert.ok((await page()).rows.every(r=>r.patron_id===borrower.id));await assert.rejects(page({i:'RBCP'}),/Access denied/);
});

test('case-insensitive accession resolves the right copy and ambiguous identifiers require an explicit selection',async()=>{
 await as(actors.admin);const a=copies[3],b=copies[4];
 await db.query('update app.copies set barcode=$1,accession=$2 where id=$3',['QA-COPY-A','Case-Access-A',a.id]);
 const loan=await action('issue',{library_code:'RBCET',barcode:'case-access-a',patron_code:borrower.code});assert.equal(loan.copy_id,a.id);
 await action('return',{library_code:'RBCET',id:loan.id});
 await db.query('update app.copies set barcode=$1 where id=$2',['qa-copy-a',b.id]);
 await assert.rejects(action('issue',{library_code:'RBCET',barcode:'QA-COPY-A',patron_code:borrower.code}),/multiple copies/);
 const selected=await action('issue',{library_code:'RBCET',barcode:'QA-COPY-A',copy_id:a.id,patron_code:borrower.code});assert.equal(selected.copy_id,a.id);
});

test('linked names outside the first patron page are resolved and account search covers the whole library',async()=>{
 await as(actors.admin);
 await db.exec("insert into app.patrons(institution_id,code,name,category) select 'RBCET','EXTRA-'||n,'Extra '||n,'student' from generate_series(1,250) n");
 const p=(await db.query("insert into app.patrons(id,institution_id,code,name,category) values('ffffffff-ffff-ffff-ffff-ffffffffffff','RBCET','LATE-NAME','A Name Beyond The First Page','faculty') returning *")).rows[0];
 const uid='00000000-0000-0000-0000-000000000088';await db.query('insert into auth.users(id) values($1)',[uid]);await db.query("insert into app.memberships values($1,'RBCET','patron',$2)",[uid,p.id]);
 const workspace=(await db.query("select public.library_workspace('RBCET') d")).rows[0].d;assert.ok(!workspace.patrons.some(r=>r.id===p.id));
 const memberships=(await db.query("select public.library_records_page('RBCET','memberships',null,1000,'') d")).rows[0].d;
 assert.equal(memberships.rows.find(m=>m.user_id===uid)._patron_name,p.name);
 const result=(await db.query("select public.library_account_search('RBCET','NAME BEYOND',null,100) d")).rows[0].d;assert.deepEqual(result.users.map(u=>u.name),[p.name]);
 assert.equal((await db.query("select public.library_account_search('RBCP','NAME BEYOND',null,100) d")).rows[0].d.users.length,0);
 await db.exec('set role authenticated');try{await assert.rejects(db.query("select public.library_account_search('RBCET','',null,100)"),/permission denied/);}finally{await db.exec('reset role');}
});
