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
test('full automatic fine collection rejects partial edits and keeps retry-safe receipts',async()=>{
 await assert.rejects(action('return',{id:loans[0].id,amount:0}),/Collect the outstanding fine/);
 await assert.rejects(collect(loans[0].id,2),/full system-calculated fine/);
 await assert.rejects(collect(loans[0].id,6.01),/full system-calculated fine/);
 await as(actors.accountant);await assert.rejects(collect(loans[0].id,6),/Access denied/);await as(actors.librarian);
 const key=randomUUID(),receipt=await action('collect_loan_fine',{id:loans[0].id,request_key:key,payment_method:'cash',reason:'Full automatic fine'});
 assert.equal(Number(receipt.amount),6);assert.equal((await collect(loans[0].id,6,key)).id,receipt.id);assert.equal(receipt.collected_on,day);assert.equal(receipt.actor,actors.librarian);
 await action('return',{id:loans[0].id,library_code:'RBCET'});assert.equal(Number((await quote(loans[0].id)).balance),0);
 const l=(await db.query('select * from app.loans where id=$1',[loans[0].id])).rows[0];assert.ok(l.returned&&l.returned_at&&l.returned_by);await assert.rejects(action('return',{id:l.id}),/already returned/);
});

test('a new overdue day after collection requires the additional fine; no duplicate final assessment',async()=>{const id=loans[1].id;await db.query("update app.loans set due=app.today()-2,policy=policy||'{\"fine_rate\":2,\"grace_days\":1,\"exclude_weekends\":false}'::jsonb where id=$1",[id]);const q=await quote(id);await collect(id,Number(q.balance));
 const tomorrow=(await db.query('select (app.today()+1)::text d')).rows[0].d;await db.exec("create or replace function app.today() returns date language sql stable as $$select '"+tomorrow+"'::date$$");
 try{assert.equal(Number((await quote(id)).balance),2);await assert.rejects(action('return',{id}),/Collect the outstanding fine/);await collect(id,2);await action('return',{id});assert.equal(Number((await quote(id)).balance),0);}finally{await db.exec(todayDefinition);}
});
test('monthly report uses collection dates, includes every receipt, and rejects early submission/deposit',async()=>{const loan=loans[2];await db.query('update app.loans set returned=app.today() where id=$1',[loan.id]);const f=(await db.query("insert into app.fines(institution_id,patron_id,loan_id,amount) values('RBCET',$1,$2,50) returning id",[loan.patron_id,loan.id])).rows[0].id;
 // Historical partial receipts remain reportable; new desk payments require full balance.
 for(const amount of [20,30]){const r=(await db.query("insert into app.payments(institution_id,fine_id,kind,amount,reason,actor,payment_method,collected_on) values('RBCET',$1,'payment',$2,'Historic partial receipt',$3,'cash',$4) returning id",[f,amount,actors.librarian,month])).rows[0];oldPaymentIds.push(r.id);}await db.query('update app.fines set paid=50 where id=$1',[f]);
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


test('slips use stored staff names, permanent unique numbers and safe list-print access',async()=>{
 await as(actors.librarian);await db.exec("alter table auth.users add column if not exists raw_user_meta_data jsonb");
 await db.query("update app.library_staff set display_name='QA Library Collector' where institution_id='RBCET' and user_id=$1",[actors.librarian]);
 const title=(await action('title',{title:'QA slip book',author:'QA slip author'})).id;
 await action('copy',{title_id:title,accession:'QA-SLIP-COPY',barcode:'QA-SLIP-COPY',institute:'RBCET'});
 const patron=(await db.query("select code from app.patrons where institution_id='RBCET' and category='faculty' limit 1")).rows[0];
 const loan=await action('issue',{library_code:'RBCET',barcode:'QA-SLIP-COPY',patron_code:patron.code});
 assert.match(loan.issue_slip_no,/^RBCET-ISS-\d{4}-\d{6,}$/);assert.equal(loan.issued_by_name,'QA Library Collector');
 await db.query("update app.loans set due=app.today()-2,policy=policy||'{\"fine_rate\":2,\"grace_days\":0,\"exclude_weekends\":false}'::jsonb where id=$1",[loan.id]);
 const amount=Number((await quote(loan.id)).balance);const payment=await collect(loan.id,amount);
 let p=(await db.query("select public.library_register_page('RBCET','collections',null,null,$1,null,1) d",[payment.id])).rows[0].d.rows[0];
 assert.equal(p.actor_name,'QA Library Collector');assert.match(p.slip_no,/^RBCET-F-\d{4}-\d{6,}$/);assert.equal(p.receipt,p.slip_no);
 await action('return',{id:loan.id});const returned=(await db.query('select * from app.loans where id=$1',[loan.id])).rows[0];assert.match(returned.return_slip_no,/^RBCET-RET-/);assert.equal(returned.returned_by_name,'QA Library Collector');assert.notEqual(returned.issue_slip_no,returned.return_slip_no);
 await db.query("update app.library_staff set display_name='Changed later' where user_id=$1",[actors.librarian]);await db.query("update app.payments set reason='QA reprint' where id=$1",[p.id]);
 const reprint=(await db.query('select * from app.payments where id=$1',[p.id])).rows[0];assert.equal(reprint.actor_name,p.actor_name);assert.equal(reprint.slip_no,p.slip_no);
 const key=randomUUID();const print=async()=> (await db.query("select public.library_print_slip('RBCET','collections','{}',$1) d",[key])).rows[0].d;
 const list=await print();assert.match(list.slip_no,/^RBCET-LIST-/);assert.equal(list.actor_name,'Changed later');assert.equal((await print()).slip_no,list.slip_no);
 const monthReport=await statement();assert.ok(monthReport.slip_no);assert.ok(monthReport.submitted_by_name);assert.ok(monthReport.verified_by_name);assert.ok(monthReport.rows.every(r=>r.slip_no&&!r.receipt.startsWith('F-')));
 await as(actors.patron);await assert.rejects(print(),/Access denied/);
 await db.exec('set role authenticated');try{await assert.rejects(db.query('select * from app.print_slips'),/permission denied/);await assert.rejects(db.query("select app.new_slip_number('RBCET','F',current_date)"),/permission denied/);}finally{await db.exec('reset role');}
});


test('borrower downloads only their own paid receipts with original names and slip numbers',async()=>{
 await as(actors.patron);
 const receipts=async(cursor=null,size=100,i='RBCET')=>(await db.query('select public.library_my_receipts($1,$2,$3) d',[i,cursor,size])).rows[0].d;
 const first=await receipts(null,1);assert.equal(first.total,1);assert.equal(first.rows.length,1);assert.ok(first.next_id);
 assert.equal((await receipts(first.rows[0].id,1)).rows.length,0);
 const ownFine=(await db.query('select id from app.fines where loan_id=$1',[loans[0].id])).rows[0].id;
 const ownPayments=(await db.query('select * from app.payments where fine_id=$1 order by id',[ownFine])).rows;
 assert.deepEqual((await receipts()).rows.map(r=>r.id),ownPayments.map(r=>r.id));
 const row=first.rows[0],original=ownPayments.find(p=>p.id===row.id);assert.equal(row.slip_no,original.slip_no);assert.equal(row.actor_name,original.actor_name);
 assert.ok(!('actor' in row));assert.ok(!('patron_id' in row));assert.ok(!('request_key' in row));assert.ok(!('fine_id' in row));
 await assert.rejects(receipts(null,201),/Invalid receipt page/);assert.equal((await receipts(null,10,'RBCP')).total,0);await assert.rejects(receipts(null,10,'NO_LIBRARY'),/Access denied/);
 const foreign=(await db.query('select id from app.payments where fine_id<>$1 limit 1',[ownFine])).rows[0];assert.ok(!(await receipts(foreign.id)).rows.some(r=>r.id===foreign.id));
 const ownId=(await db.query("select patron_id from app.memberships where user_id=$1 and institution_id='RBCET'",[actors.patron])).rows[0].patron_id;
 await db.query('update app.memberships set patron_id=$1 where user_id=$2 and institution_id=$3',[loans[1].patron_id,actors.patron,'RBCET']);
 assert.ok((await receipts()).rows.every(r=>!ownPayments.some(p=>p.id===r.id)));
 await db.query('update app.memberships set patron_id=$1 where user_id=$2 and institution_id=$3',[ownId,actors.patron,'RBCET']);
 await as(actors.librarian);await assert.rejects(receipts(),/Access denied/);
 await db.exec('set role anon');try{await assert.rejects(receipts(),/permission denied/);}finally{await db.exec('reset role');}
});


test('fractional fine rounds up to whole rupees and cannot be underpaid via direct pay',async()=>{
 await as(actors.librarian);await db.exec('begin');try{
 const l=(await db.query("select * from app.loans where institution_id='RBCET' and returned is null limit 1")).rows[0];
 await db.query("delete from app.fines where loan_id=$1",[l.id]);
 await db.query("update app.loans set due=app.today()-1,policy=policy||'{\"fine_rate\":2.5,\"grace_days\":0,\"exclude_weekends\":false}'::jsonb where id=$1",[l.id]);
 assert.equal(Number((await quote(l.id)).balance),3);
 const f=(await db.query("insert into app.fines(institution_id,patron_id,loan_id,amount) values('RBCET',$1,$2,2.5) returning id",[l.patron_id,l.id])).rows[0];
 await db.exec('savepoint rejected_payment');await assert.rejects(action('pay',{id:f.id,amount:2.5,payment_method:'cash',reason:'edited'}),/full system-calculated/);await db.exec('rollback to savepoint rejected_payment');
 const r=await action('pay',{id:f.id,payment_method:'cash',reason:'Automatic whole rupees',request_key:randomUUID()});
 assert.equal(Number((await db.query('select amount from app.payments where id=$1',[r.id])).rows[0].amount),3);assert.equal(Number((await quote(l.id)).balance),0);
 }finally{await db.exec('rollback');}
});


test('nobody can waive a fine, including admin, librarian and accountant',async()=>{
 const fine=(await db.query('select id from app.fines where loan_id=$1',[loans[0].id])).rows[0].id;
 for(const actor of [actors.admin,actors.librarian,actors.accountant,actors.assistant,actors.patron]){
  await as(actor);await assert.rejects(action('waive',{id:fine,amount:1,reason:'Forbidden waiver'}),/waivers are disabled for everyone/);
 }
 await as(actors.librarian);
 await assert.rejects(db.query('update app.fines set waived=1,amount=amount+1 where id=$1',[fine]),/waivers are disabled/);
 await assert.rejects(db.query("insert into app.payments(institution_id,fine_id,kind,amount,reason,actor) values('RBCET',$1,'waiver',1,'Forbidden',$2)",[fine,actors.librarian]),/waivers are disabled/);
 assert.equal(Number((await db.query('select waived from app.fines where id=$1',[fine])).rows[0].waived),0);
});
