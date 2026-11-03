-- Assignment choices are independent of role defaults. Mutation roles stay unchanged.
create function app.assignable_modules(r text) returns text[] language sql immutable set search_path='' as $$
 select case when r in ('admin','librarian','assistant','accountant','auditor','patron') then array_remove(app.role_modules('admin'),'Permissions') else '{}'::text[] end
$$;
create or replace function app.effective_modules(i text,u uuid,r text) returns text[] language sql stable security definer set search_path='' as $$
 select case when r='admin' then app.role_modules(r) else array(
 select m from unnest(app.assignable_modules(r)) m where m=any(coalesce((select modules from app.user_modules where institution_id=i and user_id=u),app.role_modules(r)))) end
$$;
create function app.module_read_role(i text) returns text language sql stable security definer set search_path='' as $$
 select case when app.role_for(i) in ('accountant','assistant','auditor','patron')
 and exists(select 1 from app.user_modules x where x.institution_id=i and x.user_id=auth.uid() and x.modules is not null)
 and (app.role_for(i)<>'patron' or exists(select 1 from app.memberships m join app.patrons p on p.id=m.patron_id and p.institution_id=i where m.institution_id=i and m.user_id=auth.uid() and p.category<>'student'))
 then 'librarian' else app.role_for(i) end
$$;
create function app.require_read_role(i text,roles text[]) returns void language plpgsql security definer set search_path='' as $$begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);
 if app.module_read_role(i) is null or not(app.module_read_role(i)=any(roles)) then raise exception 'Access denied for this institution/action';end if;
end$$;
create function app.accountant_fine_only(i text) returns boolean language sql stable security definer set search_path='' as $$
 select app.role_for(i)='accountant' and not exists(select 1 from unnest(app.effective_modules(i,auth.uid(),'accountant')) m where m<>'Fines')
$$;
do $$declare d text;b text;begin
 select pg_get_functiondef(oid),prosrc into d,b from pg_proc where oid='public.library_permissions(text,text,uuid,integer)'::regprocedure;
 execute replace(d,b,replace(b,'app.role_modules(m.role) eligible','app.role_modules(m.role) defaults,app.role_modules(''admin'') all_modules,app.assignable_modules(m.role) eligible'));
 select pg_get_functiondef(oid),prosrc into d,b from pg_proc where oid='public.library_set_modules(text,uuid,text[],bigint,text)'::regprocedure;
 execute replace(d,b,replace(b,'any(app.role_modules(r))','any(app.assignable_modules(r))'));
end$$;
-- Expand only read endpoints. All module checks, library checks and write-role rules remain.
do $$declare r record;b text;begin
 for r in select p.proname,p.prosrc,pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='public' and p.proname in ('library_snapshot','library_collection_page','library_records_page','library_circulation_page','library_audit_detail','library_report','library_report_page','library_register_page','library_print_slip','library_donation_acknowledgement','library_fine_quote','library_fines_due','library_fine_month','library_fine_months','library_book_edits','library_book_edit_revision','library_course_policies','library_catalogue','library_catalogue_search','library_institute_copies_page','library_institute_titles_page'))
 or (n.nspname='app' and p.proname in ('records_page','library_workspace_pre_accrued','library_workspace_pre_accountant','library_circulation_pre_fines','library_register_pre_names','library_fine_month_pre_names')) loop
  b:=r.prosrc;
  b:=regexp_replace(b,'app[.]role_for\(([^)]+)\)=''accountant''','app.role_for(\1)=''accountant'' and app.accountant_fine_only(\1)','g');
  if r.proname not in ('library_fine_months','library_catalogue','library_catalogue_search') then
   b:=replace(b,'app.role_for(i)=''patron''','app.module_read_role(i)=''patron''');
   b:=replace(b,'app.role_for(i)<>''patron''','app.module_read_role(i)<>''patron''');
   b:=replace(b,'r:=app.role_for(i)','r:=app.module_read_role(i)');
  end if;
  b:=replace(b,'perform app.require_role(i,','perform app.require_read_role(i,');
  if b<>r.prosrc then execute replace(r.def,r.prosrc,b);end if;
 end loop;
 select p.proname,p.prosrc,pg_get_functiondef(p.oid) def into r from pg_proc p where p.oid='app.library_workspace_pre_modules(text)'::regprocedure;
 b:=replace(r.prosrc,'if app.role_for(i)<>''accountant'' then','if app.role_for(i)<>''accountant'' or not app.accountant_fine_only(i) then');
 execute replace(r.def,r.prosrc,b);
 select p.proname,p.prosrc,pg_get_functiondef(p.oid) def into r from pg_proc p where p.oid='public.library_workspace(text)'::regprocedure;
 b:=replace(r.prosrc,'d:=app.library_workspace_pre_modules(i);','d:=app.library_workspace_pre_modules(i);d:=d||jsonb_build_object(''module_staff_view'',app.module_read_role(i)<>''patron'');');
 execute replace(r.def,r.prosrc,b);
end$$;
revoke all on function app.assignable_modules(text),app.module_read_role(text),app.require_read_role(text,text[]),app.accountant_fine_only(text) from public,anon,authenticated;
