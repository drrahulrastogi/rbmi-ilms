-- Shared quotas; no raw IP addresses, credentials or request bodies are stored.
create table app.request_buckets(bucket text primary key,hits integer not null,expires_at timestamptz not null);
create index request_buckets_expiry on app.request_buckets(expires_at);
alter table app.request_buckets enable row level security;
revoke all on app.request_buckets from public,anon,authenticated;
create function app.take_quota(bucket_key text,quota integer,seconds integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare b app.request_buckets;begin
 delete from app.request_buckets where bucket in(select bucket from app.request_buckets where expires_at<now() limit 100);
 insert into app.request_buckets(bucket,hits,expires_at) values(bucket_key,1,now()+make_interval(secs=>seconds)) on conflict(bucket) do update set hits=case when app.request_buckets.expires_at<=now() then 1 else app.request_buckets.hits+1 end,expires_at=case when app.request_buckets.expires_at<=now() then now()+make_interval(secs=>seconds) else app.request_buckets.expires_at end returning * into b;
 return jsonb_build_object('allowed',b.hits<=quota,'remaining',greatest(0,quota-b.hits),'retry_after',greatest(1,ceil(extract(epoch from b.expires_at-now()))::integer));end$$;
create function public.library_api_quota(operation text,subject text) returns jsonb language plpgsql security definer set search_path='' as $$
declare cap integer;begin
 cap:=case operation when 'password' then 10 when 'accounts' then 30 when 'patron-logins' then 240 when 'preauth' then 120 else null end;
 if cap is null or subject is null or length(subject)>150 or length(subject)<3 then raise exception 'Invalid quota request';end if;
 return app.take_quota('api:'||operation||':'||subject,cap,60);end$$;
revoke all on function public.library_api_quota(text,text) from public,anon,authenticated;
grant execute on function public.library_api_quota(text,text) to service_role;
create function app.read_budget(kind text) returns void language plpgsql security definer set search_path='' as $$declare b jsonb;member boolean;begin
 member:=auth.uid() is not null and exists(select 1 from app.memberships where user_id=auth.uid());
 b:=app.take_quota(case when not member then 'public:catalogue' else 'read:'||auth.uid()::text end,case when not member then 600 else 2000 end,60);
 if not (b->>'allowed')::boolean then raise sqlstate 'PT429' using message='Request limit reached. Retry in one minute.';end if;end$$;

-- MFA is enforced once the owner verifies TOTP and enables it; no enrollment secrets are stored here.
create table app.admin_security(user_id uuid primary key references auth.users on delete cascade,mfa_required boolean not null default false);
alter table app.admin_security enable row level security;
revoke all on app.admin_security from public,anon,authenticated;
create function app.require_admin_factor() returns void language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from app.admin_security where user_id=auth.uid() and mfa_required) and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'aal','aal1')<>'aal2' then raise exception 'Verify your administrator second factor';end if;end$$;
create or replace function app.require_role(i text,roles text[]) returns void language plpgsql security definer set search_path='' as $$
declare setup app.account_setup;issued bigint;begin
 perform app.require_admin_factor();
 select * into setup from app.account_setup where user_id=auth.uid();
 if setup.required then raise exception 'Change your initial password before accessing library records';end if;
 if setup.token_cutoff is not null then
  issued:=coalesce((nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'iat')::bigint,0);
  if issued<=setup.token_cutoff then raise exception 'Sign in again after changing your initial password';end if;
 end if;
 if app.role_for(i) is null or not(app.role_for(i)=any(roles)) then raise exception 'Access denied for this institution/action';end if;
end$$;
create function public.library_security_state() returns jsonb language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 return jsonb_build_object('admin',exists(select 1 from app.network_admin where user_id=auth.uid()),'mfa_required',coalesce((select mfa_required from app.admin_security where user_id=auth.uid()),false));end$$;
create function public.library_enable_admin_mfa() returns void language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from app.network_admin where user_id=auth.uid()) then raise exception 'Administrator required';end if;
 if coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'aal','aal1')<>'aal2' then raise exception 'Verify your second factor before enabling protection';end if;
 insert into app.admin_security values(auth.uid(),true) on conflict(user_id) do update set mfa_required=true;
 insert into app.audit(institution_id,actor,action,details) select institution_id,auth.uid(),'admin_mfa_enabled','{}' from app.memberships where user_id=auth.uid();end$$;
revoke all on function public.library_security_state(),public.library_enable_admin_mfa() from public,anon;
grant execute on function public.library_security_state(),public.library_enable_admin_mfa() to authenticated;

-- Invitation sessions can set the first password without knowing an initial password.
alter table app.account_setup add column method text not null default 'legacy' check(method in ('legacy','invite'));
alter table app.account_setup add column expires_at timestamptz;
create or replace function public.library_onboarding() returns jsonb language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 return coalesce((select jsonb_build_object('required',required,'method',method,'expired',required and expires_at is not null and expires_at<now()) from app.account_setup where user_id=auth.uid()),jsonb_build_object('required',false,'method','legacy','expired',false));end$$;
create function public.library_mark_invitation(target uuid) returns void language plpgsql security definer set search_path='' as $$begin
 insert into app.account_setup(user_id,method,expires_at) select target,'invite',now()+interval '24 hours' where exists(select 1 from app.memberships where user_id=target) on conflict(user_id) do update set method='invite',expires_at=now()+interval '24 hours' where app.account_setup.required;
 if not found then raise exception 'Pending setup required';end if;end$$;
revoke all on function public.library_mark_invitation(uuid) from public,anon,authenticated;
grant execute on function public.library_mark_invitation(uuid) to service_role;
create function public.library_refresh_invitation(target uuid) returns void language plpgsql security definer set search_path='' as $$begin update app.account_setup set expires_at=now()+interval '24 hours' where user_id=target and required and method='invite';end$$;
revoke all on function public.library_refresh_invitation(uuid) from public,anon,authenticated;
grant execute on function public.library_refresh_invitation(uuid) to service_role;
create or replace function public.library_login_targets(i text,codes jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform app.require_role(i,array['admin','librarian']);
 if jsonb_typeof(codes) is distinct from 'array' or jsonb_array_length(codes)>10 then raise exception 'At most ten patron codes per request';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'email',p.email,'active',p.active,'category',p.category,'institute',coalesce(p.profile->>'institute',i),'linked_user',m.user_id,'pending_invite',coalesce(s.required and s.method='invite',false))) from app.patrons p left join app.memberships m on m.institution_id=p.institution_id and m.patron_id=p.id and m.role='patron' left join app.account_setup s on s.user_id=m.user_id where p.institution_id=i and p.category in ('student','faculty') and p.code in(select jsonb_array_elements_text(codes))),'[]'::jsonb);end$$;
create function public.library_health() returns boolean language plpgsql security definer set search_path='' as $$begin
 return to_regprocedure('public.library_records_page(text,text,text,integer,text)') is not null;end$$;
revoke all on function public.library_health() from public,anon,authenticated;
grant execute on function public.library_health() to service_role;

create index patrons_library_page on app.patrons(institution_id,id);
create index loans_library_page on app.loans(institution_id,id);
create index audit_library_page on app.audit(institution_id,id);
create function app.records_page(i text,kind text,after_id text,page_size integer,q text,from_day date default null,to_day date default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare r text;own uuid;tbl text;predicate text:='';extra text:='';direction text:='asc';comparator text:='>';id_type text:='uuid';rows jsonb;total bigint;datecol text;
begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);r:=app.role_for(i);
 if kind is null or not(kind=any(array['patrons','loans','active_loans','overdue_loans','returned_loans','holds','fines','payments','audit','vendors','acquisitions','stock_sessions','stock_items','memberships','authorities','title_authorities','subscriptions','serial_issues','reading_lists','list_entries','budgets','funds','baskets','saved_reports','holidays','library_availability','policies','titles','copies'])) or page_size is null or page_size<1 or page_size>1000 or length(coalesce(q,''))>200 then raise exception 'Invalid records page request';end if;
 tbl:=case when kind in ('active_loans','returned_loans','overdue_loans') then 'loans' else kind end;
 if kind='active_loans' then predicate:=' and t.returned is null';elsif kind='overdue_loans' then predicate:=' and t.returned is null and t.due<app.today()';elsif kind='returned_loans' then predicate:=' and t.returned is not null';end if;
 select patron_id into own from app.memberships where user_id=auth.uid() and institution_id=i;
 if r='patron' then
  if kind=any(array['payments','audit','vendors','acquisitions','stock_sessions','stock_items','memberships','budgets','funds','baskets','saved_reports','library_availability']) then raise exception 'Access denied for this dataset';end if;
  if kind='patrons' then predicate:=predicate||format(' and t.id=%L::uuid',own);elsif tbl=any(array['loans','holds','fines']) then predicate:=predicate||format(' and t.patron_id=%L::uuid',own);end if;
 end if;
 if tbl='reading_lists' then predicate:=predicate||format(' and (t.visibility=''public'' or t.owner=%L::uuid)',auth.uid());end if;
 if tbl='list_entries' then predicate:=predicate||format(' and exists(select 1 from app.reading_lists l where l.id=t.list_id and (l.visibility=''public'' or l.owner=%L::uuid))',auth.uid());end if;
 if tbl='memberships' then
  select count(*) into total from app.memberships t where institution_id=i and (coalesce(q,'')='' or strpos(lower(to_jsonb(t)::text),lower(q))>0);
  select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') into rows from(select m.*,m.user_id id from app.memberships m where institution_id=i and (after_id is null or user_id>after_id::uuid) and (coalesce(q,'')='' or strpos(lower(to_jsonb(m)::text),lower(q))>0) order by user_id limit page_size) t;
  return jsonb_build_object('rows',rows,'total',total,'next_id',case when jsonb_array_length(rows)=page_size then rows->-1->>'id' else null end);
 end if;
 if tbl=any(array['policies','holidays','library_availability']) then raise exception 'Use workspace configuration for this dataset';end if;
 if tbl='audit' then direction:='desc';comparator:='<';id_type:='bigint';end if;
 if tbl='patrons' then
  extra:=', ''active_loans'',(select count(*) from app.loans l where l.patron_id=t.id and l.returned is null)';
  predicate:=predicate||' and ($3='''' or strpos(lower(concat_ws('' '',t.code,t.name,t.email,t.department)),lower($3))>0)';
 elsif tbl='loans' then
  extra:=', ''_title'',coalesce(t.issue_title,(select title from app.titles where id=(select title_id from app.copies where id=t.copy_id))), ''_barcode'',coalesce(t.issue_barcode,(select barcode from app.copies where id=t.copy_id)), ''_patron_name'',(select name from app.patrons where id=t.patron_id)';
  predicate:=predicate||' and ($3='''' or strpos(lower(concat_ws('' '',t.issue_title,t.issue_barcode,t.issue_accession,(select name from app.patrons where id=t.patron_id),t.patron_code_snapshot)),lower($3))>0)';
 elsif tbl='audit' then
  extra:=', ''_details_truncated'',octet_length(t.details::text)>4096, ''details'',case when octet_length(t.details::text)>4096 then jsonb_build_object(''summary'',''Large audit payload; open full details to read it.'') else t.details end';
  predicate:=predicate||' and ($3='''' or strpos(lower(concat_ws('' '',t.action,t.actor::text,t.details::text)),lower($3))>0)';
 else
  if tbl=any(array['holds','fines']) then extra:=', ''_patron_name'',(select name from app.patrons where id=t.patron_id), ''_patron_code'',(select code from app.patrons where id=t.patron_id)';end if;
  if tbl='stock_sessions' then extra:=', ''_scanned'',(select count(*) from app.stock_items where session_id=t.id and seen_at is not null), ''_unscanned'',(select count(*) from app.stock_items where session_id=t.id and seen_at is null and expected_status<>''loaned'')';end if;
  if tbl='stock_items' then predicate:=predicate||' and ($3='''' or t.session_id=$3::uuid)';else predicate:=predicate||' and ($3='''' or strpos(lower(to_jsonb(t)::text),lower($3))>0)';end if;
 end if;
 datecol:=case tbl when 'loans' then 'issued' when 'serial_issues' then 'due' when 'acquisitions' then 'ordered_at' else null end;
 if datecol is not null then predicate:=predicate||format(' and ($5::date is null or t.%I::date >= $5) and ($6::date is null or t.%I::date <= $6)',datecol,datecol);end if;
 execute format('select count(*) from app.%I t where institution_id=$1 %s',tbl,predicate) into total using i,after_id,coalesce(q,''),page_size,from_day,to_day;
 execute format('select coalesce(jsonb_agg(x.row order by x.id %s),''[]''::jsonb) from (select t.id,to_jsonb(t)||jsonb_build_object(''id'',t.id%s) row from app.%I t where institution_id=$1 %s and ($2 is null or t.id %s $2::%s) order by t.id %s limit $4) x',direction,extra,tbl,predicate,comparator,id_type,direction) into rows using i,after_id,coalesce(q,''),page_size,from_day,to_day;
 return jsonb_build_object('rows',rows,'total',total,'next_id',case when jsonb_array_length(rows)=page_size then rows->-1->>'id' else null end);
end$$;
create or replace function public.library_workspace(i text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r text;own uuid;k text;p jsonb;out jsonb;pages jsonb:='{}';counts jsonb:='{}';begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);r:=app.role_for(i);select patron_id into own from app.memberships where user_id=auth.uid() and institution_id=i;
 out:=jsonb_build_object('titles','[]'::jsonb,'copies','[]'::jsonb,'policies',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from app.policies t where institution_id=i),'holidays',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (select * from app.holidays where institution_id=i order by day desc limit 1000) t),'memberships',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (select * from app.memberships where institution_id=i order by user_id limit 200) t) end,'availability',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (select * from app.library_availability where institution_id=i order by day desc limit 400) t),'library',(select to_jsonb(t) from app.institutions t where id=i),'librarian',(select jsonb_build_object('user_id',user_id,'display_name',display_name) from app.library_staff where institution_id=i),'today',app.today());
 foreach k in array array['memberships','patrons','active_loans','returned_loans','holds','fines','payments','audit','vendors','acquisitions','stock_sessions','stock_items','authorities','title_authorities','subscriptions','serial_issues','reading_lists','list_entries','budgets','funds','baskets','saved_reports'] loop
  if r='patron' and k=any(array['memberships','payments','audit','vendors','acquisitions','stock_sessions','stock_items','budgets','funds','baskets','saved_reports']) then p:=jsonb_build_object('rows','[]'::jsonb,'total',0,'next_id',null);
  else p:=app.records_page(i,k,null,200,'');end if;
  out:=out||jsonb_build_object(k,p->'rows');pages:=pages||jsonb_build_object(k,p-'rows');counts:=counts||jsonb_build_object(k,p->'total');
 end loop;
 out:=out||jsonb_build_object('loans',(out->'active_loans')||(out->'returned_loans'));
 counts:=counts||jsonb_build_object('loans',((counts->>'active_loans')::bigint+(counts->>'returned_loans')::bigint),'titles',(select count(*) from app.titles where institution_id=i),'copies',(select count(*) from app.copies where institution_id=i),'available_copies',(select count(*) from app.copies where institution_id=i and status='available'),'overdue',(select count(*) from app.loans where institution_id=i and returned is null and due<app.today() and (r<>'patron' or patron_id=own)),'fine_paid',(select coalesce(sum(paid),0) from app.fines where institution_id=i and (r<>'patron' or patron_id=own)),'fine_waived',(select coalesce(sum(waived),0) from app.fines where institution_id=i and (r<>'patron' or patron_id=own)),'fine_balance',(select coalesce(sum(amount-paid-waived),0) from app.fines where institution_id=i and (r<>'patron' or patron_id=own)));
 return out||jsonb_build_object('pages',pages,'counts',counts);end$$;
create or replace function public.library_snapshot(i text) returns jsonb language plpgsql security definer set search_path='' as $$begin return public.library_workspace(i)||jsonb_build_object('titles',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (select * from app.titles where institution_id=i order by id limit 200) t),'copies',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (select * from app.copies where institution_id=i order by id limit 200) t));end$$;

create function app.catalogue_page(i text,q text,cursor uuid,page_size integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare ids uuid[];more boolean;begin
 if page_size is null or page_size<1 or page_size>2000 or length(coalesce(q,''))>200 then raise exception 'Narrow the search or use at most 2000 catalogue results';end if;
 if not exists(select 1 from app.institutions where id=i and active) then raise exception 'Library not found';end if;
 select coalesce(array_agg(id order by id),'{}') into ids from(select id from app.titles where institution_id=i and (cursor is null or id>cursor) and strpos(lower(concat_ws(' ',title,author,isbn,subject)),lower(coalesce(q,'')))>0 order by id limit least(page_size,100)+1) t;
 more:=cardinality(ids)>least(page_size,100);ids:=ids[1:least(page_size,100)];
 return jsonb_build_object('libraries',(select jsonb_agg(jsonb_build_object('id',id,'name',name) order by id) from app.institutions where active),'titles',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from app.titles t where institution_id=i and id=any(ids)),'copies',(select coalesce(jsonb_agg(jsonb_build_object('title_id',title_id,'accession',accession,'shelf',shelf,'status',status)),'[]') from(select c.*,row_number() over(partition by title_id order by id) rn from app.copies c where institution_id=i and title_id=any(ids)) t where rn<=4),'copy_counts',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from(select title_id,count(*) total,count(*) filter(where status='available') available from app.copies where institution_id=i and title_id=any(ids) group by title_id) t),'has_more',more,'next_id',case when more then ids[cardinality(ids)] else null end);
end$$;
create or replace function public.library_catalogue_search(library_code text,q text default '',max_titles integer default 40) returns jsonb language plpgsql security definer set search_path='' as $$begin perform app.read_budget('catalogue');return app.catalogue_page(library_code,q,null,max_titles);end$$;
create or replace function public.library_catalogue(library_code text) returns jsonb language plpgsql security definer set search_path='' as $$begin perform app.read_budget('catalogue');return app.catalogue_page(library_code,'',null,40);end$$;
create function public.library_public_titles_page(library_code text,q text default '',after_id uuid default null,page_size integer default 40) returns jsonb language plpgsql security definer set search_path='' as $$begin perform app.read_budget('catalogue');return app.catalogue_page(library_code,q,after_id,page_size);end$$;
create function public.library_public_copies_page(library_code text,title uuid,after_id uuid default null,page_size integer default 50) returns jsonb language plpgsql security definer set search_path='' as $$declare rows jsonb;begin
 perform app.read_budget('copies');if page_size is null or page_size<1 or page_size>100 then raise exception 'Use 1 to 100 copies per page';end if;
 if not exists(select 1 from app.institutions where id=library_code and active) or not exists(select 1 from app.titles where id=$2 and institution_id=library_code) then raise exception 'Title not found';end if;
 select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') into rows from(select id,title_id,accession,shelf,status from app.copies where institution_id=library_code and title_id=title and (after_id is null or id>after_id) order by id limit page_size) t;
 return jsonb_build_object('rows',rows,'next_id',case when jsonb_array_length(rows)=page_size then rows->-1->>'id' else null end);end$$;
revoke all on function public.library_public_titles_page(text,text,uuid,integer),public.library_public_copies_page(text,uuid,uuid,integer) from public;
grant execute on function public.library_public_titles_page(text,text,uuid,integer),public.library_public_copies_page(text,uuid,uuid,integer) to anon,authenticated;
create function public.library_records_page(i text,kind text,after_id text default null,page_size integer default 200,q text default '') returns jsonb language plpgsql security definer set search_path='' as $$begin perform app.read_budget('records');return app.records_page(i,kind,after_id,page_size,q);end$$;
revoke all on function public.library_records_page(text,text,text,integer,text) from public,anon;
grant execute on function public.library_records_page(text,text,text,integer,text) to authenticated;
create function public.library_audit_detail(i text,event_id bigint,part integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$declare payload text;begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor']);perform app.read_budget('audit');
 if part is null or part<0 or part>10000 then raise exception 'Invalid audit detail page';end if;
 select details::text into payload from app.audit where institution_id=i and id=event_id;if not found then raise exception 'Audit event not found';end if;
 return jsonb_build_object('text',substring(payload from part*16000+1 for 16000),'part',part,'parts',greatest(1,ceil(length(payload)/16000.0)::integer),'next_part',case when length(payload)>(part+1)*16000 then part+1 else null end);end$$;
revoke all on function public.library_audit_detail(text,bigint,integer) from public,anon;
grant execute on function public.library_audit_detail(text,bigint,integer) to authenticated;

create function public.library_report_page(i text,report_id uuid,after_id text default null,page_size integer default 500,q text default '') returns jsonb language plpgsql security definer set search_path='' as $$declare r app.saved_reports;begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor']);perform app.read_budget('report');
 select * into r from app.saved_reports where id=report_id and institution_id=i;if not found then raise exception 'Report not found';end if;
 return app.records_page(i,r.dataset,after_id,page_size,q,(r.definition->>'start')::date,(r.definition->>'end')::date);end$$;
revoke all on function public.library_report_page(text,uuid,text,integer,text) from public,anon;
grant execute on function public.library_report_page(text,uuid,text,integer,text) to authenticated;
create or replace function public.library_report(i text,report_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare p jsonb;begin p:=public.library_report_page(i,report_id,null,1000,'');if p->>'next_id' is not null then raise exception 'This report requires the paged report viewer';end if;return p->'rows';end$$;

-- Private helper functions are never callable directly by browser or anonymous roles.
-- Institutional serialization must not conflict with FK KEY SHARE locks held by inserts.
-- No key is changed by issue/return/availability, so NO KEY UPDATE preserves serialization.
do $$declare definition text;begin
 definition:=pg_get_functiondef('app.library_action_v2(text,text,jsonb)'::regprocedure);
 if strpos(definition,'from app.institutions where id=i for update')=0 then raise exception 'Unexpected institutional lock definition';end if;
 execute replace(definition,'from app.institutions where id=i for update','from app.institutions where id=i for no key update');
end$$;
-- Acquire the title before the patron for holds, matching issue/renew/return lock order.
-- This prevents the title/patron cycle found by the real multi-connection regression.
create or replace function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if action in ('import','patron') and (p ? 'password' or p->'profile' ? 'password' or exists(select 1 from jsonb_array_elements(case when jsonb_typeof(p->'rows')='array' then p->'rows' else '[]'::jsonb end) r where r ? 'password' or r->'profile' ? 'password')) then raise exception 'Passwords must use the account provisioning service, not patron records';end if;
 if action='hold' then
  perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);
  perform 1 from app.titles where id=(p->>'title_id')::uuid and institution_id=i for update;
 end if;
 return app.library_action_pre_accounts(i,action,p);
end$$;
revoke all on all functions in schema app from public,anon,authenticated;
notify pgrst,'reload schema';
