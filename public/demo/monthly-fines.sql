create table app.fine_months(
 id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,
 month date not null check(extract(day from month)=1),details jsonb not null,total numeric(12,2) not null check(total>=0),
 submitted_by uuid not null references auth.users,submitted_at timestamptz not null default now(),
 verified_by uuid references auth.users,verified_at timestamptz,verification_reference text,
 unique(institution_id,month));
alter table app.fine_months enable row level security;
revoke all on app.fine_months from public,anon,authenticated;

-- Quotes are read-only. The rate/calendar remain the loan's existing policy.
create function app.loan_fine_quote(l app.loans) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('loan_id',l.id,'patron_id',l.patron_id,'returned',l.returned,'due',l.due,
 'title',coalesce(l.issue_title,t.title),'accession',coalesce(l.issue_accession,c.accession),'patron_name',p.name,'patron_code',p.code,
 'fine_id',f.id,'amount',greatest(coalesce(f.amount,0),app.fine_for(l.institution_id,l.due,coalesce(l.returned,app.today()),l.policy)),
 'paid',coalesce(f.paid,0),'waived',coalesce(f.waived,0),
 'balance',greatest(coalesce(f.amount,0),app.fine_for(l.institution_id,l.due,coalesce(l.returned,app.today()),l.policy))-coalesce(f.paid,0)-coalesce(f.waived,0),'as_of',app.today())
 from app.patrons p join app.copies c on c.id=l.copy_id join app.titles t on t.id=c.title_id
 left join app.fines f on f.loan_id=l.id where p.id=l.patron_id;
$$;
revoke all on function app.loan_fine_quote(app.loans) from public,anon,authenticated;

create function public.library_fine_quote(i text,loan_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare l app.loans;begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);
 select * into l from app.loans where id=loan_id and institution_id=i;
 if not found then raise exception 'Loan not found';end if;
 if app.role_for(i)='patron' and not exists(select 1 from app.memberships where institution_id=i and user_id=auth.uid() and patron_id=l.patron_id) then raise exception 'Access denied';end if;
 return app.loan_fine_quote(l);
end$$;
revoke all on function public.library_fine_quote(text,uuid) from public,anon;
grant execute on function public.library_fine_quote(text,uuid) to authenticated;

create function public.library_fines_due(i text,after_id uuid default null,page_size integer default 100,q text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare own uuid;rows_data jsonb;total bigint;balance numeric;begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);
 if page_size is null or page_size not between 1 and 500 or length(coalesce(q,''))>200 then raise exception 'Invalid fine page';end if;
 if app.role_for(i)='patron' then select patron_id into own from app.memberships where user_id=auth.uid() and institution_id=i;end if;
 with quotes as materialized(select l.id,app.loan_fine_quote(l) r from app.loans l where institution_id=i and returned is null
  and (app.role_for(i)<>'patron' or l.patron_id=own)),
 filtered as(select * from quotes where (r->>'balance')::numeric>0 and (coalesce(q,'')='' or concat_ws(' ',r->>'patron_name',r->>'patron_code',r->>'title',r->>'accession') ilike '%'||q||'%')),
 paged as(select * from filtered where after_id is null or id>after_id order by id limit page_size)
 select (select coalesce(jsonb_agg(r order by id),'[]') from paged),count(*),coalesce(sum((r->>'balance')::numeric),0) into rows_data,total,balance from filtered;
 return jsonb_build_object('rows',rows_data,'total',total,'balance',balance,'next_id',case when jsonb_array_length(rows_data)=page_size then rows_data->-1->>'loan_id' else null end);
end$$;
revoke all on function public.library_fines_due(text,uuid,integer,text) from public,anon;
grant execute on function public.library_fines_due(text,uuid,integer,text) to authenticated;

create function app.fine_month_details(i text,m date) returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'receipt','F-'||x.id,'patron_id',p.id,'patron_name',p.name,'patron_code',p.code,
 'collected_on',x.collected_on,'amount',x.amount,'payment_method',x.payment_method,'actor',x.actor,'reference',x.reason) order by x.collected_on,x.id),'[]')
 from app.payments x join app.fines f on f.id=x.fine_id join app.patrons p on p.id=f.patron_id
 where x.institution_id=i and x.kind='payment' and x.collected_on>=m and x.collected_on<(m+interval '1 month')::date;
$$;
revoke all on function app.fine_month_details(text,date) from public,anon,authenticated;

create function public.library_fine_month(i text,month date,page_start integer default 0,page_size integer default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare m date:=date_trunc('month',month)::date;s app.fine_months;details jsonb;rows_data jsonb;total numeric;settled numeric;begin
 perform app.require_role(i,array['admin','librarian','accountant','auditor']);
 if m is null or m<'1900-01-01'::date or m>app.today() or page_start is null or page_start<0 or page_size is null or page_size not between 1 and 500 then raise exception 'Invalid month page';end if;
 select * into s from app.fine_months where institution_id=i and fine_months.month=m;
 details:=coalesce(s.details,app.fine_month_details(i,m));
 select coalesce(sum((value->>'amount')::numeric),0) into total from jsonb_array_elements(details);
 select coalesce(sum((x.value->>'amount')::numeric),0) into settled from jsonb_array_elements(details) x
 where exists(select 1 from app.fine_deposit_items di where di.payment_id=(x.value->>'id')::uuid);
 select coalesce(jsonb_agg(value order by ord),'[]') into rows_data from jsonb_array_elements(details) with ordinality as x(value,ord) where ord>page_start and ord<=page_start+page_size;
 return jsonb_build_object('month',m,'rows',rows_data,'count',jsonb_array_length(details),'total',total,'deposited',settled,'pending',total-settled,
 'status',case when s.verified_at is not null then 'verified' when s.id is not null then 'submitted' else 'draft' end,
 'submitted_by',s.submitted_by,'submitted_at',s.submitted_at,'verified_by',s.verified_by,'verified_at',s.verified_at,'verification_reference',s.verification_reference,
 'next_start',case when page_start+page_size<jsonb_array_length(details) then page_start+page_size else null end,
 'can_submit',app.today()>=(m+interval '1 month'-interval '1 day')::date and s.id is null);
end$$;
revoke all on function public.library_fine_month(text,date,integer,integer) from public,anon;
grant execute on function public.library_fine_month(text,date,integer,integer) to authenticated;

alter function public.library_action(text,text,jsonb) rename to library_action_pre_monthly;
alter function public.library_action_pre_monthly(text,text,jsonb) set schema app;
revoke all on function app.library_action_pre_monthly(text,text,jsonb) from public,anon,authenticated;
create function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare l app.loans;f app.fines;quote jsonb;amt numeric;fid uuid;result jsonb;pay app.payments;m date;details jsonb;total numeric;s app.fine_months;ids jsonb;dep jsonb;begin
 if action not in ('return','collect_loan_fine','pay','waive','fine_deposit','fine_month_submit','fine_month_verify') then return app.library_action_pre_monthly(i,action,p);end if;
 if action='return' then perform app.require_role(i,array['admin','librarian','assistant']);
 elsif action in ('collect_loan_fine','pay','fine_month_submit') then perform app.require_role(i,array['admin','librarian']);
 elsif action in ('fine_month_verify','fine_deposit') then perform app.require_role(i,array['admin','accountant']);
 else perform app.require_role(i,array['admin','librarian','accountant']);end if;
 -- Same lock order as collection/deposit registration; statements cannot race a payment.
 perform 1 from app.institutions where id=i for update;
 if action in ('return','collect_loan_fine') then
  select * into l from app.loans where id=(p->>'id')::uuid and institution_id=i for update;
  if not found then raise exception 'Loan not found; return books to their issuing library';end if;
  if action='collect_loan_fine' then
   select * into pay from app.payments where institution_id=i and request_key=nullif(p->>'request_key','')::uuid;
   if found then
    if pay.fine_id not in (select id from app.fines where loan_id=l.id) then raise exception 'Receipt belongs to another loan';end if;
    return jsonb_build_object('id',pay.id,'receipt','F-'||pay.id,'replayed',true,'collected_on',pay.collected_on,'actor',pay.actor,'amount',pay.amount);
   end if;
  end if;
  if l.returned is not null then raise exception 'Loan already returned';end if;
  if coalesce(nullif(p->>'library_code',''),i)<>i then raise exception 'Return library code must match the issuing library';end if;
  quote:=app.loan_fine_quote(l);amt:=(quote->>'amount')::numeric;
  if action='return' then
   if (quote->>'balance')::numeric>0 then raise exception 'Collect the outstanding fine of INR % before returning this book',quote->>'balance';end if;
   perform 1 from app.titles where id=(select title_id from app.copies where id=l.copy_id) for update;
   update app.loans set returned=app.today() where id=l.id;
   update app.copies set status='available' where id=l.copy_id;
   insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),'return',jsonb_build_object('id',l.id,'fine',amt,'paid',quote->'paid'));
   return jsonb_build_object('fine',amt,'balance',0);
  end if;
  if (quote->>'balance')::numeric<=0 then raise exception 'No fine is payable';end if;
  insert into app.fines(institution_id,patron_id,loan_id,amount) values(i,l.patron_id,l.id,amt)
   on conflict(loan_id) do update set amount=greatest(app.fines.amount,excluded.amount) returning id into fid;
  result:=public.library_action(i,'pay',p||jsonb_build_object('id',fid,'collected_on',app.today()));
  return result||jsonb_build_object('collected_on',app.today(),'actor',auth.uid(),'amount',(p->>'amount')::numeric);
 elsif action in ('pay','waive') then
  select * into f from app.fines where institution_id=i and id=(p->>'id')::uuid for update;
  if not found then raise exception 'Fine not found';end if;
  if action='pay' then
   select * into pay from app.payments where institution_id=i and request_key=nullif(p->>'request_key','')::uuid;
   if found then
    if pay.fine_id<>f.id then raise exception 'Receipt belongs to another fine';end if;
    return jsonb_build_object('id',pay.id,'receipt','F-'||pay.id,'replayed',true);
   end if;
  end if;
  select * into l from app.loans where id=f.loan_id;
  if l.returned is null then
   if action='waive' then raise exception 'Collect the fine before return; active-loan fines cannot be waived';end if;
   perform app.require_role(i,array['admin','librarian']);
   quote:=app.loan_fine_quote(l);
   update app.fines set amount=(quote->>'amount')::numeric where id=f.id;
   if coalesce(nullif(p->>'collected_on','')::date,app.today())<>app.today() then raise exception 'Collect an active-loan fine on today''s date';end if;
  end if;
  if action='pay' and exists(select 1 from app.fine_months where institution_id=i and month=date_trunc('month',coalesce(nullif(p->>'collected_on','')::date,app.today()))::date) then raise exception 'This collection month is submitted; backdated payments are locked';end if;
  return app.library_action_pre_monthly(i,action,p);
 elsif action='fine_deposit' then
  if exists(select 1 from app.payments x where id in(select value::uuid from jsonb_array_elements_text(p->'payment_ids')) and institution_id=i
    and (app.today()<(date_trunc('month',collected_on)+interval '1 month'-interval '1 day')::date or not exists(select 1 from app.fine_months fm where fm.institution_id=i and fm.month=date_trunc('month',x.collected_on)::date))) then raise exception 'Submit the month-end statement before depositing its collections';end if;
  return app.library_action_pre_monthly(i,action,p);
 else
  m:=date_trunc('month',nullif(p->>'month','')::date)::date;
  if m is null or m<'1900-01-01'::date or app.today()<(m+interval '1 month'-interval '1 day')::date then raise exception 'Submit or verify only at month-end or after month-end';end if;
  select * into s from app.fine_months where institution_id=i and month=m for update;
  if action='fine_month_submit' then
   if s.id is not null then return jsonb_build_object('id',s.id,'replayed',true);end if;
   details:=app.fine_month_details(i,m);select coalesce(sum((value->>'amount')::numeric),0) into total from jsonb_array_elements(details);
   insert into app.fine_months(institution_id,month,details,total,submitted_by) values(i,m,details,total,auth.uid()) returning * into s;
  else
   if s.id is null then raise exception 'Librarian must submit this month first';end if;
   if s.verified_at is not null then return jsonb_build_object('id',s.id,'replayed',true);end if;
   if length(btrim(coalesce(p->>'reference','')))=0 then raise exception 'Accounts acknowledgement or bank reference required';end if;
   select coalesce(jsonb_agg(value->>'id'),'[]') into ids from jsonb_array_elements(s.details) x where not exists(select 1 from app.fine_deposit_items d where d.payment_id=(x.value->>'id')::uuid);
   -- One consolidated handover settles every remaining receipt from the statement.
   if jsonb_array_length(ids)>0 then
    insert into app.fine_deposits(institution_id,deposited_on,reference,destination,amount,actor,request_key)
     select i,app.today(),btrim(p->>'reference'),p->>'destination',sum((value->>'amount')::numeric),auth.uid(),s.id
     from jsonb_array_elements(s.details) x where (value->>'id') in(select jsonb_array_elements_text(ids)) returning to_jsonb(app.fine_deposits.*) into dep;
    insert into app.fine_deposit_items(payment_id,deposit_id) select value::uuid,(dep->>'id')::uuid from jsonb_array_elements_text(ids);
   end if;
   update app.fine_months set verified_by=auth.uid(),verified_at=now(),verification_reference=btrim(p->>'reference') where id=s.id returning * into s;
  end if;
  insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,jsonb_build_object('id',s.id,'month',m,'total',s.total));
  return jsonb_build_object('id',s.id,'total',s.total);
 end if;
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;

alter function public.library_circulation_page(text,text,integer,text,date,date,text,text) rename to library_circulation_pre_fines;
alter function public.library_circulation_pre_fines(text,text,integer,text,date,date,text,text) set schema app;
revoke all on function app.library_circulation_pre_fines(text,text,integer,text,date,date,text,text) from public,anon,authenticated;
create function public.library_circulation_page(i text,after_id text default null,page_size integer default 50,q text default '',from_day date default null,to_day date default null,date_field text default 'issued',loan_status text default 'all') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;rows_data jsonb;begin
 result:=app.library_circulation_pre_fines(i,after_id,page_size,q,from_day,to_day,date_field,loan_status);
 select coalesce(jsonb_agg(x.value||jsonb_build_object('_fine',quote->'amount','_fine_paid',quote->'paid','_fine_balance',quote->'balance') order by x.ord),'[]') into rows_data
 from jsonb_array_elements(result->'rows') with ordinality x(value,ord) join app.loans l on l.id=(x.value->>'id')::uuid cross join lateral(select app.loan_fine_quote(l) quote) f;
 return result||jsonb_build_object('rows',rows_data);
end$$;
revoke all on function public.library_circulation_page(text,text,integer,text,date,date,text,text) from public,anon;
grant execute on function public.library_circulation_page(text,text,integer,text,date,date,text,text) to authenticated;

alter function public.library_workspace(text) rename to library_workspace_pre_accrued;
alter function public.library_workspace_pre_accrued(text) set schema app;
revoke all on function app.library_workspace_pre_accrued(text) from public,anon,authenticated;
create function public.library_workspace(i text) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;own uuid;total numeric;begin
 result:=app.library_workspace_pre_accrued(i);
 if app.role_for(i)='patron' then select patron_id into own from app.memberships where user_id=auth.uid() and institution_id=i;end if;
 select coalesce(sum(balance),0) into total from (
  select (app.loan_fine_quote(l)->>'balance')::numeric balance from app.loans l where l.institution_id=i and l.returned is null and (app.role_for(i)<>'patron' or l.patron_id=own)
  union all select f.amount-f.paid-f.waived from app.fines f join app.loans l on l.id=f.loan_id where f.institution_id=i and l.returned is not null and (app.role_for(i)<>'patron' or f.patron_id=own)
 ) b;
 return jsonb_set(result,'{counts,fine_balance}',to_jsonb(total));
end$$;
revoke all on function public.library_workspace(text) from public,anon;
grant execute on function public.library_workspace(text) to authenticated;
