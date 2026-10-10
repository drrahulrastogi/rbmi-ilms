-- All writes go through explicit transactional RPCs. app is not exposed by PostgREST.
create schema if not exists app;
create table app.institutions(id text primary key, name text not null);
create table app.memberships(user_id uuid not null references auth.users(id), institution_id text not null references app.institutions, role text not null check(role in ('admin','librarian','assistant','accountant','auditor','patron')), patron_id uuid, primary key(user_id,institution_id));
create table app.patrons(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, code text not null, name text not null, email text default '', category text not null check(category in ('student','faculty','staff','alumni','guest')), department text default '', active boolean not null default true, expires date, unique(institution_id,code));
alter table app.memberships add foreign key(patron_id) references app.patrons;
create table app.titles(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, title text not null, author text not null, isbn text default '', publisher text default '', subject text default '', classification text default '', year integer check(year between 1000 and 3000));
create table app.copies(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, title_id uuid not null references app.titles, accession text not null, barcode text not null unique, shelf text default '', price numeric(12,2) not null default 0 check(price>=0), status text not null default 'available' check(status in ('available','loaned','lost','damaged','withdrawn','missing')), unique(institution_id,accession));
create table app.policies(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, category text not null check(category in ('student','faculty','staff','alumni','guest')), loan_days integer not null check(loan_days between 1 and 365), max_loans integer not null check(max_loans between 1 and 100), max_renewals integer not null check(max_renewals between 0 and 20), fine_rate numeric(10,2) not null check(fine_rate>=0), grace_days integer not null default 0 check(grace_days>=0), fine_cap numeric(12,2) not null default 1000 check(fine_cap>=0), block_balance numeric(12,2) not null default 100 check(block_balance>=0), exclude_weekends boolean not null default true, unique(institution_id,category));
create table app.holidays(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, day date not null, name text not null, unique(institution_id,day));
create table app.loans(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, copy_id uuid not null references app.copies, patron_id uuid not null references app.patrons, issued date not null, due date not null, returned date, renewals integer not null default 0, policy jsonb not null);
create unique index one_open_loan on app.loans(copy_id) where returned is null;
create index patron_open_loans on app.loans(patron_id) where returned is null;
create table app.holds(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, title_id uuid not null references app.titles, patron_id uuid not null references app.patrons, created_at timestamptz not null default now(), status text not null default 'waiting' check(status in ('waiting','fulfilled','cancelled')));
create unique index one_waiting_hold on app.holds(title_id,patron_id) where status='waiting';
create table app.fines(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, patron_id uuid not null references app.patrons, loan_id uuid not null unique references app.loans, amount numeric(12,2) not null check(amount>=0), paid numeric(12,2) not null default 0 check(paid>=0), waived numeric(12,2) not null default 0 check(waived>=0), check(paid+waived<=amount));
create table app.payments(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, fine_id uuid not null references app.fines, kind text not null check(kind in ('payment','waiver')), amount numeric(12,2) not null check(amount>0), reason text not null, created_at timestamptz not null default now(), actor uuid references auth.users);
create table app.vendors(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, name text not null, email text default '', phone text default '');
create table app.acquisitions(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, vendor_id uuid not null references app.vendors, title_id uuid not null references app.titles, invoice text not null, quantity integer not null check(quantity between 1 and 1000), unit_price numeric(12,2) not null check(unit_price>=0), status text not null default 'ordered' check(status in ('ordered','received','cancelled')), ordered_at date not null default current_date, received_at date, unique(institution_id,vendor_id,invoice,title_id));
create table app.stock_sessions(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, name text not null, status text not null default 'open' check(status in ('open','closed')), created_at timestamptz not null default now(), closed_at timestamptz);
create unique index one_stock_session on app.stock_sessions(institution_id) where status='open';
create table app.stock_items(id uuid primary key default gen_random_uuid(), institution_id text not null references app.institutions, session_id uuid not null references app.stock_sessions, copy_id uuid not null references app.copies, expected_status text not null, seen_at timestamptz, unique(session_id,copy_id));
create table app.audit(id bigint generated always as identity primary key, institution_id text not null references app.institutions, actor uuid, action text not null, details jsonb not null, created_at timestamptz not null default now());

create function app.today() returns date language sql stable as $$select (now() at time zone 'Asia/Kolkata')::date$$;
create function app.role_for(i text) returns text language sql stable security definer set search_path='' as $$select role from app.memberships where user_id=auth.uid() and institution_id=i$$;
create function app.require_role(i text, roles text[]) returns void language plpgsql security definer set search_path='' as $$begin if app.role_for(i) is null or not (app.role_for(i)=any(roles)) then raise exception 'Access denied for this institution/action'; end if; end$$;
create function app.open_date(i text,d date,weekends boolean) returns date language plpgsql stable set search_path='' as $$declare n integer:=0; begin while (weekends and extract(isodow from d)>5) or exists(select 1 from app.holidays where institution_id=i and day=d) loop d:=d+1; n:=n+1; if n>366 then raise exception 'Calendar has no open dates'; end if; end loop; return d; end$$;
create function app.fine_for(i text,due date,until_date date,pol jsonb) returns numeric language sql stable set search_path='' as $$select least((pol->>'fine_cap')::numeric, greatest(0,count(*)-(pol->>'grace_days')::integer)*(pol->>'fine_rate')::numeric) from generate_series(due+1,until_date,interval '1 day') d where (not (pol->>'exclude_weekends')::boolean or extract(isodow from d)<=5) and not exists(select 1 from app.holidays h where h.institution_id=i and h.day=d::date)$$;
create function public.library_bootstrap() returns jsonb language plpgsql security definer set search_path='' as $$begin if auth.uid() is null then raise exception 'Sign in required'; end if; return (select jsonb_build_object('memberships',coalesce(jsonb_agg(jsonb_build_object('institution_id',m.institution_id,'role',m.role,'name',i.name,'patron_id',m.patron_id)),'[]'::jsonb)) from app.memberships m join app.institutions i on i.id=m.institution_id where user_id=auth.uid()); end$$;
create function public.library_snapshot(i text) returns jsonb language plpgsql security definer set search_path='' as $$declare r text; p uuid; out jsonb:='{}'; tbl text; dat jsonb; begin perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']); r:=app.role_for(i); select patron_id into p from app.memberships where user_id=auth.uid() and institution_id=i;
 foreach tbl in array array['titles','copies','patrons','policies','holidays','loans','holds','fines','payments','vendors','acquisitions','stock_sessions','stock_items','audit','memberships'] loop
 if r='patron' and tbl=any(array['payments','vendors','acquisitions','stock_sessions','stock_items','audit','memberships']) then dat:='[]';
 elsif r='patron' and tbl='patrons' then select coalesce(jsonb_agg(to_jsonb(t)),'[]') into dat from app.patrons t where id=p and institution_id=i;
 elsif r='patron' and tbl=any(array['loans','holds','fines']) then execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from app.%I t where institution_id=$1 and patron_id=$2',tbl) into dat using i,p;
 else execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from app.%I t where institution_id=$1',tbl) into dat using i; end if;
 out:=out||jsonb_build_object(tbl,dat); end loop; return out; end$$;

create function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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

-- Defense in depth: no direct table writes or reads from API roles, all RPCs check membership.
revoke all on schema app from public,anon,authenticated;
revoke all on all tables in schema app from public,anon,authenticated;
revoke all on all functions in schema app from public,anon,authenticated;
revoke all on function public.library_bootstrap(),public.library_snapshot(text),public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_bootstrap(),public.library_snapshot(text),public.library_action(text,text,jsonb) to authenticated;
do $$declare t text; begin for t in select tablename from pg_tables where schemaname='app' loop execute format('alter table app.%I enable row level security',t); end loop; end$$;
