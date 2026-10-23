-- Server-authorized password management; passwords never enter SQL or audit.
create or replace function public.library_password_authorize(i text, target uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform app.require_role(i,array['admin']);
 if target=auth.uid() then raise exception 'Use Change my password for your own account'; end if;
 if not exists(select 1 from app.memberships where user_id=target and institution_id=i) then raise exception 'Account is not assigned to this institution'; end if;
 if exists(select 1 from app.memberships m where m.user_id=target and coalesce(app.role_for(m.institution_id),'')<>'admin') then raise exception 'Reset requires administrator access to every institution assigned to this account'; end if;
 return true;
end$$;
revoke all on function public.library_password_authorize(text,uuid) from public,anon;
grant execute on function public.library_password_authorize(text,uuid) to authenticated;
create or replace function public.library_password_audit(i text, actor_id uuid, target uuid, event text) returns void language plpgsql security definer set search_path='' as $$
begin
 if event not in ('password_reset','password_change') then raise exception 'Invalid password event'; end if;
 if event='password_reset' and not exists(select 1 from app.memberships where user_id=actor_id and institution_id=i and role='admin') then raise exception 'Administrator required'; end if;
 if event='password_change' and actor_id<>target then raise exception 'Own account required'; end if;
 if not exists(select 1 from app.memberships where user_id=target and institution_id=i) then raise exception 'Membership required'; end if;
 insert into app.audit(institution_id,actor,action,details) values(i,actor_id,event,jsonb_build_object('target_user_id',target));
end$$;
revoke all on function public.library_password_audit(text,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.library_password_audit(text,uuid,uuid,text) to service_role;

-- Three physical libraries, one network administrator, and dated availability.
-- Preserve existing records and archive superseded institutional workspaces.
alter table app.institutions add column active boolean not null default true;
alter table app.institutions add column campuses text[] not null default '{}';
update app.institutions set name='RBCET / RBMI Central Library',campuses=array['RBCET','RBMI'] where id='RBCET';
update app.institutions set name='RBCP Library',campuses=array['RBCP'] where id='RBCP';
update app.institutions set name='RBCN Library',campuses=array['RBCN'] where id='RBCN';
update app.institutions set active=false where id in ('RBMI','RBTTI');
-- Safely disambiguate any legacy local accession and patron-code collisions.
update app.copies c set accession='RBMI-'||c.accession where institution_id='RBMI' and exists(select 1 from app.copies x where x.institution_id='RBCET' and x.accession=c.accession);
update app.patrons p set code='RBMI-'||p.code where institution_id='RBMI' and exists(select 1 from app.patrons x where x.institution_id='RBCET' and x.code=p.code);
do $$declare t text;begin foreach t in array array['titles','copies','patrons','loans','holds','fines','payments','vendors','acquisitions','stock_sessions','stock_items','audit'] loop execute format('update app.%I set institution_id=''RBCET'' where institution_id=''RBMI''',t);end loop;end$$;
insert into app.holidays(institution_id,day,name) select 'RBCET',day,name from app.holidays where institution_id='RBMI' on conflict(institution_id,day) do nothing;
insert into app.memberships(user_id,institution_id,role,patron_id) select user_id,'RBCET',role,patron_id from app.memberships where institution_id='RBMI' on conflict(user_id,institution_id) do nothing;
create table app.network_admin(singleton boolean primary key default true check(singleton),user_id uuid not null unique references auth.users(id));
do $$begin if (select count(distinct user_id) from app.memberships where role='admin')>1 then raise exception 'Resolve multiple legacy admins before upgrading';end if;end$$;
insert into app.network_admin(user_id) select distinct user_id from app.memberships where role='admin';
insert into app.memberships(user_id,institution_id,role) select a.user_id,i.id,'admin' from app.network_admin a cross join app.institutions i where i.active on conflict(user_id,institution_id) do update set role='admin';
create table app.library_staff(institution_id text primary key references app.institutions,user_id uuid not null unique references auth.users(id),display_name text not null default 'Librarian',assigned_at timestamptz not null default now());
-- Only an unambiguous existing RBCET librarian is retained automatically.
insert into app.library_staff(institution_id,user_id) select 'RBCET',min(user_id::text)::uuid from app.memberships where institution_id='RBCET' and role='librarian' having count(*)=1;
create table app.library_availability(institution_id text not null references app.institutions,day date not null,available boolean not null,reason text not null check(length(trim(reason)) between 1 and 500),changed_by uuid references auth.users(id),changed_at timestamptz not null default now(),primary key(institution_id,day));
create index library_availability_closed_idx on app.library_availability(institution_id,day) where not available;
create or replace function app.role_for(i text) returns text language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from app.network_admin where user_id=auth.uid()) then 'admin'
 when m.role='admin' then null when m.role='librarian' and not exists(select 1 from app.library_staff s where s.institution_id=i and s.user_id=auth.uid()) then null else m.role end
 from app.institutions x left join app.memberships m on m.institution_id=x.id and m.user_id=auth.uid() where x.id=i and x.active
$$;
create or replace function app.open_date(i text,d date,weekends boolean) returns date language plpgsql stable set search_path='' as $$declare n integer:=0;begin while (weekends and extract(isodow from d)>5) or exists(select 1 from app.holidays where institution_id=i and day=d) or exists(select 1 from app.library_availability where institution_id=i and day=d and not available) loop d:=d+1;n:=n+1;if n>366 then raise exception 'Calendar has no open dates';end if;end loop;return d;end$$;
create or replace function app.fine_for(i text,due date,until_date date,pol jsonb) returns numeric language sql stable set search_path='' as $$
 select least((pol->>'fine_cap')::numeric,greatest(0,count(*)-(pol->>'grace_days')::integer)*(pol->>'fine_rate')::numeric)
 from generate_series(due+1,until_date,interval '1 day') d
 where (not (pol->>'exclude_weekends')::boolean or extract(isodow from d)<=5)
 and not exists(select 1 from app.holidays h where h.institution_id=i and h.day=d::date)
 and not exists(select 1 from app.library_availability a where a.institution_id=i and a.day=d::date and not a.available)
$$;
alter table app.loans add column issue_library_code text references app.institutions,add column issue_library_name text,add column issued_by uuid references auth.users(id),add column issued_at timestamptz,add column issue_barcode text,add column issue_accession text,add column issue_title text,add column patron_code_snapshot text,add column return_library_code text references app.institutions,add column returned_by uuid references auth.users(id),add column returned_at timestamptz;
update app.loans l set issue_library_code=l.institution_id,issue_library_name=i.name,issue_barcode=c.barcode,issue_accession=c.accession,issue_title=t.title,patron_code_snapshot=p.code from app.institutions i,app.copies c,app.titles t,app.patrons p where i.id=l.institution_id and c.id=l.copy_id and t.id=c.title_id and p.id=l.patron_id;
alter table app.loans add constraint same_issue_library check(issue_library_code=institution_id),add constraint same_return_library check(return_library_code is null or return_library_code=issue_library_code);
create function app.stamp_loan() returns trigger language plpgsql security definer set search_path='' as $$begin
 if TG_OP='INSERT' then
 new.issue_library_code:=new.institution_id;select name into new.issue_library_name from app.institutions where id=new.institution_id;new.issued_by:=auth.uid();new.issued_at:=now();
 select c.barcode,c.accession,t.title into new.issue_barcode,new.issue_accession,new.issue_title from app.copies c join app.titles t on t.id=c.title_id where c.id=new.copy_id and c.institution_id=new.institution_id;
 if new.issue_barcode is null then raise exception 'Copy does not belong to issuing library';end if;
 select code into new.patron_code_snapshot from app.patrons where id=new.patron_id and institution_id=new.institution_id;
 if new.patron_code_snapshot is null then raise exception 'Patron does not belong to issuing library';end if;
 elsif new.returned is not null and old.returned is null then new.return_library_code:=new.institution_id;new.returned_by:=auth.uid();new.returned_at:=now();end if;
 return new;end$$;
create trigger stamp_library_loan before insert or update on app.loans for each row execute function app.stamp_loan();
create or replace function app.library_action_core(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c app.copies; pat app.patrons; l app.loans; pol app.policies; h app.holds; f app.fines; a app.acquisitions; s app.stock_sessions; v uuid; tid uuid; amt numeric; n integer; own uuid; rowdata jsonb; result jsonb:='{}';
begin
 if action=any(array['issue','return','renew','hold','cancel_hold']) then perform app.require_role(i,array['admin','librarian','assistant','patron']);
 elsif action=any(array['pay','waive']) then perform app.require_role(i,array['admin','librarian','accountant']);
 elsif action=any(array['policy','holiday','member']) then perform app.require_role(i,array['admin']);
 else perform app.require_role(i,array['admin','librarian']); end if;
 if app.role_for(i)='patron' and action<>all(array['hold','cancel_hold','renew']) then raise exception 'Patrons may only renew and manage their own holds'; end if;
 if action='issue' then
 select * into c from app.copies where institution_id=i and (barcode=p->>'barcode' or accession=p->>'barcode'); if not found then raise exception 'Copy not found'; end if;
 perform 1 from app.titles where id=c.title_id for update;
 select * into c from app.copies where id=c.id for update;
 select * into pat from app.patrons where institution_id=i and code=p->>'patron_code' for update;
 if not found or not pat.active or (pat.expires is not null and pat.expires<app.today()) then raise exception 'Patron inactive, expired or not found'; end if;
 select * into pol from app.policies where institution_id=i and category=pat.category;
 if not found then raise exception 'No policy for patron category'; end if;
 if c.status<>'available' then raise exception 'Copy is not available'; end if;
 if (select count(*) from app.loans where patron_id=pat.id and returned is null)>=pol.max_loans then raise exception 'Loan limit reached'; end if;
 if exists(select 1 from app.loans where patron_id=pat.id and returned is null and due<app.today()) then raise exception 'Return overdue books before issuing'; end if;
 if (select coalesce(sum(amount-paid-waived),0) from app.fines where patron_id=pat.id)>pol.block_balance then raise exception 'Outstanding fines exceed policy'; end if;
 select * into h from app.holds where title_id=c.title_id and status='waiting' order by created_at,id limit 1;
 if h.id is not null and h.patron_id<>pat.id then raise exception 'Reserved for first patron in hold queue'; end if;
 insert into app.loans(institution_id,copy_id,patron_id,issued,due,policy) values(i,c.id,pat.id,app.today(),app.open_date(i,app.today()+pol.loan_days,pol.exclude_weekends),to_jsonb(pol)) returning to_jsonb(app.loans.*) into result;
 update app.copies set status='loaned' where id=c.id; if h.id is not null then update app.holds set status='fulfilled' where id=h.id; end if;
 elsif action=any(array['return','renew']) then
 select * into l from app.loans where institution_id=i and id=(p->>'id')::uuid;
 if not found then raise exception 'Loan not found'; end if;
 select title_id into tid from app.copies where id=l.copy_id; perform 1 from app.titles where id=tid for update;
 select * into l from app.loans where id=l.id for update; perform 1 from app.patrons where id=l.patron_id for update;
 if l.returned is not null then raise exception 'Loan already returned'; end if;
 if app.role_for(i)='patron' and not exists(select 1 from app.memberships where user_id=auth.uid() and institution_id=i and patron_id=l.patron_id) then raise exception 'Cannot renew another patron loan'; end if;
 if action='return' then
 amt:=app.fine_for(i,l.due,app.today(),l.policy); update app.loans set returned=app.today() where id=l.id; update app.copies set status='available' where id=l.copy_id;
 if amt>0 then insert into app.fines(institution_id,patron_id,loan_id,amount) values(i,l.patron_id,l.id,amt); end if; result:=jsonb_build_object('fine',amt);
 else
 select * into pat from app.patrons where id=l.patron_id; if not pat.active or (pat.expires is not null and pat.expires<app.today()) then raise exception 'Membership inactive or expired'; end if;
 if l.due<app.today() or l.renewals>=(l.policy->>'max_renewals')::integer then raise exception 'Overdue or renewal limit reached'; end if;
 if exists(select 1 from app.holds where title_id=tid and status='waiting') then raise exception 'Renewal blocked by hold queue'; end if;
 if (select coalesce(sum(amount-paid-waived),0) from app.fines where patron_id=pat.id)>(l.policy->>'block_balance')::numeric then raise exception 'Outstanding fines exceed policy'; end if;
 update app.loans set due=app.open_date(i,greatest(due,app.today())+(policy->>'loan_days')::integer,(policy->>'exclude_weekends')::boolean),renewals=renewals+1 where id=l.id returning to_jsonb(app.loans.*) into result;
 end if;
 elsif action='hold' then
 select * into pat from app.patrons where institution_id=i and code=p->>'patron_code' for update;
 if not found or not pat.active or (pat.expires is not null and pat.expires<app.today()) then raise exception 'Patron inactive, expired or not found'; end if;
 if app.role_for(i)='patron' and not exists(select 1 from app.memberships where user_id=auth.uid() and institution_id=i and patron_id=pat.id) then raise exception 'Cannot reserve for another patron'; end if;
 perform 1 from app.titles where id=(p->>'title_id')::uuid and institution_id=i for update; if not found then raise exception 'Title not found'; end if;
 insert into app.holds(institution_id,title_id,patron_id) values(i,(p->>'title_id')::uuid,pat.id);
 elsif action='cancel_hold' then
 select * into h from app.holds where id=(p->>'id')::uuid and institution_id=i for update; if not found or h.status<>'waiting' then raise exception 'Waiting hold not found'; end if;
 if app.role_for(i)='patron' and not exists(select 1 from app.memberships where user_id=auth.uid() and institution_id=i and patron_id=h.patron_id) then raise exception 'Cannot cancel another patron hold'; end if;
 update app.holds set status='cancelled' where id=h.id;
 elsif action=any(array['pay','waive']) then
 select * into f from app.fines where id=(p->>'id')::uuid and institution_id=i for update; if not found then raise exception 'Fine not found'; end if;
 amt:=(p->>'amount')::numeric; if amt is null or amt<=0 or amt>f.amount-f.paid-f.waived or length(trim(coalesce(p->>'reason','')))=0 then raise exception 'Valid amount and receipt/reference or waiver reason required'; end if;
 if action='pay' then update app.fines set paid=paid+amt where id=f.id; else update app.fines set waived=waived+amt where id=f.id; end if;
 insert into app.payments(institution_id,fine_id,kind,amount,reason,actor) values(i,f.id,case when action='pay' then 'payment' else 'waiver' end,amt,p->>'reason',auth.uid());
 elsif action='title' then
 if length(trim(coalesce(p->>'title','')))=0 or length(trim(coalesce(p->>'author','')))=0 then raise exception 'Title and author required'; end if;
 if nullif(p->>'id','') is null then insert into app.titles(institution_id,title,author,isbn,publisher,subject,classification,year) values(i,p->>'title',p->>'author',coalesce(p->>'isbn',''),coalesce(p->>'publisher',''),coalesce(p->>'subject',''),coalesce(p->>'classification',''),nullif(p->>'year','')::integer) returning id into v;
 else update app.titles set title=p->>'title',author=p->>'author',isbn=coalesce(p->>'isbn',''),publisher=coalesce(p->>'publisher',''),subject=coalesce(p->>'subject',''),classification=coalesce(p->>'classification',''),year=nullif(p->>'year','')::integer where institution_id=i and id=(p->>'id')::uuid returning id into v; if v is null then raise exception 'Title not found'; end if; end if; result:=jsonb_build_object('id',v);
 elsif action='copy' then
 perform 1 from app.titles where institution_id=i and id=(p->>'title_id')::uuid; if not found then raise exception 'Title not found'; end if;
 if length(trim(coalesce(p->>'accession','')))=0 or length(trim(coalesce(p->>'barcode','')))=0 then raise exception 'Accession and barcode required'; end if;
 insert into app.copies(institution_id,title_id,accession,barcode,shelf,price) values(i,(p->>'title_id')::uuid,p->>'accession',p->>'barcode',coalesce(p->>'shelf',''),coalesce(nullif(p->>'price','')::numeric,0));
 elsif action='copy_status' then
 if p->>'status'<>all(array['available','lost','damaged','withdrawn','missing']) then raise exception 'Invalid manual status'; end if;
 select * into c from app.copies where institution_id=i and id=(p->>'id')::uuid for update; if not found or c.status='loaned' then raise exception 'Copy missing or currently on loan'; end if;
 if length(trim(coalesce(p->>'reason','')))=0 then raise exception 'Reason required'; end if; update app.copies set status=p->>'status' where id=c.id;
 elsif action='patron' then
 if length(trim(coalesce(p->>'code','')))=0 or length(trim(coalesce(p->>'name','')))=0 then raise exception 'Code and name required'; end if;
 insert into app.patrons(institution_id,code,name,email,category,department,active,expires) values(i,p->>'code',p->>'name',coalesce(p->>'email',''),p->>'category',coalesce(p->>'department',''),coalesce((p->>'active')::boolean,true),nullif(p->>'expires','')::date) on conflict(institution_id,code) do update set name=excluded.name,email=excluded.email,category=excluded.category,department=excluded.department,active=excluded.active,expires=excluded.expires returning id into v; result:=jsonb_build_object('id',v);
 elsif action='policy' then
 insert into app.policies(institution_id,category,loan_days,max_loans,max_renewals,fine_rate,grace_days,fine_cap,block_balance,exclude_weekends) values(i,p->>'category',(p->>'loan_days')::integer,(p->>'max_loans')::integer,(p->>'max_renewals')::integer,(p->>'fine_rate')::numeric,(p->>'grace_days')::integer,(p->>'fine_cap')::numeric,(p->>'block_balance')::numeric,(p->>'exclude_weekends')::boolean) on conflict(institution_id,category) do update set loan_days=excluded.loan_days,max_loans=excluded.max_loans,max_renewals=excluded.max_renewals,fine_rate=excluded.fine_rate,grace_days=excluded.grace_days,fine_cap=excluded.fine_cap,block_balance=excluded.block_balance,exclude_weekends=excluded.exclude_weekends;
 elsif action='holiday' then insert into app.holidays(institution_id,day,name) values(i,(p->>'day')::date,p->>'name') on conflict(institution_id,day) do update set name=excluded.name;
 elsif action='member' then
 if nullif(p->>'patron_id','') is not null and not exists(select 1 from app.patrons where id=(p->>'patron_id')::uuid and institution_id=i) then raise exception 'Patron must belong to institution'; end if;
 if p->>'role'='patron' and nullif(p->>'patron_id','') is null then raise exception 'Patron account requires linked patron'; end if;
 if (p->>'user_id')::uuid=auth.uid() then raise exception 'Cannot change your own role'; end if;
 insert into app.memberships(user_id,institution_id,role,patron_id) values((p->>'user_id')::uuid,i,p->>'role',nullif(p->>'patron_id','')::uuid) on conflict(user_id,institution_id) do update set role=excluded.role,patron_id=excluded.patron_id;
 elsif action='vendor' then insert into app.vendors(institution_id,name,email,phone) values(i,p->>'name',coalesce(p->>'email',''),coalesce(p->>'phone',''));
 elsif action='order' then
 if not exists(select 1 from app.vendors where id=(p->>'vendor_id')::uuid and institution_id=i) or not exists(select 1 from app.titles where id=(p->>'title_id')::uuid and institution_id=i) then raise exception 'Vendor/title institution mismatch'; end if;
 insert into app.acquisitions(institution_id,vendor_id,title_id,invoice,quantity,unit_price) values(i,(p->>'vendor_id')::uuid,(p->>'title_id')::uuid,p->>'invoice',(p->>'quantity')::integer,(p->>'unit_price')::numeric);
 elsif action='receive' then
 select * into a from app.acquisitions where institution_id=i and id=(p->>'id')::uuid for update; if not found or a.status<>'ordered' then raise exception 'Open order not found'; end if;
 if length(trim(coalesce(p->>'prefix','')))=0 then raise exception 'Accession prefix required'; end if;
 for n in 1..a.quantity loop insert into app.copies(institution_id,title_id,accession,barcode,shelf,price) values(i,a.title_id,(p->>'prefix')||'-'||n,i||'-'||(p->>'prefix')||'-'||n,coalesce(p->>'shelf',''),a.unit_price); end loop;
 update app.acquisitions set status='received',received_at=app.today() where id=a.id;
 elsif action='cancel_order' then update app.acquisitions set status='cancelled' where id=(p->>'id')::uuid and institution_id=i and status='ordered'; if not found then raise exception 'Open order not found'; end if;
 elsif action='stock_start' then
 insert into app.stock_sessions(institution_id,name) values(i,p->>'name') returning id into v;
 insert into app.stock_items(institution_id,session_id,copy_id,expected_status) select i,v,id,status from app.copies where institution_id=i and status<>'withdrawn';
 elsif action=any(array['stock_scan','stock_close']) then
 select * into s from app.stock_sessions where institution_id=i and id=(p->>'id')::uuid for update; if not found or s.status<>'open' then raise exception 'Open stock session not found'; end if;
 if action='stock_scan' then update app.stock_items set seen_at=now() where session_id=s.id and copy_id in(select id from app.copies where institution_id=i and barcode=p->>'barcode'); if not found then raise exception 'Barcode not in stock snapshot'; end if;
 else update app.stock_sessions set status='closed',closed_at=now() where id=s.id; end if;
 elsif action='import' then
 if p->>'kind'<>all(array['books','students']) or jsonb_typeof(p->'rows')<>'array' or jsonb_array_length(p->'rows')>1000 then raise exception 'Import must contain at most 1000 books/students'; end if;
 n:=0; for rowdata in select value from jsonb_array_elements(p->'rows') loop
 if p->>'kind'='students' then perform public.library_action(i,'patron',rowdata||jsonb_build_object('category',coalesce(nullif(rowdata->>'category',''),'student')));
 else
 select id into v from app.titles where institution_id=i and isbn<>'' and isbn=rowdata->>'isbn' order by id limit 1;
 if v is null then result:=public.library_action(i,'title',rowdata); v:=(result->>'id')::uuid; end if;
 perform public.library_action(i,'copy',rowdata||jsonb_build_object('title_id',v)); end if; n:=n+1; end loop; result:=jsonb_build_object('imported',n);
 else raise exception 'Unknown action: %',action; end if;
 insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,p); return result;
end$$;

create or replace function app.library_snapshot_core(i text) returns jsonb language plpgsql security definer set search_path='' as $$declare r text; p uuid; out jsonb:='{}'; tbl text; dat jsonb; begin perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']); r:=app.role_for(i); select patron_id into p from app.memberships where user_id=auth.uid() and institution_id=i;
 foreach tbl in array array['titles','copies','patrons','policies','holidays','loans','holds','fines','payments','vendors','acquisitions','stock_sessions','stock_items','audit','memberships'] loop
 if r='patron' and tbl=any(array['payments','vendors','acquisitions','stock_sessions','stock_items','audit','memberships']) then dat:='[]';
 elsif r='patron' and tbl='patrons' then select coalesce(jsonb_agg(to_jsonb(t)),'[]') into dat from app.patrons t where id=p and institution_id=i;
 elsif r='patron' and tbl=any(array['loans','holds','fines']) then execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from app.%I t where institution_id=$1 and patron_id=$2',tbl) into dat using i,p;
 else execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from app.%I t where institution_id=$1',tbl) into dat using i; end if;
 out:=out||jsonb_build_object(tbl,dat); end loop; return out; end$$;


create or replace function public.library_bootstrap() returns jsonb language plpgsql security definer set search_path='' as $$begin if auth.uid() is null then raise exception 'Sign in required';end if;return jsonb_build_object('memberships',(select coalesce(jsonb_agg(jsonb_build_object('institution_id',i.id,'role',app.role_for(i.id),'name',i.name,'campuses',i.campuses,'patron_id',m.patron_id) order by i.id),'[]') from app.institutions i left join app.memberships m on m.institution_id=i.id and m.user_id=auth.uid() where i.active and app.role_for(i.id) is not null));end$$;
create or replace function public.library_snapshot(i text) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 result:=app.library_snapshot_core(i);
 return result||jsonb_build_object('library',(select to_jsonb(x) from app.institutions x where id=i),'librarian',(select jsonb_build_object('user_id',s.user_id,'display_name',s.display_name) from app.library_staff s where s.institution_id=i),'availability',(select coalesce(jsonb_agg(to_jsonb(a) order by a.day desc),'[]') from app.library_availability a where a.institution_id=i),'today',app.today());end$$;
create or replace function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare r text;target uuid;previous uuid;d date;result jsonb;begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);r:=app.role_for(i);
 if jsonb_typeof(p)<>'object' then raise exception 'Object payload required';end if;
 if action='account_email_audit' then
 perform app.require_role(i,array['admin']);insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,jsonb_build_object('target_user_id',(p->>'target_user_id')::uuid));return jsonb_build_object('saved',true);
 elsif action='availability' then
 perform app.require_role(i,array['admin','librarian']);d:=(p->>'day')::date;
 if d is null or jsonb_typeof(p->'available')<>'boolean' or length(trim(coalesce(p->>'reason','')))=0 then raise exception 'Date, availability and reason required';end if;
 if r<>'admin' and d<app.today() then raise exception 'Only administrator may correct past availability';end if;
 if d>app.today()+366 then raise exception 'Availability date too far ahead';end if;
 perform 1 from app.institutions where id=i for update;
 insert into app.library_availability(institution_id,day,available,reason,changed_by) values(i,d,(p->>'available')::boolean,p->>'reason',auth.uid()) on conflict(institution_id,day) do update set available=excluded.available,reason=excluded.reason,changed_by=auth.uid(),changed_at=now();
 insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,p);return jsonb_build_object('saved',true);
 elsif action='assign_librarian' then
 perform app.require_role(i,array['admin']);target:=(p->>'user_id')::uuid;
 if target is null or not exists(select 1 from auth.users where id=target) then raise exception 'Existing Auth account required';end if;
 if exists(select 1 from app.network_admin where user_id=target) then raise exception 'Administrator cannot be assigned as librarian';end if;
 if length(trim(coalesce(p->>'display_name','')))=0 then raise exception 'Librarian display name required';end if;
 perform 1 from app.institutions where active order by id for update;
 if exists(select 1 from app.library_staff where user_id=target and institution_id<>i) then raise exception 'Each librarian must be assigned to a separate library';end if;
 select user_id into previous from app.library_staff where institution_id=i;
 delete from app.memberships where user_id=previous and institution_id=i and role='librarian' and previous<>target;
 insert into app.library_staff(institution_id,user_id,display_name) values(i,target,p->>'display_name') on conflict(institution_id) do update set user_id=excluded.user_id,display_name=excluded.display_name,assigned_at=now();
 insert into app.memberships(user_id,institution_id,role) values(target,i,'librarian') on conflict(user_id,institution_id) do update set role='librarian',patron_id=null;
 insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,p||jsonb_build_object('previous_user_id',previous));return jsonb_build_object('saved',true);
 elsif action='member' then
 if p->>'role'='admin' then raise exception 'There is one network administrator; administrator role cannot be assigned here';end if;
 if p->>'role'='librarian' then raise exception 'Use Assign librarian to manage the designated librarian';end if;
 if exists(select 1 from app.library_staff where user_id=(p->>'user_id')::uuid and institution_id=i) then raise exception 'Replace the assigned librarian before changing their role';end if;
 end if;
 if action=any(array['issue','return']) then
 if coalesce(p->>'library_code','')<>i then raise exception 'Scan/select the correct library code before issuing or returning';end if;
 perform 1 from app.institutions where id=i for update;
 if action='return' and not exists(select 1 from app.loans where id=(p->>'id')::uuid and issue_library_code=i) then raise exception 'Return this book to its issuing library';end if;
 end if;
 result:=app.library_action_core(i,action,p);return result;
end$$;
-- Explicitly protect every new private object; public RPCs alone are exposed.
alter table app.network_admin enable row level security;
alter table app.library_staff enable row level security;
alter table app.library_availability enable row level security;
revoke all on all tables in schema app from public,anon,authenticated;
revoke all on all functions in schema app from public,anon,authenticated;
revoke all on function public.library_bootstrap(),public.library_snapshot(text),public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_bootstrap(),public.library_snapshot(text),public.library_action(text,text,jsonb) to authenticated;

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

-- Preserve source fields without exposing private import archives through the catalogue.
alter table app.patrons add column profile jsonb not null default '{}'::jsonb check(jsonb_typeof(profile)='object');
create table app.import_batches(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,source_name text not null,source_hash text not null,counts jsonb not null default '{}',created_at timestamptz not null default now(),actor uuid references auth.users,unique(institution_id,source_hash));
create table app.import_records(id uuid primary key default gen_random_uuid(),batch_id uuid not null references app.import_batches,kind text not null check(kind in ('student','book')),source_sheet text not null,source_row integer not null,entity_id uuid not null,source_data jsonb not null,unique(batch_id,source_sheet,source_row));
create index import_records_entity on app.import_records(entity_id,kind);
alter table app.import_batches enable row level security;
alter table app.import_records enable row level security;
revoke all on app.import_batches,app.import_records from public,anon,authenticated;
create index titles_library_isbn on app.titles(institution_id,isbn);
create index copies_library_title on app.copies(institution_id,title_id);
create index patrons_library on app.patrons(institution_id);
alter function public.library_action(text,text,jsonb) rename to library_action_v3;
alter function public.library_action_v3(text,text,jsonb) set schema app;
revoke all on function app.library_action_v3(text,text,jsonb) from public,anon,authenticated;
create function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; rowdata jsonb; n integer:=0; v uuid;
begin
 if action='import' and p->>'kind'='students' then
  perform app.require_role(i,array['admin','librarian']);
  if jsonb_typeof(p->'rows') is distinct from 'array' or jsonb_array_length(p->'rows')>1000 then raise exception 'At most 1000 students per batch'; end if;
  for rowdata in select value from jsonb_array_elements(p->'rows') loop
   perform public.library_action(i,'patron',rowdata||jsonb_build_object('code',coalesce(nullif(rowdata->>'code',''),nullif(rowdata->>'card_no',''),rowdata->>'roll_no'),'category','student','active',coalesce(rowdata->'active','true'::jsonb),'department',coalesce(rowdata->>'department',concat_ws(' / ',rowdata->>'course',rowdata->>'branch',rowdata->>'year')),'profile',coalesce(rowdata->'profile',rowdata-'name'-'email'))); n:=n+1;
  end loop;
  return jsonb_build_object('imported',n);
 elsif action='patron' then
  if p ? 'profile' and jsonb_typeof(p->'profile')<>'object' then raise exception 'Student profile must be an object'; end if;
  result:=app.library_action_v3(i,action,p);
  update app.patrons set profile=profile||coalesce(p->'profile','{}') where institution_id=i and code=p->>'code';return result;
 elsif action='source_details' then
  perform app.require_role(i,array['admin','librarian']);
  return coalesce((select jsonb_agg(jsonb_build_object('source',b.source_name,'sheet',r.source_sheet,'row',r.source_row,'fields',r.source_data)) from app.import_records r join app.import_batches b on b.id=r.batch_id where b.institution_id=i and r.entity_id=(p->>'id')::uuid),'[]'::jsonb);
 end if;
 return app.library_action_v3(i,action,p);
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;

alter function app.today() set search_path='';

-- Assemble each collection once. Avoid repeatedly copying a multi-megabyte JSON object.
create or replace function public.library_snapshot(i text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r text;own uuid;u uuid:=auth.uid();begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);r:=app.role_for(i);
 select patron_id into own from app.memberships where user_id=u and institution_id=i;
 return jsonb_build_object(
'titles',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.titles x where institution_id=i),
'copies',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.copies x where institution_id=i),
'policies',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.policies x where institution_id=i),
'holidays',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.holidays x where institution_id=i),
'patrons',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.patrons x where institution_id=i and (r<>'patron' or id=own)),
'loans',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.loans x where institution_id=i and (r<>'patron' or patron_id=own)),
'holds',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.holds x where institution_id=i and (r<>'patron' or patron_id=own)),
'fines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.fines x where institution_id=i and (r<>'patron' or patron_id=own)),
'payments',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.payments x where institution_id=i) end,
'vendors',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.vendors x where institution_id=i) end,
'acquisitions',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.acquisitions x where institution_id=i) end,
'stock_sessions',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.stock_sessions x where institution_id=i) end,
'stock_items',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.stock_items x where institution_id=i) end,
'audit',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.audit x where institution_id=i) end,
'memberships',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.memberships x where institution_id=i) end,
'authorities',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.authorities x where institution_id=i),
'title_authorities',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.title_authorities x where institution_id=i),
'subscriptions',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.subscriptions x where institution_id=i),
'serial_issues',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.serial_issues x where institution_id=i),
'reading_lists',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.reading_lists x where institution_id=i and (visibility='public' or owner=u)),
'list_entries',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.list_entries x where institution_id=i and exists(select 1 from app.reading_lists l where l.id=x.list_id and (l.visibility='public' or l.owner=u))),
'budgets',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.budgets x where institution_id=i) end,
'funds',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.funds x where institution_id=i) end,
'baskets',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.baskets x where institution_id=i) end,
'saved_reports',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.saved_reports x where institution_id=i) end,
'library',(select to_jsonb(x) from app.institutions x where id=i),
'librarian',(select jsonb_build_object('user_id',user_id,'display_name',display_name) from app.library_staff where institution_id=i),
'availability',(select coalesce(jsonb_agg(to_jsonb(x) order by day desc),'[]') from app.library_availability x where institution_id=i),
'today',app.today());
end$$;

-- Assemble each collection once. Avoid repeatedly copying a multi-megabyte JSON object.
create or replace function public.library_workspace(i text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r text;own uuid;u uuid:=auth.uid();begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);r:=app.role_for(i);
 select patron_id into own from app.memberships where user_id=u and institution_id=i;
 return jsonb_build_object(
'titles','[]'::jsonb,
'copies','[]'::jsonb,
'policies',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.policies x where institution_id=i),
'holidays',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.holidays x where institution_id=i),
'patrons',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.patrons x where institution_id=i and (r<>'patron' or id=own)),
'loans',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.loans x where institution_id=i and (r<>'patron' or patron_id=own)),
'holds',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.holds x where institution_id=i and (r<>'patron' or patron_id=own)),
'fines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.fines x where institution_id=i and (r<>'patron' or patron_id=own)),
'payments',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.payments x where institution_id=i) end,
'vendors',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.vendors x where institution_id=i) end,
'acquisitions',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.acquisitions x where institution_id=i) end,
'stock_sessions',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.stock_sessions x where institution_id=i) end,
'stock_items',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.stock_items x where institution_id=i) end,
'audit',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.audit x where institution_id=i) end,
'memberships',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.memberships x where institution_id=i) end,
'authorities',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.authorities x where institution_id=i),
'title_authorities',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.title_authorities x where institution_id=i),
'subscriptions',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.subscriptions x where institution_id=i),
'serial_issues',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.serial_issues x where institution_id=i),
'reading_lists',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.reading_lists x where institution_id=i and (visibility='public' or owner=u)),
'list_entries',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.list_entries x where institution_id=i and exists(select 1 from app.reading_lists l where l.id=x.list_id and (l.visibility='public' or l.owner=u))),
'budgets',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.budgets x where institution_id=i) end,
'funds',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.funds x where institution_id=i) end,
'baskets',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.baskets x where institution_id=i) end,
'saved_reports',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.saved_reports x where institution_id=i) end,
'library',(select to_jsonb(x) from app.institutions x where id=i),
'librarian',(select jsonb_build_object('user_id',user_id,'display_name',display_name) from app.library_staff where institution_id=i),
'availability',(select coalesce(jsonb_agg(to_jsonb(x) order by day desc),'[]') from app.library_availability x where institution_id=i),
'today',app.today());
end$$;

create index titles_library_page on app.titles(institution_id,id);
create index copies_library_page on app.copies(institution_id,id);
create function public.library_collection_page(i text,kind text,after_id uuid default null,page_size integer default 5000) returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb;begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);
 if kind<>all(array['titles','copies']) or kind is null or page_size is null or page_size<1 or page_size>5000 then raise exception 'Invalid collection page request';end if;
 execute format('select coalesce(jsonb_agg(to_jsonb(x) order by x.id),''[]''::jsonb) from (select * from app.%I where institution_id=$1 and ($2 is null or id>$2) order by id limit $3) x',kind) into rows using i,after_id,page_size;
 return jsonb_build_object('rows',rows,'next_id',case when jsonb_array_length(rows)=page_size then rows->-1->>'id' else null end);
end$$;
revoke all on function public.library_workspace(text),public.library_collection_page(text,text,uuid,integer) from public,anon;
grant execute on function public.library_workspace(text),public.library_collection_page(text,text,uuid,integer) to authenticated;

create function public.library_catalogue_search(library_code text,q text default '',max_titles integer default 40) returns jsonb language plpgsql security definer set search_path='' as $$
declare ids uuid[];more boolean;begin
 if max_titles is null or max_titles<1 or max_titles>2000 or length(coalesce(q,''))>200 then raise exception 'Narrow the search or use at most 2000 catalogue results';end if;
 if not exists(select 1 from app.institutions where id=library_code and active) then raise exception 'Library not found';end if;
 select coalesce(array_agg(x.id order by x.id),'{}') into ids from (select id from app.titles where institution_id=library_code and strpos(lower(concat_ws(' ',title,author,isbn,subject)),lower(coalesce(q,'')))>0 order by id limit max_titles+1) x;
 more:=cardinality(ids)>max_titles;ids:=ids[1:max_titles];
 return jsonb_build_object('libraries',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by id),'[]') from app.institutions where active),'titles',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from app.titles x where institution_id=library_code and id=any(ids)), 'copies',(select coalesce(jsonb_agg(jsonb_build_object('title_id',title_id,'accession',accession,'shelf',shelf,'status',status)),'[]') from app.copies where institution_id=library_code and title_id=any(ids)), 'has_more',more);
end$$;
revoke all on function public.library_catalogue_search(text,text,integer) from public;
grant execute on function public.library_catalogue_search(text,text,integer) to anon,authenticated;

-- Add the separately operated RBGN library; no existing collection is moved.
insert into app.institutions(id,name,active,campuses) values('RBGN','RBGN Library',true,array['RBGN']) on conflict(id) do update set active=true;
insert into app.policies(institution_id,category,loan_days,max_loans,max_renewals,fine_rate,grace_days,fine_cap,block_balance,exclude_weekends)
select 'RBGN',c,case when c='faculty' then 30 else 14 end,case when c='faculty' then 10 else 3 end,2,2,1,500,100,true from unnest(array['student','faculty','staff','alumni','guest']) c on conflict(institution_id,category) do nothing;
insert into app.memberships(user_id,institution_id,role) select user_id,'RBGN','admin' from app.network_admin on conflict(user_id,institution_id) do update set role='admin',patron_id=null;
insert into app.audit(institution_id,actor,action,details) select 'RBGN',user_id,'library_added',jsonb_build_object('code','RBGN','name','RBGN Library') from app.network_admin;

-- One atomic, administrator-approved calendar upload per selected library.
create function app.import_holidays(i text, rows_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare row_data jsonb; d date; n integer:=0; seen date[]:=array[]::date[]; label text;
begin
 perform app.require_role(i,array['admin']);
 if jsonb_typeof(rows_data) is distinct from 'array' then raise exception 'Holiday rows must be an array'; end if;
 if jsonb_array_length(rows_data) not between 1 and 1000 then raise exception 'Upload 1 to 1000 holidays per batch'; end if;
 for row_data in select value from jsonb_array_elements(rows_data) loop
  n:=n+1;
  if jsonb_typeof(row_data) is distinct from 'object' or coalesce(row_data->>'day','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Row %: date must be YYYY-MM-DD',n; end if;
  begin d:=(row_data->>'day')::date; exception when others then raise exception 'Row %: invalid calendar date',n; end;
  if d < date '1900-01-01' or d > date '2100-12-31' then raise exception 'Row %: date must be between 1900 and 2100',n; end if;
  label:=btrim(row_data->>'name');
  if label is null or length(label) not between 1 and 200 then raise exception 'Row %: holiday name must contain 1 to 200 characters',n; end if;
  if d=any(seen) then raise exception 'Row %: duplicate holiday date %',n,d; end if;
  seen:=array_append(seen,d);
  insert into app.holidays(institution_id,day,name) values(i,d,label)
   on conflict(institution_id,day) do update set name=excluded.name;
 end loop;
 insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),'holiday_import',jsonb_build_object('imported',n,'rows',rows_data));
 return jsonb_build_object('imported',n);
end$$;
revoke all on function app.import_holidays(text,jsonb) from public,anon,authenticated;
create or replace function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; rowdata jsonb; n integer:=0; v uuid;
begin
 if action='holiday_import' then return app.import_holidays(i,p->'rows');
 elsif action='holiday' then return app.import_holidays(i,jsonb_build_array(p)); end if;
 if action='import' and p->>'kind'='students' then
  perform app.require_role(i,array['admin','librarian']);
  if jsonb_typeof(p->'rows') is distinct from 'array' or jsonb_array_length(p->'rows')>1000 then raise exception 'At most 1000 students per batch'; end if;
  for rowdata in select value from jsonb_array_elements(p->'rows') loop
   perform public.library_action(i,'patron',rowdata||jsonb_build_object('code',coalesce(nullif(rowdata->>'code',''),nullif(rowdata->>'card_no',''),rowdata->>'roll_no'),'category','student','active',coalesce(rowdata->'active','true'::jsonb),'department',coalesce(rowdata->>'department',concat_ws(' / ',rowdata->>'course',rowdata->>'branch',rowdata->>'year')),'profile',coalesce(rowdata->'profile',rowdata-'name'-'email'))); n:=n+1;
  end loop;
  return jsonb_build_object('imported',n);
 elsif action='patron' then
  if p ? 'profile' and jsonb_typeof(p->'profile')<>'object' then raise exception 'Student profile must be an object'; end if;
  result:=app.library_action_v3(i,action,p);
  update app.patrons set profile=profile||coalesce(p->'profile','{}') where institution_id=i and code=p->>'code';return result;
 elsif action='source_details' then
  perform app.require_role(i,array['admin','librarian']);
  return coalesce((select jsonb_agg(jsonb_build_object('source',b.source_name,'sheet',r.source_sheet,'row',r.source_row,'fields',r.source_data)) from app.import_records r join app.import_batches b on b.id=r.batch_id where b.institution_id=i and r.entity_id=(p->>'id')::uuid),'[]'::jsonb);
 end if;
 return app.library_action_v3(i,action,p);
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;

-- Institute-scoped faculty memberships; no Auth login is created by patron import.
create or replace function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; rowdata jsonb; n integer:=0; v uuid; institute_code text; seen_codes text[]:=array[]::text[];
begin
 if action='holiday_import' then return app.import_holidays(i,p->'rows');
 elsif action='holiday' then return app.import_holidays(i,jsonb_build_array(p)); end if;
 if action='import' and p->>'kind' in ('students','faculty') then
  perform app.require_role(i,array['admin','librarian']);
  if jsonb_typeof(p->'rows') is distinct from 'array' or jsonb_array_length(p->'rows')>1000 then raise exception 'At most 1000 patrons per batch'; end if;
  for rowdata in select value from jsonb_array_elements(p->'rows') loop
   if p->>'kind'='faculty' then
    if nullif(btrim(rowdata->>'code'),'') is null or nullif(btrim(rowdata->>'name'),'') is null then raise exception 'Faculty code and name are required'; end if;
    if rowdata->>'code'=any(seen_codes) then raise exception 'Duplicate faculty code in batch'; end if;
    seen_codes:=array_append(seen_codes,rowdata->>'code');
    if exists(select 1 from app.patrons where institution_id=i and code=rowdata->>'code' and category<>'faculty') then raise exception 'Faculty code already belongs to another patron category'; end if;
    rowdata:=rowdata||jsonb_build_object('category','faculty','institute',coalesce(nullif(btrim(rowdata->>'institute'),''),i));
   end if;
   perform public.library_action(i,'patron',rowdata||jsonb_build_object('code',coalesce(nullif(rowdata->>'code',''),nullif(rowdata->>'card_no',''),rowdata->>'roll_no'),'category',case when p->>'kind'='faculty' then 'faculty' else 'student' end,'expires',nullif(btrim(rowdata->>'expires'),''),'active',coalesce(rowdata->'active','true'::jsonb),'department',coalesce(rowdata->>'department',concat_ws(' / ',rowdata->>'course',rowdata->>'branch',rowdata->>'year')),'profile',coalesce(rowdata->'profile',rowdata-'name'-'email'))); n:=n+1;
  end loop;
  return jsonb_build_object('imported',n);
 elsif action='patron' then
  perform app.require_role(i,array['admin','librarian']);
  if p ? 'institute' or p->>'category'='faculty' then
   institute_code:=upper(btrim(coalesce(nullif(p->>'institute',''),p->'profile'->>'institute',i)));
   if not exists(select 1 from app.institutions where id=i and active and institute_code=any(campuses)) then raise exception 'Institute must belong to the selected library'; end if;
   p:=p||jsonb_build_object('profile',coalesce(p->'profile','{}'::jsonb)||jsonb_build_object('institute',institute_code));
  end if;
  if p ? 'profile' and jsonb_typeof(p->'profile')<>'object' then raise exception 'Student profile must be an object'; end if;
  result:=app.library_action_v3(i,action,p);
  update app.patrons set profile=profile||coalesce(p->'profile','{}') where institution_id=i and code=p->>'code';return result;
 elsif action='source_details' then
  perform app.require_role(i,array['admin','librarian']);
  return coalesce((select jsonb_agg(jsonb_build_object('source',b.source_name,'sheet',r.source_sheet,'row',r.source_row,'fields',r.source_data)) from app.import_records r join app.import_batches b on b.id=r.batch_id where b.institution_id=i and r.entity_id=(p->>'id')::uuid),'[]'::jsonb);
 end if;
 return app.library_action_v3(i,action,p);
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;
