-- Module access supplements, and never elevates, existing institution/role checks.
create table app.user_modules(
 institution_id text not null references app.institutions(id),
 user_id uuid not null references auth.users(id) on delete cascade,
 modules text[],revision bigint not null default 1,
 changed_by uuid not null references auth.users(id),changed_at timestamptz not null default now(),
 primary key(institution_id,user_id)
);
alter table app.user_modules enable row level security;
revoke all on app.user_modules from public,anon,authenticated;

create function app.role_modules(r text) returns text[] language sql immutable set search_path='' as $$
 select case when r='accountant' then array['Fines']
 when r='patron' then array['Overview','Catalogue','Circulation','Fines','Search','Holds','Lists']
 when r in ('admin','librarian','assistant','auditor') then
 array['Overview','Catalogue','Patrons','Circulation','Holds','Fines','Acquisitions','Stock verification','Reports','Audit trail','Settings','Search','Authorities','Lists','Serials']
 ||case when r in ('admin','librarian') then array['Book edits'] else '{}'::text[] end
 ||case when r='admin' then array['Permissions'] else '{}'::text[] end
 else '{}'::text[] end
$$;
create function app.effective_modules(i text,u uuid,r text) returns text[] language sql stable security definer set search_path='' as $$
 select case when r='admin' then app.role_modules(r) else array(
 select m from unnest(app.role_modules(r)) m where m=any(coalesce((select modules from app.user_modules where institution_id=i and user_id=u),app.role_modules(r)))) end
$$;
create function app.has_module(i text,m text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(m=any(app.effective_modules(i,auth.uid(),app.role_for(i))),false)
$$;
create function app.require_module(i text,modules text[]) returns void language plpgsql security definer set search_path='' as $$
begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);
 if not exists(select 1 from unnest(modules) m where app.has_module(i,m)) then raise exception 'Access denied: module permission revoked or not assigned';end if;
end$$;

-- Dependencies permit only data required by another assigned module, not its operations.
create function app.dataset_modules(k text) returns text[] language sql immutable set search_path='' as $$
 select case
 when k in ('titles','copies') then array['Overview','Catalogue','Circulation','Holds','Acquisitions','Stock verification','Reports','Search','Authorities','Lists','Serials','Book edits']
 when k='patrons' then array['Patrons','Circulation','Fines','Reports']
 when k in ('loans','active_loans','returned_loans','overdue_loans') then array['Overview','Circulation','Reports']
 when k='holds' then array['Holds']
 when k='fines' then array['Overview','Fines','Circulation','Reports']
 when k='payments' then array['Fines']
 when k='audit' then array['Audit trail']
 when k='memberships' then array['Settings']
 when k in ('vendors','acquisitions','budgets','funds','baskets') then array['Acquisitions']
 when k in ('stock_sessions','stock_items') then array['Stock verification']
 when k in ('authorities','title_authorities') then array['Authorities']
 when k in ('subscriptions','serial_issues') then array['Serials']
 when k in ('reading_lists','list_entries') then array['Lists']
 when k='saved_reports' then array['Reports']
 when k in ('policies','holidays','availability','librarian','course_policies') then array['Settings','Overview','Circulation','Patrons']
 else '{}'::text[] end
$$;
create function app.can_read_dataset(i text,k text) returns boolean language sql stable security definer set search_path='' as $$
 select app.role_for(i)='admin' or exists(select 1 from unnest(app.dataset_modules(k)) m where app.has_module(i,m))
$$;

create function public.library_my_modules(i text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);
 return jsonb_build_object('modules',app.effective_modules(i,auth.uid(),app.role_for(i)),'revision',coalesce((select revision from app.user_modules where institution_id=i and user_id=auth.uid()),0));
end$$;
create function public.library_permissions(i text,q text default '',after_id uuid default null,page_size integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$
declare rows_data jsonb;total bigint;begin
 perform app.require_role(i,array['admin']);
 if page_size is null or page_size not between 1 and 100 or length(coalesce(q,''))>200 then raise exception 'Invalid permission search';end if;
 with users as materialized(
 select m.user_id id,m.role,
 coalesce(nullif(to_jsonb(u)->'raw_user_meta_data'->>'full_name',''),nullif(to_jsonb(u)->'raw_user_meta_data'->>'name',''),s.display_name,p.name,'Name not recorded') name,
 coalesce(to_jsonb(u)->>'email',p.email,'') email,
 app.role_modules(m.role) eligible,app.effective_modules(i,m.user_id,m.role) modules,
 coalesce(x.revision,0) revision,x.modules is not null custom,x.changed_at
 from app.memberships m join auth.users u on u.id=m.user_id
 left join app.library_staff s on s.institution_id=i and s.user_id=m.user_id
 left join app.patrons p on p.institution_id=i and p.id=m.patron_id
 left join app.user_modules x on x.institution_id=i and x.user_id=m.user_id
 where m.institution_id=i and (m.role<>'librarian' or s.user_id is not null)
 and not exists(select 1 from app.library_staff other where other.user_id=m.user_id and other.institution_id<>i)
 ), filtered as materialized(select * from users where coalesce(btrim(q),'')='' or strpos(lower(concat_ws(' ',name,email,role,id)),lower(btrim(q)))>0),
 page as(select * from filtered where after_id is null or id>after_id order by id limit page_size)
 select (select count(*) from filtered),coalesce(jsonb_agg(to_jsonb(page) order by id),'[]') into total,rows_data from page;
 return jsonb_build_object('rows',rows_data,'total',total,'next_id',case when jsonb_array_length(rows_data)=page_size then rows_data->-1->>'id' else null end);
end$$;
create function public.library_set_modules(i text,target uuid,modules text[],expected_revision bigint,reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r text;before_modules text[];after_modules text[];old_revision bigint;new_revision bigint;begin
 perform app.require_role(i,array['admin']);
 if reason is null or length(btrim(reason)) not between 1 and 1000 then raise exception 'Enter a reason for the permission change';end if;
 -- Serialize first-time changes too; stale forms must never overwrite newer assignments.
 perform 1 from app.memberships where institution_id=i and user_id=target for update;
 if not found then raise exception 'User is not assigned to this library';end if;
 select role into r from app.memberships where institution_id=i and user_id=target;
 if r='admin' or exists(select 1 from app.network_admin where user_id=target) then raise exception 'Administrator permissions cannot be revoked';end if;
 if exists(select 1 from app.library_staff where user_id=target and institution_id<>i)
 or (r='librarian' and not exists(select 1 from app.library_staff where user_id=target and institution_id=i)) then raise exception 'User is not assigned to this library';end if;
 if modules is not null and (cardinality(modules)>16 or exists(select 1 from unnest(modules) m where m is null or not(m=any(app.role_modules(r))))) then raise exception 'A module is invalid or unavailable for this role';end if;
 select coalesce((select revision from app.user_modules where institution_id=i and user_id=target),0) into old_revision;
 if expected_revision is distinct from old_revision then raise exception 'Permissions changed since this form opened. Reload the account and try again';end if;
 before_modules:=app.effective_modules(i,target,r);
 insert into app.user_modules(institution_id,user_id,modules,changed_by) values(i,target,case when modules is null then null else array(select distinct m from unnest(modules) m order by m) end,auth.uid())
 on conflict(institution_id,user_id) do update set modules=excluded.modules,revision=app.user_modules.revision+1,changed_by=auth.uid(),changed_at=now() returning revision into new_revision;
 after_modules:=app.effective_modules(i,target,r);
 insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),'module_permissions',jsonb_build_object('user_id',target,'user_name',app.staff_slip_name(target,i),'changed_by_name',app.staff_slip_name(auth.uid(),i),'role',r,'before',before_modules,'after',after_modules,'reason',btrim(reason),'revision',new_revision,'restored_defaults',modules is null));
 return jsonb_build_object('modules',after_modules,'revision',new_revision);
end$$;

-- Check every user mutation at the public dispatcher; keep its OID for recursive imports.
create function app.check_action_module(i text,action text,p jsonb) returns void language plpgsql security definer set search_path='' as $$
declare m text;begin
 if action='waive' then raise exception 'Fine waivers are disabled for everyone. Collect the full fine.';end if;
 if app.role_for(i)='admin' then return;end if;
 if app.role_for(i)='accountant' and action not in ('fine_month_verify','fine_deposit') then raise exception 'Access denied: accountant access is limited to fine verification and deposits';end if;
 if action='availability' then perform app.require_module(i,array['Overview','Settings']);return;end if;
 if action='source_details' then perform app.require_module(i,array['Catalogue','Patrons']);return;end if;
 m:=case
 when action in ('title','copy','book','copy_edit','copy_status','copy_institute','marc_import') then 'Catalogue'
 when action='import' then case when p->>'kind'='books' then 'Catalogue' else 'Patrons' end
 when action in ('patron','reactivate_student','resume_graduation') then 'Patrons'
 when action in ('issue','return','renew') then 'Circulation'
 when action in ('hold','cancel_hold') then 'Holds'
 when action in ('pay','waive','collect_loan_fine','fine_deposit','fine_month_submit','fine_month_verify') then 'Fines'
 when action in ('acquire','vendor','order','receive','cancel_order','budget','fund','basket') then 'Acquisitions'
 when action in ('stock_start','stock_scan','stock_close') then 'Stock verification'
 when action in ('policy','holiday','holiday_import','member','course_policy','assign_librarian','account_email_audit') then 'Settings'
 when action in ('authority','link_authority') then 'Authorities'
 when action in ('reading_list','list_add','list_remove') then 'Lists'
 when action in ('subscription','serial_status') then 'Serials'
 when action='save_report' then 'Reports'
 when action in ('book_edit_request','book_edit_approve','book_edit_reject') then 'Book edits'
 when action='source_details' then case when p->>'kind' in ('students','faculty') then 'Patrons' else 'Catalogue' end
 else null end;
 if m is null then raise exception 'Access denied: action has no module permission';end if;
 perform app.require_module(i,array[m]);
end$$;
do $$declare d text;b text;begin
 d:=pg_get_functiondef('public.library_action(text,text,jsonb)'::regprocedure);
 select prosrc into b from pg_proc where oid='public.library_action(text,text,jsonb)'::regprocedure;
 execute replace(d,b,regexp_replace(b,'\mbegin\M','begin perform app.check_action_module(i,action,p);','i'));
end$$;

-- Restrict read endpoints, including alternate direct APIs and export paths.
do $$declare r record;guard text;b text;begin
 for r in select p.proname,p.prosrc,p.proargnames,pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('library_collection_page','library_records_page','library_circulation_page','library_audit_detail','library_report','library_report_page','library_donation_acknowledgement','library_register_page','library_print_slip','library_fine_quote','library_fines_due','library_fine_month','library_fine_months','library_my_receipts','library_book_edits','library_book_edit_action','library_book_edit_revision','library_invitation_candidates_page','library_login_targets','library_course_policies','library_notifications') loop
  guard:=case
  when r.proname in ('library_collection_page','library_records_page') then 'if not app.can_read_dataset(i,kind) then raise exception ''Access denied: module permission revoked or not assigned'';end if;'
  when r.proname='library_circulation_page' then 'perform app.require_module(i,array[''Circulation'']);'
  when r.proname='library_audit_detail' then 'perform app.require_module(i,array[''Audit trail'']);'
  when r.proname in ('library_report','library_report_page') then 'perform app.require_module(i,array[''Reports'']);'
  when r.proname='library_donation_acknowledgement' then 'perform app.require_module(i,array[''Acquisitions'']);'
  when r.proname in ('library_register_page','library_print_slip') then 'perform app.require_module(i,case when kind in (''collections'',''deposits'',''monthly_draft'') then array[''Fines''] else array[''Acquisitions''] end);'
  when r.proname='library_fine_quote' then 'perform app.require_module(i,array[''Circulation'',''Fines'']);'
  when r.proname='library_fines_due' then 'perform app.require_module(i,array[''Overview'',''Circulation'',''Fines'']);'
  when r.proname in ('library_fine_month','library_my_receipts') then 'perform app.require_module(i,array[''Fines'']);'
  when r.proname='library_fine_months' then 'perform app.require_module(i,array[''Fines'']); if all_libraries and exists(select 1 from app.memberships m where m.user_id=auth.uid() and app.role_for(m.institution_id) in (''admin'',''accountant'') and not app.has_module(m.institution_id,''Fines'')) then raise exception ''Fine permission is required in every included library'';end if;'
  when r.proname='library_book_edit_action' then 'perform app.check_action_module(i,action,p);'
  when r.proname in ('library_book_edits','library_book_edit_revision') then 'perform app.require_module(i,array[''Book edits'']);'
  when r.proname in ('library_invitation_candidates_page','library_login_targets') then 'perform app.require_module(i,array[''Patrons'']);'
  when r.proname='library_course_policies' then 'if not app.can_read_dataset(i,''course_policies'') then raise exception ''Access denied: module permission revoked or not assigned'';end if;'
  when r.proname='library_notifications' then 'perform app.require_role(i,array[''admin'',''librarian'',''assistant'',''accountant'',''auditor'',''patron'']);if not exists(select 1 from unnest(array[''Overview'',''Fines'',''Circulation'']) m where app.has_module(i,m)) then return ''[]''::jsonb;end if;'
  end;
  if r.proname in ('library_collection_page','library_course_policies','library_donation_acknowledgement','library_audit_detail','library_report','library_report_page') then guard:='if app.role_for(i)=''accountant'' then raise exception ''Accountant access is limited to fine accounting'';end if;'||guard;
  elsif r.proname='library_records_page' then guard:='if app.role_for(i)=''accountant'' and kind not in (''fines'',''payments'') then raise exception ''Accountant access is limited to fine accounting'';end if;'||guard;
  elsif r.proname='library_register_page' then guard:='if app.role_for(i)=''accountant'' and kind not in (''collections'',''deposits'') then raise exception ''Accountant access is limited to fine accounting'';end if;'||guard;end if;
  b:=regexp_replace(r.prosrc,'\mbegin\M','begin '||guard,'i');
  if r.proname='library_report_page' then b:=replace(b,'return app.records_page(i,r.dataset','if not app.can_read_dataset(i,r.dataset) then raise exception ''Access denied: report dataset permission revoked'';end if; return app.records_page(i,r.dataset');end if;
  if b=r.prosrc then raise exception 'Unable to guard %',r.proname;end if;
  execute replace(r.def,r.prosrc,b);
 end loop;
end$$;

-- Filter bootstrap datasets too, rather than only hiding navigation.
alter function public.library_workspace(text) rename to library_workspace_pre_modules;
alter function public.library_workspace_pre_modules(text) set schema app;
revoke all on function app.library_workspace_pre_modules(text) from public,anon,authenticated;
create function public.library_workspace(i text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb;k text;readable text[]:='{}';assigned text[];begin
 d:=app.library_workspace_pre_modules(i);assigned:=app.effective_modules(i,auth.uid(),app.role_for(i));
 if d->>'accountant_only'='true' then return d||jsonb_build_object('module_permissions',public.library_my_modules(i),'readable_datasets','[]'::jsonb);end if;
 foreach k in array array['titles','copies','patrons','loans','active_loans','returned_loans','holds','fines','payments','audit','memberships','vendors','acquisitions','stock_sessions','stock_items','authorities','title_authorities','subscriptions','serial_issues','reading_lists','list_entries','budgets','funds','baskets','saved_reports','policies','holidays','availability','course_policies'] loop
  if not(app.dataset_modules(k)&&assigned) then d:=jsonb_set(d,array[k],'[]');d:=d #- array['pages',k];d:=d #- array['counts',k];else readable:=array_append(readable,k);end if;
 end loop;
 if not(app.dataset_modules('loans')&&assigned) then d:=d #- '{counts,overdue}';end if;
 if not(app.dataset_modules('fines')&&assigned) then d:=d #- '{counts,fine_balance}' #- '{counts,fine_paid}' #- '{counts,fine_waived}';end if;
 if not(app.dataset_modules('titles')&&assigned) then d:=d #- '{counts,available_copies}';end if;
 if not(app.dataset_modules('librarian')&&assigned) then d:=d-'librarian';end if;
 return d||jsonb_build_object('module_permissions',public.library_my_modules(i),'readable_datasets',readable);
end$$;
-- The old snapshot must not append unrestricted datasets to the filtered workspace.
create or replace function public.library_snapshot(i text) returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb;begin
 if app.role_for(i)='accountant' then raise exception 'Accountant access is limited to fine accounting';end if;
 d:=public.library_workspace(i);
 if app.can_read_dataset(i,'titles') then
  return d||jsonb_build_object('titles',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (select * from app.titles where institution_id=i order by id limit 200) t),'copies',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (select * from app.copies where institution_id=i order by id limit 200) t));
 end if;
 return d;
end$$;

-- All helpers remain private. Only explicitly authenticated APIs are exposed.
revoke all on function app.role_modules(text),app.effective_modules(text,uuid,text),app.has_module(text,text),app.require_module(text,text[]),app.dataset_modules(text),app.can_read_dataset(text,text),app.check_action_module(text,text,jsonb) from public,anon,authenticated;
revoke all on function public.library_my_modules(text),public.library_permissions(text,text,uuid,integer),public.library_set_modules(text,uuid,text[],bigint,text),public.library_workspace(text) from public,anon;
grant execute on function public.library_my_modules(text),public.library_permissions(text,text,uuid,integer),public.library_set_modules(text,uuid,text[],bigint,text),public.library_workspace(text) to authenticated;
