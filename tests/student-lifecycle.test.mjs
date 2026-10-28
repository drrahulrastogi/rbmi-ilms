import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {authStub,seedDemo,actors} from '../scripts/demo.mjs';
import {admissionYear,completionDate,studentStatus} from '../src/student-lifecycle.mjs';
let db,student,uid='00000000-0000-0000-0000-000000000091';
const as=id=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
const action=async(name,p,i='RBCET')=>(await db.query('select public.library_action($1,$2,$3) d',[i,name,p])).rows[0].d;
before(async()=>{
 db=new PGlite();await db.exec(authStub);
 const files=(await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();
 await db.exec(await readFile('supabase/migrations/'+files[0],'utf8'));await db.exec(await readFile('supabase/seed.sql','utf8'));await seedDemo(db);
 for(const f of files.slice(1))await db.exec(await readFile('supabase/migrations/'+f,'utf8'));
 await as(actors.admin);
 await action('course_policy',{course:'QA three-year course',duration_years:3,completion_month:6,completion_day:30});
 const result=await action('patron',{code:'QA-GRADUATE',name:'QA Graduate',category:'student',active:true,course:'QA three-year course',admission_year:'2020',profile:{institute:'RBCET'}});
 student=(await db.query("select * from app.patrons where institution_id='RBCET' and code='QA-GRADUATE'")).rows[0];
 await db.query('insert into auth.users(id) values($1)',[uid]);await db.query("insert into app.memberships(user_id,institution_id,role,patron_id) values($1,'RBCET','patron',$2)",[uid,student.id]);
});
after(async()=>db.close());

test('two, three and four year courses use configured cutoff, with exact date and admin exceptions',()=>{
 assert.equal(admissionYear('2022-2023'),2022);assert.equal(admissionYear('2022-23'),2022);assert.equal(admissionYear('2022-2024'),null);
 for(const years of [2,3,4]){
  const p={category:'student',active:true,profile:{admission_year:'2022',course:'Course'}};
  const policies=[{course:'Course',duration_years:years,completion_month:6,completion_day:30}];
  assert.equal(completionDate(p,policies),(2022+years)+'-06-30');
  assert.equal(completionDate({...p,profile:{course:'Course',admission_year:'2022-2023'}},policies),(2022+years)+'-06-30');
  assert.equal(studentStatus(p,policies,(2022+years)+'-06-30'),'active');
  assert.equal(studentStatus(p,policies,(2022+years)+'-07-01'),'passed_out');
  assert.equal(studentStatus({...p,graduation_override:true},policies,'2030-01-01'),'active');
  assert.equal(completionDate({...p,course_end_date:'2028-05-10'},policies),'2028-05-10');
 }
 assert.equal(completionDate({category:'student',profile:{admission_year:'2022',course:'Unconfigured'}},[]),null);
 assert.equal(completionDate({category:'student',profile:{course:'Course'}},[{course:'Course',duration_years:3}]),null);
});
test('completed student is passed out, blocked with existing token and cannot issue books',async()=>{
 assert.equal(student.status,'passed_out');assert.equal(student.active,false);
 await as(uid);const boot=(await db.query('select public.library_bootstrap() d')).rows[0].d;assert.equal(boot.memberships.length,0);
 const setup=(await db.query('select public.library_onboarding() d')).rows[0].d;assert.equal(setup.account_disabled,true);
 await assert.rejects(db.query("select public.library_workspace('RBCET')"),/Passed out/);
 await as(actors.admin);await assert.rejects(action('issue',{library_code:'RBCET',barcode:'RBCET-120',patron_code:'QA-GRADUATE'}),/passed out/i);
});
test('only admin reactivates; override survives scheduled job and can be removed',async()=>{
 await as(actors.librarian);await assert.rejects(action('reactivate_student',{id:student.id,reason:'Not authorized'}),/Access denied/);
 await as(actors.admin);await action('reactivate_student',{id:student.id,reason:'Approved extended library access'});
 await db.query('select app.mark_passed_out_students()');
 let p=(await db.query('select * from app.patrons where id=$1',[student.id])).rows[0];assert.equal(p.status,'active');assert.equal(p.active,true);assert.equal(p.graduation_override,true);
 await as(uid);assert.equal((await db.query('select public.library_bootstrap() d')).rows[0].d.memberships.length,1);
 await as(actors.admin);await action('resume_graduation',{id:student.id,reason:'Extension ended'});
 p=(await db.query('select * from app.patrons where id=$1',[student.id])).rows[0];assert.equal(p.status,'passed_out');assert.equal(p.active,false);assert.equal(p.graduation_override,false);
});
test('scheduled transition preserves identity, loans, fines and manual inactivity before completion',async()=>{
 await as(actors.admin);await action('patron',{code:'QA-SCHEDULED',name:'QA Scheduled',category:'student',active:false,course:'QA three-year course',admission_year:'2090'});
 const p=(await db.query("select * from app.patrons where code='QA-SCHEDULED'")).rows[0];assert.equal(p.status,'inactive');
 const counts=(await db.query('select (select count(*) from app.loans) loans,(select count(*) from app.fines) fines')).rows[0];
 await db.exec('alter table app.patrons disable trigger patron_lifecycle');
 try{await db.query("update app.patrons set profile=profile||'{\"admission_year\":\"2020\"}' where id=$1",[p.id]);}finally{await db.exec('alter table app.patrons enable trigger patron_lifecycle');}
 await db.query('select app.mark_passed_out_students()');
 const changed=(await db.query('select * from app.patrons where id=$1',[p.id])).rows[0];assert.equal(changed.id,p.id);assert.equal(changed.status,'passed_out');assert.equal(changed.active,false);
 assert.deepEqual((await db.query('select (select count(*) from app.loans) loans,(select count(*) from app.fines) fines')).rows[0],counts);
});
test('faculty and librarian membership are not disabled by student completion',async()=>{
 await as(actors.admin);await action('patron',{code:'QA-FACULTY',name:'QA Faculty',category:'faculty',active:true,course:'QA three-year course',admission_year:'2000'});
 const p=(await db.query("select * from app.patrons where code='QA-FACULTY'")).rows[0];assert.equal(p.status,'active');
 await db.query("insert into app.memberships(user_id,institution_id,role) values($1,'RBCP','assistant')",[uid]);
 await as(uid);assert.equal((await db.query('select public.library_onboarding() d')).rows[0].d.account_disabled,false);
});
test('book creation includes accession and date atomically; duplicate identifiers never leave a title',async()=>{
 await as(actors.admin);const result=await action('book',{title:'QA Atomic Book',author:'QA Author',accession:'QA-ACC-NEW',institute:'RBCET',accessioned_on:'2026-10-28',price:120});
 const c=(await db.query('select * from app.copies where title_id=$1',[result.id])).rows[0];assert.equal(c.accession,'QA-ACC-NEW');assert.equal(c.barcode,c.accession);assert.equal(new Date(c.accessioned_on).toISOString().slice(0,10),'2026-10-28');
 const before=(await db.query('select count(*) n from app.titles')).rows[0].n;
 await assert.rejects(action('book',{title:'Duplicate must roll back',author:'QA',accession:'qa-acc-new',barcode:'UNIQUE-NEW',institute:'RBCET'}),/unique|duplicate/i);
 assert.equal((await db.query('select count(*) n from app.titles')).rows[0].n,before);
 await assert.rejects(action('book',{title:'Missing copy',author:'QA',institute:'RBCET'}),/Accession/);
});
