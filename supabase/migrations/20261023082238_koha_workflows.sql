-- Additional workflows derived from the supplied Koha training inventory.
create table app.authorities(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,kind text not null check(kind in ('personal','corporate','subject','geographic','genre')),heading text not null check(length(trim(heading))>0),variants text not null default '',notes text not null default '',unique(institution_id,kind,heading));
create table app.title_authorities(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,title_id uuid not null references app.titles,authority_id uuid not null references app.authorities,unique(title_id,authority_id));
create table app.reading_lists(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,name text not null check(length(trim(name))>0),owner uuid not null references auth.users,visibility text not null check(visibility in ('private','public')),created_at timestamptz not null default now());
create table app.list_entries(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,list_id uuid not null references app.reading_lists,title_id uuid not null references app.titles,unique(list_id,title_id));
create table app.budgets(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,name text not null check(length(trim(name))>0),amount numeric(12,2) not null check(amount>0),starts date not null,ends date not null,check(ends>=starts));
create table app.funds(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,budget_id uuid not null references app.budgets,code text not null,name text not null,amount numeric(12,2) not null check(amount>0),unique(institution_id,code));
create table app.baskets(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,vendor_id uuid not null references app.vendors,name text not null check(length(trim(name))>0));
alter table app.acquisitions add column fund_id uuid references app.funds,add column basket_id uuid references app.baskets;
create table app.subscriptions(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,title text not null check(length(trim(title))>0),issn text not null default '',vendor_id uuid references app.vendors,frequency text not null check(frequency in ('weekly','monthly','quarterly','yearly')),first_issue date not null,issue_count integer not null check(issue_count between 1 and 120),notes text not null default '',created_at timestamptz not null default now());
create table app.serial_issues(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,subscription_id uuid not null references app.subscriptions,number integer not null,due date not null,status text not null default 'expected' check(status in ('expected','arrived','late','missing')),received date,notes text not null default '',unique(subscription_id,number));
create table app.saved_reports(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,name text not null check(length(trim(name))>0),dataset text not null check(dataset in ('loans','copies','patrons','fines','acquisitions','serial_issues')),definition jsonb not null default '{}',created_by uuid references auth.users,created_at timestamptz not null default now());
create index serial_due_idx on app.serial_issues(institution_id,due,status);
create index list_owner_idx on app.reading_lists(institution_id,owner);
alter function public.library_action(text,text,jsonb) rename to library_action_v2;
alter function public.library_action_v2(text,text,jsonb) set schema app;
alter function public.library_snapshot(text) rename to library_snapshot_v2;
alter function public.library_snapshot_v2(text) set schema app;
create function public.library_snapshot(i text) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 result:=app.library_snapshot_v2(i);
 return result||jsonb_build_object('authorities',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from app.authorities a where institution_id=i),'title_authorities',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from app.title_authorities a where institution_id=i),'reading_lists',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from app.reading_lists a where institution_id=i and (visibility='public' or owner=auth.uid())), 'list_entries',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from app.list_entries e join app.reading_lists l on l.id=e.list_id where e.institution_id=i and (l.visibility='public' or l.owner=auth.uid())), 'subscriptions',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from app.subscriptions a where institution_id=i),'serial_issues',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from app.serial_issues a where institution_id=i),
 'budgets',case when app.role_for(i)='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(a)),'[]') from app.budgets a where institution_id=i) end,'funds',case when app.role_for(i)='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(a)),'[]') from app.funds a where institution_id=i) end,'baskets',case when app.role_for(i)='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(a)),'[]') from app.baskets a where institution_id=i) end,'saved_reports',case when app.role_for(i)='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(a)),'[]') from app.saved_reports a where institution_id=i) end);
end$$;
create function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare v uuid;tid uuid;rowdata jsonb;b app.budgets;f app.funds;l app.reading_lists;sub app.subscriptions;n integer;step interval;result jsonb;begin
 if action not in ('authority','link_authority','reading_list','list_add','list_remove','budget','fund','basket','subscription','serial_status','save_report','order','marc_import') then return app.library_action_v2(i,action,p);end if;
 if action in ('reading_list','list_add','list_remove') then perform app.require_role(i,array['admin','librarian','assistant','patron']);else perform app.require_role(i,array['admin','librarian']);end if;
 if action='marc_import' then
 if jsonb_typeof(p->'rows')<>'array' or jsonb_array_length(p->'rows') not between 1 and 1000 then raise exception 'MARC import requires 1 to 1000 copies';end if;
 for rowdata in select value from jsonb_array_elements(p->'rows') loop
 if coalesce(nullif(rowdata->>'library_code',''),i) not in (i,case when i='RBCET' then 'RBMI' else i end) then raise exception 'MARC copy library does not match selected library';end if;
 tid:=null;
 select id into tid from app.titles where institution_id=i and ((isbn<>'' and isbn=rowdata->>'isbn') or (coalesce(rowdata->>'isbn','')='' and title=rowdata->>'title' and author=rowdata->>'author')) order by id limit 1;
 if tid is null then result:=app.library_action_v2(i,'title',rowdata);tid:=(result->>'id')::uuid;end if;
 perform app.library_action_v2(i,'copy',rowdata||jsonb_build_object('title_id',tid));
 end loop;
 elsif action='authority' then
 insert into app.authorities(institution_id,kind,heading,variants,notes) values(i,p->>'kind',p->>'heading',coalesce(p->>'variants',''),coalesce(p->>'notes','')) on conflict(institution_id,kind,heading) do update set variants=excluded.variants,notes=excluded.notes returning id into v;
 elsif action='link_authority' then
 if not exists(select 1 from app.titles where id=(p->>'title_id')::uuid and institution_id=i) or not exists(select 1 from app.authorities where id=(p->>'authority_id')::uuid and institution_id=i) then raise exception 'Title/authority must belong to this library';end if;
 insert into app.title_authorities(institution_id,title_id,authority_id) values(i,(p->>'title_id')::uuid,(p->>'authority_id')::uuid) on conflict do nothing;
 elsif action='reading_list' then
 insert into app.reading_lists(institution_id,name,owner,visibility) values(i,p->>'name',auth.uid(),p->>'visibility') returning id into v;
 elsif action in ('list_add','list_remove') then
 select * into l from app.reading_lists where id=(p->>'list_id')::uuid and institution_id=i for update;
 if l.id is null or l.owner<>auth.uid() then raise exception 'Only the list owner may change its contents';end if;
 if not exists(select 1 from app.titles where id=(p->>'title_id')::uuid and institution_id=i) then raise exception 'Title belongs to another library';end if;
 if action='list_add' then insert into app.list_entries(institution_id,list_id,title_id) values(i,l.id,(p->>'title_id')::uuid) on conflict do nothing;else delete from app.list_entries where list_id=l.id and title_id=(p->>'title_id')::uuid;end if;
 elsif action='budget' then
 insert into app.budgets(institution_id,name,amount,starts,ends) values(i,p->>'name',(p->>'amount')::numeric,(p->>'starts')::date,(p->>'ends')::date) returning id into v;
 elsif action='fund' then
 select * into b from app.budgets where id=(p->>'budget_id')::uuid and institution_id=i for update;if b.id is null then raise exception 'Budget not found';end if;
 if coalesce((select sum(amount) from app.funds where budget_id=b.id),0)+(p->>'amount')::numeric>b.amount then raise exception 'Fund allocations exceed budget';end if;
 insert into app.funds(institution_id,budget_id,code,name,amount) values(i,b.id,p->>'code',p->>'name',(p->>'amount')::numeric) returning id into v;
 elsif action='basket' then
 if not exists(select 1 from app.vendors where id=(p->>'vendor_id')::uuid and institution_id=i) then raise exception 'Vendor not found';end if;
 insert into app.baskets(institution_id,vendor_id,name) values(i,(p->>'vendor_id')::uuid,p->>'name') returning id into v;
 elsif action='order' then
 if nullif(p->>'fund_id','') is not null then
 select * into f from app.funds where id=(p->>'fund_id')::uuid and institution_id=i for update;if f.id is null then raise exception 'Fund not found';end if;
 if not exists(select 1 from app.budgets where id=f.budget_id and app.today() between starts and ends) then raise exception 'Budget period is not active';end if;
 if coalesce((select sum(quantity*unit_price) from app.acquisitions where fund_id=f.id and status<>'cancelled'),0)+(p->>'quantity')::integer*(p->>'unit_price')::numeric>f.amount then raise exception 'Order exceeds available fund';end if;
 end if;
 if nullif(p->>'basket_id','') is not null and not exists(select 1 from app.baskets where id=(p->>'basket_id')::uuid and institution_id=i and vendor_id=(p->>'vendor_id')::uuid) then raise exception 'Basket/vendor mismatch';end if;
 -- Serialize per-library order capture; core order has no generated ID in its response.
 perform 1 from app.institutions where id=i for update;
 result:=app.library_action_v2(i,action,p);
 select id into v from app.acquisitions where institution_id=i and vendor_id=(p->>'vendor_id')::uuid and title_id=(p->>'title_id')::uuid and invoice=p->>'invoice';
 update app.acquisitions set fund_id=nullif(p->>'fund_id','')::uuid,basket_id=nullif(p->>'basket_id','')::uuid where id=v;
 return result||jsonb_build_object('id',v);
 elsif action='subscription' then
 if nullif(p->>'vendor_id','') is not null and not exists(select 1 from app.vendors where id=(p->>'vendor_id')::uuid and institution_id=i) then raise exception 'Vendor not found';end if;
 insert into app.subscriptions(institution_id,title,issn,vendor_id,frequency,first_issue,issue_count,notes) values(i,p->>'title',coalesce(p->>'issn',''),nullif(p->>'vendor_id','')::uuid,p->>'frequency',(p->>'first_issue')::date,(p->>'issue_count')::integer,coalesce(p->>'notes','')) returning * into sub;v:=sub.id;
 step:=case sub.frequency when 'weekly' then interval '7 days' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end;
 for n in 1..sub.issue_count loop insert into app.serial_issues(institution_id,subscription_id,number,due) values(i,sub.id,n,(sub.first_issue+(n-1)*step)::date);end loop;
 elsif action='serial_status' then
 update app.serial_issues set status=p->>'status',received=case when p->>'status'='arrived' then app.today() else null end,notes=coalesce(p->>'notes','') where id=(p->>'id')::uuid and institution_id=i returning id into v;if v is null then raise exception 'Serial issue not found';end if;
 elsif action='save_report' then
 insert into app.saved_reports(institution_id,name,dataset,definition,created_by) values(i,p->>'name',p->>'dataset',jsonb_build_object('start',nullif(p->>'start','')::date,'end',nullif(p->>'end','')::date),auth.uid()) returning id into v;
 end if;
 insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,p);return jsonb_build_object('id',v);
end$$;
create function public.library_report(i text,report_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare r app.saved_reports;result jsonb;datecol text;begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor']);select * into r from app.saved_reports where id=report_id and institution_id=i;if r.id is null then raise exception 'Report not found';end if;
 datecol:=case r.dataset when 'loans' then 'issued' when 'serial_issues' then 'due' when 'acquisitions' then 'ordered_at' else 'created_at' end;
 if r.dataset in ('copies','patrons','fines') then
 execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]'') from app.%I t where institution_id=$1',r.dataset) into result using i;
 else execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]'') from app.%I t where institution_id=$1 and ($2::date is null or %I::date >= $2) and ($3::date is null or %I::date <= $3)',r.dataset,datecol,datecol) into result using i,(r.definition->>'start')::date,(r.definition->>'end')::date;end if;
 return result;end$$;
do $$declare t text;begin foreach t in array array['authorities','title_authorities','reading_lists','list_entries','budgets','funds','baskets','subscriptions','serial_issues','saved_reports'] loop execute format('alter table app.%I enable row level security',t);end loop;end$$;
revoke all on all tables in schema app from public,anon,authenticated;
revoke all on all functions in schema app from public,anon,authenticated;
revoke all on function public.library_bootstrap(),public.library_snapshot(text),public.library_action(text,text,jsonb),public.library_report(text,uuid) from public,anon;
grant execute on function public.library_bootstrap(),public.library_snapshot(text),public.library_action(text,text,jsonb),public.library_report(text,uuid) to authenticated;

-- Public OPAC exposes catalogue metadata and copy availability only, never patrons/accounts.
create function public.library_catalogue(library_code text) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from app.institutions where id=library_code and active) then raise exception 'Library not found';end if;
 return jsonb_build_object('libraries',(select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name) order by i.id) from app.institutions i where active),'titles',(select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'title',t.title,'author',t.author,'isbn',t.isbn,'subject',t.subject,'publisher',t.publisher,'year',t.year,'classification',t.classification)),'[]') from app.titles t where institution_id=library_code),'copies',(select coalesce(jsonb_agg(jsonb_build_object('title_id',c.title_id,'shelf',c.shelf,'status',c.status,'accession',c.accession)),'[]') from app.copies c where institution_id=library_code));
 end$$;
revoke all on function public.library_catalogue(text) from public;
grant execute on function public.library_catalogue(text) to anon,authenticated;
