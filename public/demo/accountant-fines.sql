-- Accountants receive only the fine workspace, without catalogue or patron datasets.
alter function public.library_workspace(text) rename to library_workspace_pre_accountant;
alter function public.library_workspace_pre_accountant(text) set schema app;
revoke all on function app.library_workspace_pre_accountant(text) from public,anon,authenticated;
create function public.library_workspace(i text) returns jsonb language plpgsql security definer set search_path='' as $$
declare lib jsonb;begin
 if app.role_for(i)<>'accountant' then return app.library_workspace_pre_accountant(i);end if;
 perform app.require_role(i,array['accountant']);
 select to_jsonb(x) into lib from app.institutions x where id=i;
 return jsonb_build_object('library',lib,'accountant_only',true,'counts','{}'::jsonb);
end$$;
revoke all on function public.library_workspace(text) from public,anon;
grant execute on function public.library_workspace(text) to authenticated;

alter function public.library_action(text,text,jsonb) rename to library_action_pre_accountant;
alter function public.library_action_pre_accountant(text,text,jsonb) set schema app;
revoke all on function app.library_action_pre_accountant(text,text,jsonb) from public,anon,authenticated;
create function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if action='waive' then raise exception 'Fine waivers are disabled for everyone. Collect the full fine.';end if;
 if app.role_for(i)='accountant' and action not in ('fine_month_verify','fine_deposit') then raise exception 'Access denied: accountant access is limited to fine verification and deposits';end if;
 return app.library_action_pre_accountant(i,action,p);
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;

-- Guard existing RPCs in place so their signatures, ownership and grants stay intact.
do $$declare r record;guard text;body text;begin
 for r in select p.oid,p.proname,p.prosrc,p.proargnames,pg_get_functiondef(p.oid) def
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('library_catalogue','library_catalogue_search','library_circulation_page',
 'library_collection_page','library_course_policies','library_donation_acknowledgement','library_audit_detail',
 'library_institute_copies_page','library_institute_titles_page','library_snapshot','library_report','library_report_page',
 'library_records_page','library_register_page','library_print_slip') loop
  if r.proname='library_records_page' then guard:=' and kind not in (''fines'',''payments'')';
  elsif r.proname='library_register_page' then guard:=' and kind not in (''collections'',''deposits'')';
  elsif r.proname='library_print_slip' then guard:=' and kind not in (''collections'',''deposits'',''monthly_draft'')';
  else guard:='';end if;
  body:=regexp_replace(r.prosrc,'\mbegin\M',format('begin if app.role_for(%I)=''accountant''%s then raise exception ''Accountant access is limited to fine accounting'';end if;',r.proargnames[1],guard),'i');
  if body=r.prosrc then raise exception 'Unable to restrict RPC %',r.proname;end if;
  execute replace(r.def,r.prosrc,body);
 end loop;
end$$;

create function public.library_fine_months(i text,from_month date,to_month date,all_libraries boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare first_month date:=date_trunc('month',from_month)::date;last_month date:=date_trunc('month',to_month)::date;rows_data jsonb;r record;begin
 perform app.require_role(i,array['admin','librarian','accountant','auditor']);
 if first_month is null or last_month is null or first_month>last_month or first_month<'1900-01-01'::date or last_month>app.today()
 or last_month>=first_month+interval '120 months' then raise exception 'Choose a valid period of at most 120 months';end if;
 if all_libraries and app.role_for(i) not in ('admin','accountant') then raise exception 'Only Accounts or admin can consolidate assigned libraries';end if;
 if all_libraries then
  for r in select institution_id from app.memberships where user_id=auth.uid() and role in ('admin','accountant') and app.role_for(institution_id) in ('admin','accountant') loop
   perform app.require_role(r.institution_id,array['admin','accountant']);
  end loop;
 end if;
 with libraries as(select x.id,x.name from app.institutions x where x.active and (
  (not all_libraries and x.id=i) or (all_libraries and exists(select 1 from app.memberships m where m.institution_id=x.id and m.user_id=auth.uid() and m.role in ('admin','accountant') and app.role_for(x.id) in ('admin','accountant'))))),
 receipts as(select p.institution_id,date_trunc('month',p.collected_on)::date as month,count(*) as receipt_count,sum(p.amount) total,
  coalesce(sum(p.amount) filter(where d.payment_id is not null),0) deposited
  from app.payments p join libraries lib on lib.id=p.institution_id left join app.fine_deposit_items d on d.payment_id=p.id
  where p.kind='payment' and p.collected_on>=first_month and p.collected_on<last_month+interval '1 month'
  group by p.institution_id,date_trunc('month',p.collected_on)::date),
 months as(select institution_id,month from receipts union select f.institution_id,f.month from app.fine_months f join libraries lib on lib.id=f.institution_id where f.month between first_month and last_month),
 report as(select m.institution_id,lib.name library_name,m.month,coalesce(f.total,p.total,0) total,coalesce(p.deposited,0) deposited,
  coalesce(f.total,p.total,0)-coalesce(p.deposited,0) pending,coalesce(jsonb_array_length(f.details),p.receipt_count,0) receipts,
  case when f.verified_at is not null then 'verified' when f.id is not null then 'submitted' else 'draft' end status,
  f.slip_no,f.submitted_by_name,f.submitted_at,f.verified_by_name,f.verified_at,f.verification_reference
  from months m join libraries lib on lib.id=m.institution_id left join receipts p using(institution_id,month)
  left join app.fine_months f using(institution_id,month))
 select coalesce(jsonb_agg(to_jsonb(report) order by month,institution_id),'[]') into rows_data from report;
 return jsonb_build_object('rows',rows_data,'from_month',first_month,'to_month',last_month);
end$$;
revoke all on function public.library_fine_months(text,date,date,boolean) from public,anon;
grant execute on function public.library_fine_months(text,date,date,boolean) to authenticated;
