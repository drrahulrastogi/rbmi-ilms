-- Resolve identifiers without changing stored accession/barcode spelling.
alter function app.library_action_core(text,text,jsonb) rename to library_action_before_casefold;
create function app.library_action_core(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare matches integer;canonical text;identifier text;begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);
 if action in ('issue','stock_scan') then
  identifier:=lower(btrim(coalesce(p->>'barcode','')));
  if identifier='' then raise exception 'Enter a barcode or accession number';end if;
  select count(*),min(barcode) into matches,canonical from app.copies
   where institution_id=i and (lower(btrim(barcode))=identifier or lower(btrim(accession))=identifier);
  if matches=0 then raise exception 'No matching copy in this library';end if;
  if matches>1 then
   select barcode into canonical from app.copies where institution_id=i and id=(p->>'copy_id')::uuid
    and (lower(btrim(barcode))=identifier or lower(btrim(accession))=identifier);
   if canonical is null then raise exception 'Identifier matches multiple copies; select a specific copy from book search';end if;
  end if;
  p:=p||jsonb_build_object('barcode',canonical);
 end if;
 return app.library_action_before_casefold(i,action,p);
end$$;
revoke all on function app.library_action_core(text,text,jsonb),app.library_action_before_casefold(text,text,jsonb) from public,anon,authenticated;

-- Membership pages join names on the server, independently of the first 200 patrons.
create or replace function public.library_records_page(i text,kind text,after_id text default null,page_size integer default 200,q text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;rows jsonb;begin
 perform app.read_budget('records');result:=app.records_page(i,kind,after_id,page_size,q);
 if kind='memberships' then
  select coalesce(jsonb_agg(e.value||jsonb_build_object('_patron_name',p.name,'_patron_code',p.code) order by e.ordinality),'[]'::jsonb)
   into rows from jsonb_array_elements(result->'rows') with ordinality e(value,ordinality)
   left join app.patrons p on p.id=(e.value->>'patron_id')::uuid and p.institution_id=i;
  result:=result||jsonb_build_object('rows',rows);
 end if;
 return result;
end$$;

create function public.library_circulation_page(i text,after_id text default null,page_size integer default 50,q text default '',from_day date default null,to_day date default null,date_field text default 'issued',loan_status text default 'all') returns jsonb language plpgsql security definer set search_path='' as $$
declare r text;own uuid;rows jsonb;total bigint;begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);perform app.read_budget('records');
 r:=app.role_for(i);select patron_id into own from app.memberships where user_id=auth.uid() and institution_id=i;
 if page_size is null or page_size<1 or page_size>1000 or length(coalesce(q,''))>200
  or date_field is null or date_field not in ('issued','due','returned') or loan_status is null or loan_status not in ('all','active','returned')
  or (from_day is not null and to_day is not null and from_day>to_day) then raise exception 'Invalid circulation filters';end if;
 with filtered as materialized (
  select l.id,to_jsonb(l)||jsonb_build_object('_title',coalesce(nullif(l.issue_title,''),t.title),'_barcode',coalesce(nullif(l.issue_barcode,''),c.barcode),
   '_accession',coalesce(nullif(l.issue_accession,''),c.accession),'_patron_name',p.name,'_patron_code',p.code,
   '_fine',(select coalesce(sum(f.amount),0) from app.fines f where f.loan_id=l.id and f.institution_id=i)) as record
  from app.loans l left join app.copies c on c.id=l.copy_id and c.institution_id=i
   left join app.titles t on t.id=c.title_id and t.institution_id=i left join app.patrons p on p.id=l.patron_id and p.institution_id=i
  where l.institution_id=i and (r<>'patron' or l.patron_id=own)
   and (loan_status='all' or loan_status='active' and l.returned is null or loan_status='returned' and l.returned is not null)
   and (from_day is null or (case date_field when 'due' then l.due when 'returned' then l.returned else l.issued end)>=from_day)
   and (to_day is null or (case date_field when 'due' then l.due when 'returned' then l.returned else l.issued end)<=to_day)
   and (coalesce(btrim(q),'')='' or strpos(lower(concat_ws(' ',l.issue_title,t.title,l.issue_barcode,c.barcode,l.issue_accession,c.accession,p.name,p.code)),lower(btrim(q)))>0)
 ), page as (select * from filtered where after_id is null or id>after_id::uuid order by id limit page_size)
 select (select count(*) from filtered),coalesce(jsonb_agg(record order by id),'[]'::jsonb) into total,rows from page;
 return jsonb_build_object('rows',rows,'total',total,'next_id',case when jsonb_array_length(rows)=page_size then rows->-1->>'id' else null end);
end$$;
revoke all on function public.library_circulation_page(text,text,integer,text,date,date,text,text) from public,anon;
grant execute on function public.library_circulation_page(text,text,integer,text,date,date,text,text) to authenticated;

-- Alerts are generated from current records, so returns/payments clear them automatically.
create function public.library_notifications(i text) returns jsonb language plpgsql security definer set search_path='' as $$
declare own uuid;current_day date:=app.today();begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);
 select m.patron_id into own from app.memberships m join app.patrons p on p.id=m.patron_id and p.institution_id=i
  where m.user_id=auth.uid() and m.institution_id=i and p.active and (p.expires is null or p.expires>=current_day);
 if own is null then return '[]'::jsonb;end if;
 return (select coalesce(jsonb_agg(n.record order by n.priority,n.key),'[]'::jsonb) from (
  select 1 priority,'availability' key,jsonb_build_object('id','availability:'||current_day,'type','unavailable','title','Librarian unavailable today',
   'message','The librarian is unavailable on '||current_day||'. This day is excluded from overdue fine calculations. '||a.reason) record
   from app.library_availability a where a.institution_id=i and a.day=current_day and not a.available
  union all
  select 2,l.id::text,jsonb_build_object('id','due:'||l.id||':'||l.due,'type','due_soon','title',case when l.due=current_day then 'Book due today' else 'Book due soon' end,
   'message',coalesce(nullif(l.issue_title,''),t.title,'Borrowed book')||' (accession '||coalesce(nullif(l.issue_accession,''),c.accession,'unavailable')||') is due on '||l.due||'.','due',l.due)
   from app.loans l left join app.copies c on c.id=l.copy_id left join app.titles t on t.id=c.title_id
   where l.institution_id=i and l.patron_id=own and l.returned is null and l.due between current_day and current_day+3
  union all
  select 3,f.id::text,jsonb_build_object('id','fine:'||f.id,'type','fine_due','title','Unpaid fine',
   'message','An assessed fine balance of INR '||to_char(f.amount-f.paid-f.waived,'FM999999990.00')||' remains unpaid. Please contact your library desk.','amount',f.amount-f.paid-f.waived)
   from app.fines f where f.institution_id=i and f.patron_id=own and f.amount-f.paid-f.waived>0
 ) n);
end$$;
revoke all on function public.library_notifications(text) from public,anon;
grant execute on function public.library_notifications(text) to authenticated;

-- The authenticated account endpoint calls this with its server-only service client.
create function public.library_account_search(i text,q text default '',after_id text default null,page_size integer default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb;begin
 if page_size is null or page_size<1 or page_size>200 or length(coalesce(q,''))>200 or not exists(select 1 from app.institutions where id=i and active) then raise exception 'Invalid account search';end if;
 with users as (
  select u.id,to_jsonb(u)->>'email' email,coalesce(nullif(p.name,''),nullif(s.display_name,''),nullif(to_jsonb(u)->'raw_user_meta_data'->>'full_name',''),to_jsonb(u)->>'email') name
  from auth.users u join app.memberships m on m.user_id=u.id and m.institution_id=i
   left join app.patrons p on p.id=m.patron_id and p.institution_id=i left join app.library_staff s on s.user_id=u.id and s.institution_id=i
 ), page as (select * from users where (after_id is null or id>after_id::uuid)
   and (coalesce(btrim(q),'')='' or strpos(lower(concat_ws(' ',name,email)),lower(btrim(q)))>0) order by id limit page_size)
 select coalesce(jsonb_agg(to_jsonb(page) order by id),'[]'::jsonb) into rows from page;
 return jsonb_build_object('users',rows,'nextCursor',case when jsonb_array_length(rows)=page_size then rows->-1->>'id' else null end);
end$$;
revoke all on function public.library_account_search(text,text,text,integer) from public,anon,authenticated;
grant execute on function public.library_account_search(text,text,text,integer) to service_role;
