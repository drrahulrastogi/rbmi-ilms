import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {authStub,seedDemo,actors} from '../scripts/demo.mjs';
let db,loans,day,month,todayDefinition,oldPaymentIds=[];
const as=id=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
const action=async(action,p,i='RBCET')=>(await db.query('select public.library_action($1,$2,$3) d',[i,action,p])).rows[0].d;
const quote=async id=>(await db.query('select public.library_fine_quote($1,$2) d',['RBCET',id])).rows[0].d;
const statement=async(start=0,size=100,i='RBCET')=>(await db.query('select public.library_fine_month($1,$2,$3,$4) d',[i,month,start,size])).rows[0].d;
const collect=(id,amount,key=randomUUID())=>action('collect_loan_fine',{id,amount,request_key:key,payment_method:'cash',reason:'QA cash collection'});
before(async()=>{db=new PGlite();await db.exec(authStub);const files=(await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();await db.exec(await readFile('supabase/migrations/'+files[0],'utf8'));await db.exec(await readFile('supabase/seed.sql','utf8'));await seedDemo(db);for(const f of files.slice(1))await db.exec(await readFile('supabase/migrations/'+f,'utf8'));await as(actors.librarian);
 day=(await db.query('select app.today()::text d')).rows[0].d;month=(await db.query("select (date_trunc('month',app.today())-interval '1 month')::date::text d")).rows[0].d;
 todayDefinition=(await db.query("select pg_get_functiondef('app.today()'::regprocedure) d")).rows[0].d;
 loans=(await db.query("select * from app.loans where institution_id='RBCET' order by case when patron_id=(select patron_id from app.memberships where institution_id='RBCET' and user_id='00000000-0000-0000-0000-000000000006') then 0 else 1 end,due,id limit 3")).rows;
 await db.query("update app.loans set due=app.today()-4,policy=policy||'{\"fine_rate\":2,\"grace_days\":1,\"exclude_weekends\":false}'::jsonb where id=$1",[loans[0].id]);
});
after(async()=>db.close());
test('fine appears before return without posting a charge, and borrower sees only their own loan',async()=>{const q=await quote(loans[0].id);assert.equal(Number(q.balance),6);assert.equal((await db.query('select count(*) n from app.fines')).rows[0].n,0);const due=(await db.query("select public.library_fines_due('RBCET',null,100,'') d")).rows[0].d;assert.ok(due.rows.some(r=>r.loan_id===loans[0].id&&Number(r.balance)===6));
 await as(actors.patron);assert.equal((await quote(loans[0].id)).patron_id,loans[0].patron_id);assert.equal(Number((await db.query("select public.library_workspace('RBCET') d")).rows[0].d.counts.fine_balance),6);await assert.rejects(quote(loans[1].id),/Access denied/);await as(actors.librarian);
 const circulation=(await db.query("select public.library_circulation_page('RBCET',null,100,'',null,null,'issued','active') d")).rows[0].d;assert.equal(Number(circulation.rows.find(l=>l.id===loans[0].id)._fine_balance),6);
});
test('unpaid and partially paid fines block return; only the librarian collects, with retry-safe receipts',async()=>{await assert.rejects(action('return',{id:loans[0].id,amount:0}),/Collect the outstanding fine/);const key=randomUUID(),receipt=await collect(loans[0].id,2,key);assert.equal((await collect(loans[0].id,2,key)).id,receipt.id);assert.equal(receipt.collected_on,day);assert.equal(receipt.actor,actors.librarian);assert.equal(Number((await quote(loans[0].id)).balance),4);await assert.rejects(action('return',{id:loans[0].id}),/Collect the outstanding fine/);
 await as(actors.accountant);await assert.rejects(collect(loans[0].id,4),/Access denied/);await as(actors.librarian);const q=await quote(loans[0].id);await assert.rejects(action('waive',{id:q.fine_id,amount:4,reason:'bypass'}),/cannot be waived/);await collect(loans[0].id,4);await action('return',{id:loans[0].id,library_code:'RBCET'});
 assert.equal(Number((await quote(loans[0].id)).balance),0);assert.equal((await db.query('select count(*) n from app.fines where loan_id=$1',[loans[0].id])).rows[0].n,1);const l=(await db.query('select * from app.loans where id=$1',[loans[0].id])).rows[0];assert.ok(l.returned&&l.returned_at&&l.returned_by);await assert.rejects(action('return',{id:l.id}),/already returned/);
});
test('a new overdue day after collection requires the additional fine; no duplicate final assessment',async()=>{const id=loans[1].id;await db.query("update app.loans set due=app.today()-2,policy=policy||'{\"fine_rate\":2,\"grace_days\":1,\"exclude_weekends\":false}'::jsonb where id=$1",[id]);const q=await quote(id);await collect(id,Number(q.balance));
 const tomorrow=(await db.query('select (app.today()+1)::text d')).rows[0].d;await db.exec("create or replace function app.today() returns date language sql stable as $$select '"+tomorrow+"'::date$$");
 try{assert.equal(Number((await quote(id)).balance),2);await assert.rejects(action('return',{id}),/Collect the outstanding fine/);await collect(id,2);await action('return',{id});assert.equal(Number((await quote(id)).balance),0);}finally{await db.exec(todayDefinition);}
});
test('monthly report uses collection dates, includes every receipt, and rejects early submission/deposit',async()=>{const loan=loans[2];await db.query('update app.loans set returned=app.today() where id=$1',[loan.id]);const f=(await db.query("insert into app.fines(institution_id,patron_id,loan_id,amount) values('RBCET',$1,$2,50) returning id",[loan.patron_id,loan.id])).rows[0].id;
 for(const amount of [20,30]){const r=await action('pay',{id:f,amount,payment_method:'cash',collected_on:month,request_key:randomUUID(),reason:'QA previous-month cash'});oldPaymentIds.push(r.id);}
 let r=await statement(0,1);assert.equal(r.count,2);assert.equal(Number(r.total),50);assert.equal(r.rows.length,1);assert.equal(r.next_start,1);assert.equal((await statement(1,1)).next_start,null);
 const first=(await db.query("select date_trunc('month',app.today())::date::text d")).rows[0].d;
 if(day!==first.slice(0,8)+new Date(Number(first.slice(0,4)),Number(first.slice(5,7)),0).getDate())await assert.rejects(action('fine_month_submit',{month:first}),/month-end/);
 await as(actors.accountant);await assert.rejects(action('fine_deposit',{payment_ids:oldPaymentIds,deposited_on:day,reference:'EARLY',destination:'accounts'}),/Submit the month-end/);await assert.rejects(action('fine_month_verify',{month,reference:'NO',destination:'accounts'}),/submit this month first/);await as(actors.librarian);
});
test('librarian submission locks the snapshot and backdated collections; accountant verifies the full handover once',async()=>{const before=await statement();const submitted=await action('fine_month_submit',{month});assert.equal((await action('fine_month_submit',{month})).id,submitted.id);await db.query("update app.patrons set name='Changed after submission' where id=$1",[loans[2].patron_id]);assert.equal((await statement()).rows[0].patron_name,before.rows[0].patron_name);
 const fine=(await db.query('select id from app.fines where loan_id=$1',[loans[2].id])).rows[0].id;await assert.rejects(action('pay',{id:fine,amount:1,collected_on:month,payment_method:'cash',reason:'late'}),/month is submitted/);
 await assert.rejects(action('fine_month_verify',{month,reference:'QA-MONTH',destination:'accounts'}),/Access denied/);await as(actors.accountant);await action('fine_deposit',{payment_ids:[oldPaymentIds[0]],deposited_on:day,reference:'QA-PARTIAL-DEPOSIT',destination:'bank',request_key:randomUUID()});assert.equal(Number((await statement()).pending),30);const verified=await action('fine_month_verify',{month,reference:'QA-MONTH',destination:'accounts'});assert.equal((await action('fine_month_verify',{month,reference:'QA-MONTH',destination:'accounts'})).id,verified.id);
 const report=await statement();assert.equal(report.status,'verified');assert.equal(Number(report.total),50);assert.equal(Number(report.deposited),50);assert.equal(Number(report.pending),0);assert.equal((await db.query("select count(*) n from app.fine_deposits where reference='QA-MONTH'")).rows[0].n,1);assert.equal(Number((await db.query("select amount from app.fine_deposits where reference='QA-MONTH'")).rows[0].amount),30);
 await assert.rejects(action('fine_deposit',{payment_ids:oldPaymentIds,deposited_on:day,reference:'DOUBLE',destination:'bank'}),/Receipts/);
});
test('monthly access remains library-scoped and inaccessible to borrowers or direct table readers',async()=>{await as(actors.patron);await assert.rejects(statement(),/Access denied/);await as(actors.librarian);await assert.rejects(action('fine_month_verify',{month},'RBCP'),/Access denied/);await db.exec('set role authenticated');try{await assert.rejects(db.query('select * from app.fine_months'),/permission denied/);await assert.rejects(db.query("select app.library_action_pre_monthly('RBCET','return','{}')"),/permission denied/);}finally{await db.exec('reset role');}});


test('fine start is the first chargeable day after grace, weekends, holidays and unavailable dates',async()=>{
 await db.exec('begin');try{
  const pol={fine_rate:2,fine_cap:500,grace_days:1,exclude_weekends:true};
  const start=async(p=pol)=>(await db.query("select app.fine_start_date('RBCET','2026-11-06',$1)::text d",[p])).rows[0].d;
  assert.equal(await start(),'2026-11-10');
  await db.exec("insert into app.holidays(institution_id,day,name) values('RBCET','2026-11-09','QA holiday') on conflict(institution_id,day) do nothing");
  await db.exec("insert into app.library_availability(institution_id,day,available,reason) values('RBCET','2026-11-10',false,'QA closed') on conflict(institution_id,day) do update set available=false");
  assert.equal(await start(),'2026-11-12');
  assert.equal(await start({...pol,exclude_weekends:false,grace_days:0}),'2026-11-07');
  assert.equal(await start({...pol,fine_rate:0}),null);assert.equal(await start({...pol,fine_cap:0}),null);
  const d=await start();assert.equal(Number((await db.query("select app.fine_for('RBCET','2026-11-06',$1::date-1,$2) f",[d,pol])).rows[0].f),0);
  assert.equal(Number((await db.query("select app.fine_for('RBCET','2026-11-06',$1::date,$2) f",[d,pol])).rows[0].f),2);
 }finally{await db.exec('rollback');}
});
