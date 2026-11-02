import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {authStub,seedDemo,actors} from '../scripts/demo.mjs';
let db,day,fine,receipt,acquired;
const as=id=>db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);
const action=async(action,p,i='RBCET')=>(await db.query('select public.library_action($1,$2,$3) d',[i,action,p])).rows[0].d;
const page=async(kind,q='',size=100,cursor=null,i='RBCET')=>(await db.query('select public.library_register_page($1,$2,null,null,$3,$4,$5) d',[i,kind,q,cursor,size])).rows[0].d;
const donation=(extra={})=>({source:'donation',institute:'RBMI',title:'QA Donated Knowledge',author:'QA Author',donor_name:'QA Donor',donor_contact:'Campus',quantity:2,unit_price:125,prefix:'QA-DONATION',day,request_key:randomUUID(),...extra});
before(async()=>{db=new PGlite();await db.exec(authStub);const files=(await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();await db.exec(await readFile('supabase/migrations/'+files[0],'utf8'));await db.exec(await readFile('supabase/seed.sql','utf8'));await seedDemo(db);for(const f of files.slice(1))await db.exec(await readFile('supabase/migrations/'+f,'utf8'));await as(actors.admin);day=(await db.query('select app.today()::text d')).rows[0].d;
const loan=(await db.query("select * from app.loans where institution_id='RBCET' limit 1")).rows[0];await db.query('update app.loans set returned=app.today() where id=$1',[loan.id]);fine=(await db.query("insert into app.fines(institution_id,patron_id,loan_id,amount) values('RBCET',$1,$2,100) returning id",[loan.patron_id,loan.id])).rows[0].id;});
after(async()=>db.close());
test('donation creates normal copies with provenance and repeat-safe donor grouping',async()=>{const p=donation();acquired=await action('acquire',p);assert.equal((await action('acquire',p)).id,acquired.id);const copies=(await db.query('select *,accessioned_on::text as accessioned_on from app.copies where acquisition_id=$1',[acquired.id])).rows;assert.equal(copies.length,2);assert.ok(copies.every(c=>c.institute==='RBMI'&&c.status==='available'&&c.accessioned_on===day));
 await action('acquire',donation({prefix:'QA-DONATION-SECOND',quantity:1}));const report=await page('acquisitions','qa donor');assert.equal(report.summary.donated_books,3);assert.equal(report.summary.donors,1);assert.equal(Number(report.summary.donated_value),375);assert.ok(report.rows.every(r=>r.donor_name==='QA Donor'&&r.received_at===day));
 const ptn=(await db.query("select code from app.patrons where institution_id='RBCET' and category='faculty' limit 1")).rows[0];const loan=await action('issue',{barcode:copies[0].barcode,patron_code:ptn.code,library_code:'RBCET'});assert.equal(loan.copy_id,copies[0].id);
});
test('invalid institute, missing donor and accession collision roll back acquisition atomically',async()=>{const before=(await page('acquisitions')).total;await assert.rejects(action('acquire',donation({institute:'RBCN',prefix:'FAIL'})),/Institute/);await assert.rejects(action('acquire',donation({donor_name:'',prefix:'FAIL'})),/Donor/);await assert.rejects(action('acquire',donation({quantity:3,prefix:'QA-DONATION'})),/duplicate|accession|exists/i);assert.equal((await page('acquisitions')).total,before);});
test('exchange, other and purchased books enter the same inventory without inflating donations',async()=>{for(const source of ['exchange','other','purchase']){const vendor=(await db.query("select id from app.vendors where institution_id='RBCET' limit 1")).rows[0].id;await action('acquire',donation({source,vendor_id:vendor,prefix:'QA-'+source,donor_name:''}));}assert.equal((await page('acquisitions','qa donor')).summary.donated_books,3);});
test('register pagination and date filters cover the full dataset',async()=>{const first=await page('acquisitions','',2);assert.equal(first.rows.length,2);assert.ok(first.next_id);const next=await page('acquisitions','',2,first.next_id);assert.ok(next.rows.every(r=>!first.rows.some(a=>a.id===r.id)));assert.equal(next.total,first.total);const future=(await db.query("select public.library_register_page('RBCET','acquisitions','2099-01-01','2099-01-02','',null,100) d")).rows[0].d;assert.equal(future.total,0);});
test('fine collections preserve balance, generate receipt and replay without double collection',async()=>{await as(actors.librarian);const p={id:fine,amount:100,reason:'Cash received',payment_method:'cash',collected_on:(await db.query("select (date_trunc('month',app.today())-interval '1 day')::date::text d")).rows[0].d,request_key:randomUUID()};receipt=await action('pay',p);assert.match(receipt.receipt,/^F-/);assert.equal((await action('pay',p)).id,receipt.id);assert.equal(Number((await db.query('select paid from app.fines where id=$1',[fine])).rows[0].paid),100);const rows=await page('collections',receipt.id);assert.equal(rows.total,1);assert.equal(rows.rows[0].payment_method,'cash');assert.equal(Number(rows.summary.pending),100);await assert.rejects(action('pay',{...p,request_key:randomUUID(),amount:81}),/No fine is payable/);});
test('only accountant/admin deposits money; a receipt cannot settle twice or across libraries',async()=>{const p={payment_ids:[receipt.id],deposited_on:day,reference:'QA-ACCOUNTS-1',destination:'accounts',request_key:randomUUID()};await assert.rejects(action('fine_deposit',p),/Access denied/);await action('fine_month_submit',{month:(await db.query("select (date_trunc('month',app.today())-interval '1 day')::date::text d")).rows[0].d});await as(actors.accountant);await assert.rejects(action('fine_deposit',p,'RBCP'),/Receipts/);const deposit=await action('fine_deposit',p);assert.equal(Number(deposit.amount),100);assert.equal((await action('fine_deposit',p)).id,deposit.id);await assert.rejects(action('fine_deposit',{...p,request_key:randomUUID(),reference:'QA-DOUBLE'}),/Receipts/);await assert.rejects(action('fine_deposit',{...p,payment_ids:[receipt.id,receipt.id],request_key:randomUUID()}),/Duplicate/);const report=await page('collections',receipt.id);assert.equal(Number(report.summary.pending),0);assert.equal(Number(report.summary.deposited),100);assert.equal(report.rows[0].deposit_reference,p.reference);assert.equal((await page('deposits')).total,1);});
test('borrowers and assistants cannot access financial registers; tables are not directly exposed',async()=>{await as(actors.patron);await assert.rejects(page('collections'),/Access denied/);await assert.rejects(action('acquire',donation({prefix:'NO'})),/Access denied/);await as(actors.assistant);await assert.rejects(page('acquisitions'),/Access denied/);await db.exec('set role authenticated');try{await assert.rejects(db.query('select * from app.fine_deposits'),/permission denied/);await assert.rejects(db.query('select app.library_action_pre_registers($1,$2,$3)',['RBCET','pay',{}]),/permission denied/);}finally{await db.exec('reset role');}});


test('one named acknowledgement includes all books from a donor and remains library scoped',async()=>{
 await as(actors.librarian);
 const ack=async id=>(await db.query("select public.library_donation_acknowledgement('RBCET',$1) d",[id])).rows[0].d;
 const a=await ack(acquired.id);assert.equal(a.donor_name,'QA Donor');assert.equal(a.books.length,2);assert.equal(a.books.reduce((n,b)=>n+b.quantity,0),3);assert.match(a.slip_no,/^RBCET-DON-/);
 const second=(await page('acquisitions','qa donor')).rows.find(r=>r.id!==acquired.id);assert.equal((await ack(second.id)).slip_no,a.slip_no);
 await as(actors.patron);await assert.rejects(ack(acquired.id),/Access denied/);await as(actors.librarian);
 await assert.rejects(db.query("select public.library_donation_acknowledgement('RBCP',$1)",[acquired.id]),/Access denied|not found/);
});


test('donor PDF contains the name, combined books and RBMI logo on every page',async()=>{
 const {donationDocument,buildRegisterPDF}=await import('../src/register-print.mjs');
 const d=donationDocument({donor_name:'QA Donor Name',donor_contact:'Campus',slip_no:'RBCET-DON-2026-000001',as_of:'2026-11-02',books:Array.from({length:75},(_,n)=>({title:'Donated book '+n,author:'QA Author',institute:'RBMI',received_at:'2026-11-01',quantity:2,value:200,recorded_by_name:'QA Librarian'}))},'RBCET');
 assert.ok(d.lines.includes('Donor: QA Donor Name'));assert.ok(d.lines.includes('Total books received: 150'));
 assert.ok(!JSON.stringify(d).includes('DON-2d6c0957'));
 const doc=await buildRegisterPDF(d.title,d.lines,d.columns,d.rows,{logoBytes:await readFile('public/rbmi-logo.png'),closingLines:d.closingLines});
 const pdf=doc.output();const pages=doc.getNumberOfPages();assert.ok(pages>1);assert.ok(pdf.includes('/Subtype /Image'));assert.equal((pdf.match(/\/I0 Do/g)||[]).length,pages);
});


test('payments PDF includes receipt numbers, collector names, dates and total',async()=>{
 const {paymentsDocument}=await import('../src/register-print.mjs');
 const d=paymentsDocument([{slip_no:'RBCET-F-2026-000001',patron_name:'QA Student',patron_code:'123',amount:6,actor_name:'QA Librarian',reason:'Cash fine',collected_on:'2026-11-02'}],'RBCET',{slip_no:'RBCET-LIST-2026-000002',actor_name:'QA Librarian'});
 assert.equal(d.title,'Payments');assert.ok(d.lines.includes('Total collected: INR 6.00'));assert.deepEqual(d.rows[0],['RBCET-F-2026-000001','QA Student / 123','6.00','QA Librarian','Cash fine','2026-11-02']);
});
