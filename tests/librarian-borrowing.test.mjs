import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {authStub,seedDemo,actors} from '../scripts/demo.mjs';
let db,registration;
const pharmacy='00000000-0000-0000-0000-000000000007';
const nursing='00000000-0000-0000-0000-000000000008';
const greaterNoida='00000000-0000-0000-0000-000000000009';
const as=id=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
const action=async(i,name,p)=>(await db.query('select public.library_action($1,$2,$3) d',[i,name,p])).rows[0].d;
before(async()=>{
 db=new PGlite();await db.exec(authStub);
 const files=(await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();
 await db.exec(await readFile('supabase/migrations/'+files[0],'utf8'));
 await db.exec(await readFile('supabase/seed.sql','utf8'));await seedDemo(db);
 for(const f of files.slice(1))await db.exec(await readFile('supabase/migrations/'+f,'utf8'));
 // The older demo grants its librarian every library; live librarians have one staff assignment.
 await db.query("delete from app.memberships where user_id=$1 and institution_id<>'RBCET'",[actors.librarian]);
 await db.exec('alter table auth.users add column email text,add column email_confirmed_at timestamptz,add column banned_until timestamptz');
 await db.query("update auth.users set email='rahul.r@rbmi.in',email_confirmed_at=now() where id=$1",[actors.admin]);
 await db.query("update auth.users set email='nidhi@example.invalid',email_confirmed_at=now() where id=$1",[actors.librarian]);
 for(const [id,email] of [[pharmacy,'rekha'],[nursing,'sheeba'],[greaterNoida,'raveena']]){
  await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())",[id,email+'@example.invalid']);
 }
 await as(actors.admin);
 for(const [library,user_id,display_name] of [['RBCP',pharmacy,'Rekha'],['RBCN',nursing,'Sheeba'],['RBGN',greaterNoida,'Raveena']]){
  await action(library,'assign_librarian',{user_id,display_name});
 }
 registration=await readFile('scripts/register-librarian-borrowers.sql','utf8');
});
after(async()=>db.close());
test('all librarians get borrowing memberships while staff permissions stay in their assigned library',async()=>{
 const authCount=(await db.query('select count(*) n from auth.users')).rows[0].n;
 await db.exec(registration);
 const rows=(await db.query("select m.*,s.institution_id home_library,p.category,p.email from app.library_staff s join app.memberships m on m.user_id=s.user_id join app.patrons p on p.id=m.patron_id order by s.institution_id,m.institution_id")).rows;
 assert.equal(rows.length,16);
 assert.ok(rows.every(r=>r.category==='staff'&&r.role===(r.institution_id===r.home_library?'librarian':'patron')));
 assert.equal((await db.query('select count(*) n from auth.users')).rows[0].n,authCount);
 await as(pharmacy);
 const bootstrap=(await db.query('select public.library_bootstrap() d')).rows[0].d;
 assert.equal(bootstrap.memberships.length,4);
 assert.ok(bootstrap.memberships.every(m=>m.role===(m.institution_id==='RBCP'?'librarian':'patron')));
});
test('re-running registration reuses borrowers and produces no duplicate memberships or audit events',async()=>{
 const before=(await db.query("select (select count(*) from app.patrons) patrons,(select count(*) from app.memberships) memberships,(select count(*) from app.audit) audit")).rows[0];
 await db.exec(registration);
 const after=(await db.query("select (select count(*) from app.patrons) patrons,(select count(*) from app.memberships) memberships,(select count(*) from app.audit) audit")).rows[0];
 assert.deepEqual(after,before);
});
test('a librarian issues to a colleague, who sees only their own loan and cannot operate the other library',async()=>{
 await as(actors.librarian);
 const borrower=(await db.query("select * from app.patrons where code='RBCET-LIB-RBCP'")).rows[0];
 const copy=(await db.query("select c.* from app.copies c where c.institution_id='RBCET' and c.status='available' and not exists(select 1 from app.holds h where h.title_id=c.title_id and h.status='waiting') limit 1")).rows[0];
 const loan=await action('RBCET','issue',{library_code:'RBCET',barcode:copy.barcode,patron_code:borrower.code});
 assert.equal(loan.patron_id,borrower.id);assert.equal(loan.issued_by,actors.librarian);
 assert.equal(loan.issue_library_code,'RBCET');
 await as(pharmacy);
 const workspace=(await db.query("select public.library_workspace('RBCET') d")).rows[0].d;
 assert.ok(workspace.loans.some(l=>l.id===loan.id));assert.ok(workspace.loans.every(l=>l.patron_id===borrower.id));
 assert.ok(workspace.patrons.every(p=>p.id===borrower.id));
 await assert.rejects(action('RBCET','issue',{library_code:'RBCET',barcode:copy.barcode,patron_code:borrower.code}),/Patrons may only|Access denied/);
 await assert.rejects(action('RBCET','return',{library_code:'RBCET',id:loan.id}),/Patrons may only|Access denied/);
 await assert.rejects(action('RBCP','return',{library_code:'RBCP',id:loan.id}),/Loan not found|issuing library/);
 await as(actors.librarian);await action('RBCET','return',{library_code:'RBCET',id:loan.id});
 assert.ok((await db.query('select returned from app.loans where id=$1',[loan.id])).rows[0].returned);
});
test('registration refuses to reactivate an administrator-disabled borrowing membership',async()=>{
 await db.query("update app.patrons set active=false where code='RBCET-LIB-RBCP'");
 await assert.rejects(db.exec(registration),/inactive or expired/);await db.exec('rollback');
 assert.equal((await db.query("select active from app.patrons where code='RBCET-LIB-RBCP'")).rows[0].active,false);
});
