-- Preserve existing purchases and payment history. Legacy payment methods are unknown.
create table app.donors(
 id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,
 name text not null check(length(btrim(name)) between 1 and 200),contact text not null default '' check(length(contact)<=300),
 unique(institution_id,id));
create unique index donors_identity on app.donors(institution_id,lower(btrim(name)),lower(btrim(contact)));
alter table app.donors enable row level security;
revoke all on app.donors from public,anon,authenticated;
alter table app.acquisitions alter column vendor_id drop not null,
 add column source text not null default 'purchase' check(source in ('purchase','donation','exchange','other')),
 add column donor_id uuid references app.donors,
 add column institute text,
 add column notes text not null default '',
 add column request_key uuid unique,
 add constraint acquisition_donor_library foreign key(institution_id,donor_id) references app.donors(institution_id,id),
 add constraint acquisition_source_details check((source<>'purchase' or vendor_id is not null) and (source<>'donation' or donor_id is not null));
alter table app.copies add column acquisition_id uuid references app.acquisitions;
create index copies_acquisition on app.copies(acquisition_id);
create index acquisitions_register on app.acquisitions(institution_id,ordered_at,id);
alter table app.payments add column payment_method text not null default 'unknown' check(payment_method in ('unknown','cash','upi','bank','card')),
 add column collected_on date,
 add column request_key uuid unique;
update app.payments set collected_on=(created_at at time zone 'Asia/Kolkata')::date;
alter table app.payments alter column collected_on set default app.today(),alter column collected_on set not null;
create index payments_register on app.payments(institution_id,collected_on,id);
create table app.fine_deposits(
 id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,
 deposited_on date not null,reference text not null check(length(btrim(reference)) between 1 and 200),
 destination text not null check(destination in ('accounts','bank')),amount numeric(12,2) not null check(amount>0),
 actor uuid not null references auth.users,created_at timestamptz not null default now(),request_key uuid not null unique,
 unique(institution_id,reference));
create table app.fine_deposit_items(
 payment_id uuid primary key references app.payments,deposit_id uuid not null references app.fine_deposits);
create index fine_deposit_items_deposit on app.fine_deposit_items(deposit_id);
create index fine_deposits_register on app.fine_deposits(institution_id,deposited_on,id);
alter table app.fine_deposits enable row level security;
alter table app.fine_deposit_items enable row level security;
revoke all on app.fine_deposits,app.fine_deposit_items from public,anon,authenticated;

alter function public.library_action(text,text,jsonb) rename to library_action_pre_registers;
alter function public.library_action_pre_registers(text,text,jsonb) set schema app;
revoke all on function app.library_action_pre_registers(text,text,jsonb) from public,anon,authenticated;
create function public.library_action(i text,action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;v uuid;tid uuid;donor uuid;campus text;qty integer;cost numeric;amt numeric;f app.fines;a app.acquisitions;
 pay app.payments;key uuid;ids uuid[];cnt integer;collection_day date;deposit_day date;method text;rec record;
begin
 if action not in ('acquire','receive','pay','fine_deposit') then return app.library_action_pre_registers(i,action,p);end if;
 if action in ('acquire','receive') then perform app.require_role(i,array['admin','librarian']);
 elsif action='pay' then perform app.require_role(i,array['admin','librarian','accountant']);
 else perform app.require_role(i,array['admin','accountant']);end if;
 key:=coalesce(nullif(p->>'request_key','')::uuid,gen_random_uuid());
 -- Serialize acquisition capture and deposit selection inside the library.
 perform 1 from app.institutions where id=i for update;
 if action='acquire' then
  select id into v from app.acquisitions where request_key=key and institution_id=i;
  if found then return jsonb_build_object('id',v,'replayed',true);end if;
  if coalesce(p->>'source','') not in ('purchase','donation','exchange','other') then raise exception 'Choose an acquisition source';end if;
  campus:=app.book_institute(i,p->>'institute');if campus is null then raise exception 'Institute is required';end if;
  qty:=(p->>'quantity')::integer;cost:=(p->>'unit_price')::numeric;
  if qty is null or qty not between 1 and 1000 or cost is null or cost<0 or cost>9999999 then raise exception 'Invalid quantity or value';end if;
  collection_day:=coalesce(nullif(p->>'day','')::date,app.today());
  if collection_day>app.today() or collection_day<'1900-01-01'::date then raise exception 'Invalid acquisition date';end if;
  if length(btrim(coalesce(p->>'title','')))=0 or length(btrim(coalesce(p->>'author','')))=0 then raise exception 'Title and author required';end if;
  select id into tid from app.titles where institution_id=i and lower(btrim(title))=lower(btrim(p->>'title')) and lower(btrim(author))=lower(btrim(p->>'author')) and coalesce(isbn,'')=coalesce(p->>'isbn','') order by id limit 1;
  if tid is null then result:=app.library_action_pre_registers(i,'title',p);tid:=(result->>'id')::uuid;end if;
  if p->>'source'='donation' then
   if length(btrim(coalesce(p->>'donor_name','')))=0 then raise exception 'Donor name required';end if;
   insert into app.donors(institution_id,name,contact) values(i,btrim(p->>'donor_name'),btrim(coalesce(p->>'donor_contact','')))
    on conflict(institution_id,lower(btrim(name)),lower(btrim(contact))) do update set name=excluded.name returning id into donor;
  end if;
  if p->>'source'='purchase' and not exists(select 1 from app.vendors where id=nullif(p->>'vendor_id','')::uuid and institution_id=i) then raise exception 'Select a vendor in this library';end if;
  insert into app.acquisitions(institution_id,vendor_id,title_id,invoice,quantity,unit_price,source,donor_id,institute,notes,ordered_at,request_key)
   values(i,case when p->>'source'='purchase' then (p->>'vendor_id')::uuid end,tid,coalesce(nullif(btrim(p->>'reference'),''),'ACQ-'||key),qty,cost,p->>'source',donor,campus,coalesce(p->>'notes',''),collection_day,key) returning id into v;
  result:=public.library_action(i,'receive',jsonb_build_object('id',v,'prefix',p->>'prefix','shelf',p->>'shelf','received_on',collection_day));
  insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,jsonb_build_object('id',v,'source',p->>'source','copies',qty));
  return jsonb_build_object('id',v);
 elsif action='receive' then
  select * into a from app.acquisitions where id=(p->>'id')::uuid and institution_id=i for update;
  if not found or a.status<>'ordered' then raise exception 'Open order not found';end if;
  campus:=app.book_institute(i,coalesce(nullif(p->>'institute',''),a.institute));
  if campus is null then select campuses[1] into campus from app.institutions where id=i;end if;
  collection_day:=coalesce(nullif(p->>'received_on','')::date,app.today());
  if collection_day>app.today() or collection_day<a.ordered_at then raise exception 'Invalid received date';end if;
  result:=app.library_action_pre_registers(i,action,p);
  update app.copies set acquisition_id=a.id,institute=campus,accessioned_on=collection_day
   where institution_id=i and title_id=a.title_id and accession in (select (p->>'prefix')||'-'||n from generate_series(1,a.quantity) n);
  update app.acquisitions set institute=campus,received_at=collection_day where id=a.id;
  return result;
 elsif action='pay' then
  select * into pay from app.payments where request_key=key and institution_id=i;
  if found then return jsonb_build_object('id',pay.id,'receipt','F-'||pay.id,'replayed',true);end if;
  select * into f from app.fines where id=(p->>'id')::uuid and institution_id=i for update;
  if not found then raise exception 'Fine not found';end if;
  amt:=(p->>'amount')::numeric;method:=coalesce(nullif(p->>'payment_method',''),'cash');
  collection_day:=coalesce(nullif(p->>'collected_on','')::date,app.today());
  if amt is null or amt<=0 or amt<>round(amt,2) or amt>f.amount-f.paid-f.waived then raise exception 'Invalid payment amount';end if;
  if method not in ('cash','upi','bank','card') or collection_day>app.today() or collection_day<'1900-01-01'::date then raise exception 'Invalid payment method or date';end if;
  if length(btrim(coalesce(p->>'reason','')))=0 then raise exception 'Receipt/reference required';end if;
  update app.fines set paid=paid+amt where id=f.id;
  insert into app.payments(institution_id,fine_id,kind,amount,reason,actor,payment_method,collected_on,request_key)
   values(i,f.id,'payment',amt,p->>'reason',auth.uid(),method,collection_day,key) returning id into v;
  insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,jsonb_build_object('id',v,'fine_id',f.id,'amount',amt,'method',method));
  return jsonb_build_object('id',v,'receipt','F-'||v);
 else
  select id into v from app.fine_deposits where request_key=key and institution_id=i;
  if found then return jsonb_build_object('id',v,'replayed',true);end if;
  if jsonb_typeof(p->'payment_ids') is distinct from 'array' or jsonb_array_length(p->'payment_ids') not between 1 and 500 then raise exception 'Select 1 to 500 receipts';end if;
  select array_agg(value::uuid) into ids from jsonb_array_elements_text(p->'payment_ids');
  if cardinality(ids)<>(select count(distinct x) from unnest(ids) x) then raise exception 'Duplicate receipt selected';end if;
  deposit_day:=(p->>'deposited_on')::date;
  if deposit_day is null or deposit_day>app.today() or deposit_day<'1900-01-01'::date then raise exception 'Invalid deposit date';end if;
  perform 1 from app.payments where institution_id=i and id=any(ids) order by id for update;
  select count(*),sum(amount) into cnt,amt from app.payments x where x.id=any(ids) and x.institution_id=i and x.kind='payment' and x.collected_on<=deposit_day
    and not exists(select 1 from app.fine_deposit_items d where d.payment_id=x.id);
  if cnt<>cardinality(ids) then raise exception 'Receipts must be un-deposited payments in this library and collected by the deposit date';end if;
  insert into app.fine_deposits(institution_id,deposited_on,reference,destination,amount,actor,request_key)
   values(i,deposit_day,btrim(p->>'reference'),p->>'destination',amt,auth.uid(),key) returning id into v;
  insert into app.fine_deposit_items(payment_id,deposit_id) select x,v from unnest(ids) x;
  insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,jsonb_build_object('id',v,'payment_ids',ids,'amount',amt));
  return jsonb_build_object('id',v,'amount',amt);
 end if;
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;

-- Filter before aggregating/paging so reports are never limited to the first workspace page.
create function public.library_register_page(i text,kind text,from_day date default null,to_day date default null,q text default '',after_id uuid default null,page_size integer default 100)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare rows_data jsonb;summary jsonb;total bigint;last_id uuid;begin
 perform app.require_role(i,array['admin','librarian','accountant','auditor']);
 if kind not in ('acquisitions','collections','deposits') or page_size is null or page_size not between 1 and 500 or length(coalesce(q,''))>200 or from_day>to_day then raise exception 'Invalid register filter';end if;
 if kind='acquisitions' then
  with filtered as(select a.*,t.title,d.name donor_name,d.contact donor_contact,v.name vendor_name
   from app.acquisitions a join app.titles t on t.id=a.title_id left join app.donors d on d.id=a.donor_id left join app.vendors v on v.id=a.vendor_id
   where a.institution_id=i and (from_day is null or a.ordered_at>=from_day) and (to_day is null or a.ordered_at<=to_day)
    and (coalesce(q,'')='' or concat_ws(' ',a.invoice,t.title,d.name,a.institute,a.source) ilike '%'||q||'%')),
  paged as(select * from filtered where after_id is null or id>after_id order by id limit page_size)
  select (select coalesce(jsonb_agg(to_jsonb(p) order by id),'[]') from paged p),count(*),jsonb_build_object(
   'donated_books',coalesce(sum(quantity) filter(where source='donation' and status='received'),0),
   'donors',count(distinct donor_id) filter(where source='donation' and status='received'),
   'donated_value',coalesce(sum(quantity*unit_price) filter(where source='donation' and status='received'),0))
   into rows_data,total,summary from filtered;
 elsif kind='collections' then
  with filtered as(select x.*,p.name patron_name,p.code patron_code,di.deposit_id,fd.reference deposit_reference,fd.deposited_on,
   'F-'||x.id as receipt from app.payments x join app.fines f on f.id=x.fine_id join app.patrons p on p.id=f.patron_id
   left join app.fine_deposit_items di on di.payment_id=x.id left join app.fine_deposits fd on fd.id=di.deposit_id
   where x.institution_id=i and x.kind='payment' and (from_day is null or x.collected_on>=from_day) and (to_day is null or x.collected_on<=to_day)
    and (coalesce(q,'')='' or concat_ws(' ',p.name,p.code,x.reason,x.id::text,x.payment_method) ilike '%'||q||'%')),
  paged as(select * from filtered where after_id is null or id>after_id order by id limit page_size)
  select (select coalesce(jsonb_agg(to_jsonb(p) order by id),'[]') from paged p),count(*),jsonb_build_object(
   'collected',coalesce(sum(amount),0),'deposited',coalesce(sum(amount) filter(where deposit_id is not null),0),
   'pending',coalesce(sum(amount) filter(where deposit_id is null),0),
   'cash_pending',coalesce(sum(amount) filter(where deposit_id is null and payment_method='cash'),0),
   'unknown_pending',coalesce(sum(amount) filter(where deposit_id is null and payment_method='unknown'),0)) into rows_data,total,summary from filtered;
 else
  with filtered as(select d.*,(select jsonb_agg(payment_id order by payment_id) from app.fine_deposit_items where deposit_id=d.id) payment_ids
   from app.fine_deposits d where d.institution_id=i and (from_day is null or deposited_on>=from_day) and (to_day is null or deposited_on<=to_day)
   and (coalesce(q,'')='' or concat_ws(' ',reference,destination) ilike '%'||q||'%')),
  paged as(select * from filtered where after_id is null or id>after_id order by id limit page_size)
  select (select coalesce(jsonb_agg(to_jsonb(p) order by id),'[]') from paged p),count(*),jsonb_build_object('deposited',coalesce(sum(amount),0)) into rows_data,total,summary from filtered;
 end if;
 if jsonb_array_length(rows_data)=page_size then last_id:=(rows_data->(page_size-1)->>'id')::uuid;end if;
 return jsonb_build_object('rows',rows_data,'total',total,'summary',summary,'next_id',last_id);
end$$;
revoke all on function public.library_register_page(text,text,date,date,text,uuid,integer) from public,anon;
grant execute on function public.library_register_page(text,text,date,date,text,uuid,integer) to authenticated;
