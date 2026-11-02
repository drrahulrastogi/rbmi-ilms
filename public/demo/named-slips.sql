create sequence app.slip_sequence;
revoke all on sequence app.slip_sequence from public,anon,authenticated;
create function app.new_slip_number(i text,kind text,day date) returns text language plpgsql volatile set search_path='' as $$
declare serial text:=nextval('app.slip_sequence')::text;begin
 return i||'-'||kind||'-'||to_char(coalesce(day,app.today()),'YYYY')||'-'||lpad(serial,greatest(6,length(serial)),'0');
end$$;
create function app.staff_slip_name(actor uuid,i text) returns text language sql stable set search_path='' as $$
 select coalesce(app.loan_issuer_display_name(actor,i),'Name not recorded');
$$;
revoke all on function app.new_slip_number(text,text,date),app.staff_slip_name(uuid,text) from public,anon,authenticated;

alter table app.payments add column actor_name text,add column slip_no text unique;
alter table app.fine_deposits add column actor_name text,add column slip_no text unique;
alter table app.acquisitions add column recorded_by uuid references auth.users,add column recorded_by_name text,add column slip_no text unique;
alter table app.loans add column issue_slip_no text unique,add column return_slip_no text unique,add column returned_by_name text;
alter table app.fine_months add column slip_no text unique,add column submitted_by_name text,add column verified_by_name text;
update app.payments set actor_name=app.staff_slip_name(actor,institution_id),slip_no=app.new_slip_number(institution_id,case when kind='payment' then 'F' else 'W' end,collected_on);
update app.fine_deposits set actor_name=app.staff_slip_name(actor,institution_id),slip_no=app.new_slip_number(institution_id,'DEP',deposited_on);
update app.acquisitions set recorded_by_name=app.staff_slip_name(recorded_by,institution_id),slip_no=app.new_slip_number(institution_id,case when source='donation' then 'DON' else 'ACQ' end,ordered_at);
update app.loans set issue_slip_no=app.new_slip_number(institution_id,'ISS',issued),
 return_slip_no=case when returned is not null then app.new_slip_number(institution_id,'RET',returned) end,
 returned_by_name=case when returned is not null then app.staff_slip_name(returned_by,institution_id) end;
update app.fine_months set slip_no=app.new_slip_number(institution_id,'MONTH',month),submitted_by_name=app.staff_slip_name(submitted_by,institution_id),
 verified_by_name=case when verified_by is not null then app.staff_slip_name(verified_by,institution_id) end;
alter table app.payments alter column slip_no set not null;
alter table app.fine_deposits alter column slip_no set not null;
alter table app.acquisitions alter column slip_no set not null;
alter table app.loans alter column issue_slip_no set not null;
alter table app.fine_months alter column slip_no set not null;

create function app.stamp_named_slip() returns trigger language plpgsql security definer set search_path='' as $$begin
 if TG_TABLE_NAME='payments' then
  if TG_OP='INSERT' then new.actor_name:=app.staff_slip_name(new.actor,new.institution_id);new.slip_no:=app.new_slip_number(new.institution_id,case when new.kind='payment' then 'F' else 'W' end,new.collected_on);
  else new.actor_name:=old.actor_name;new.slip_no:=old.slip_no;end if;
 elsif TG_TABLE_NAME='fine_deposits' then
  if TG_OP='INSERT' then new.actor_name:=app.staff_slip_name(new.actor,new.institution_id);new.slip_no:=app.new_slip_number(new.institution_id,'DEP',new.deposited_on);
  else new.actor_name:=old.actor_name;new.slip_no:=old.slip_no;end if;
 elsif TG_TABLE_NAME='acquisitions' then
  if TG_OP='INSERT' then new.recorded_by:=auth.uid();new.recorded_by_name:=app.staff_slip_name(new.recorded_by,new.institution_id);new.slip_no:=app.new_slip_number(new.institution_id,case when new.source='donation' then 'DON' else 'ACQ' end,new.ordered_at);
  else new.recorded_by:=old.recorded_by;new.recorded_by_name:=old.recorded_by_name;new.slip_no:=old.slip_no;end if;
 elsif TG_TABLE_NAME='loans' then
  if TG_OP='INSERT' then new.issue_slip_no:=app.new_slip_number(new.institution_id,'ISS',new.issued);new.return_slip_no:=case when new.returned is not null then app.new_slip_number(new.institution_id,'RET',new.returned) end;new.returned_by_name:=case when new.returned is not null then app.staff_slip_name(coalesce(new.returned_by,auth.uid()),new.institution_id) end;
  else
   new.issue_slip_no:=old.issue_slip_no;new.return_slip_no:=old.return_slip_no;new.returned_by_name:=old.returned_by_name;
   if old.returned is null and new.returned is not null then new.return_slip_no:=app.new_slip_number(new.institution_id,'RET',new.returned);new.returned_by_name:=app.staff_slip_name(new.returned_by,new.institution_id);end if;
  end if;
 elsif TG_TABLE_NAME='fine_months' then
  if TG_OP='INSERT' then new.slip_no:=app.new_slip_number(new.institution_id,'MONTH',new.month);new.submitted_by_name:=app.staff_slip_name(new.submitted_by,new.institution_id);new.verified_by_name:=null;
  else
   new.slip_no:=old.slip_no;new.submitted_by_name:=old.submitted_by_name;new.verified_by_name:=old.verified_by_name;
   if old.verified_by is null and new.verified_by is not null then new.verified_by_name:=app.staff_slip_name(new.verified_by,new.institution_id);end if;
  end if;
 end if;
 return new;
end$$;
revoke all on function app.stamp_named_slip() from public,anon,authenticated;
create trigger zzz_named_slip before insert or update on app.payments for each row execute function app.stamp_named_slip();
create trigger zzz_named_slip before insert or update on app.fine_deposits for each row execute function app.stamp_named_slip();
create trigger zzz_named_slip before insert or update on app.acquisitions for each row execute function app.stamp_named_slip();
create trigger zzz_named_slip before insert or update on app.loans for each row execute function app.stamp_named_slip();
create trigger zzz_named_slip before insert or update on app.fine_months for each row execute function app.stamp_named_slip();

-- Existing financial APIs already return row columns, including the stored name/number.
-- Preserve frozen monthly amounts and borrower names while enriching legacy receipt references.
alter function public.library_fine_month(text,date,integer,integer) rename to library_fine_month_pre_names;
alter function public.library_fine_month_pre_names(text,date,integer,integer) set schema app;
revoke all on function app.library_fine_month_pre_names(text,date,integer,integer) from public,anon,authenticated;
create function public.library_fine_month(i text,month date,page_start integer default 0,page_size integer default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;s app.fine_months;rows_data jsonb;begin
 r:=app.library_fine_month_pre_names(i,month,page_start,page_size);
 select * into s from app.fine_months where institution_id=i and fine_months.month=date_trunc('month',library_fine_month.month)::date;
 select coalesce(jsonb_agg(x.value||jsonb_build_object('receipt',p.slip_no,'slip_no',p.slip_no,'actor_name',p.actor_name) order by x.ord),'[]') into rows_data
 from jsonb_array_elements(r->'rows') with ordinality x(value,ord) join app.payments p on p.id=(x.value->>'id')::uuid and p.institution_id=i;
 return r||jsonb_build_object('rows',rows_data,'slip_no',s.slip_no,'submitted_by_name',s.submitted_by_name,'verified_by_name',s.verified_by_name);
end$$;
revoke all on function public.library_fine_month(text,date,integer,integer) from public,anon;
grant execute on function public.library_fine_month(text,date,integer,integer) to authenticated;

-- Assign auditable numbers to printable register/list exports as well.
create table app.print_slips(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,
 slip_no text not null unique,kind text not null,filters jsonb not null,actor uuid not null references auth.users,actor_name text not null,
 created_at timestamptz not null default now(),request_key uuid not null unique);
alter table app.print_slips enable row level security;
revoke all on app.print_slips from public,anon,authenticated;
create function public.library_print_slip(i text,kind text,filters jsonb,request_key uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s app.print_slips;begin
 perform app.require_role(i,array['admin','librarian','accountant','auditor']);
 if kind is null or kind not in ('collections','deposits','acquisitions','monthly_draft') or filters is null or jsonb_typeof(filters)<>'object' or pg_column_size(filters)>4000 or request_key is null then raise exception 'Invalid list slip';end if;
 insert into app.print_slips(institution_id,slip_no,kind,filters,actor,actor_name,request_key)
 values(i,app.new_slip_number(i,'LIST',app.today()),kind,filters,auth.uid(),app.staff_slip_name(auth.uid(),i),request_key)
 on conflict on constraint print_slips_request_key_key do nothing;
 select * into s from app.print_slips where print_slips.request_key=library_print_slip.request_key and institution_id=i;
 if not found then raise exception 'Slip unavailable';end if;
 if s.kind<>kind or s.filters<>filters then raise exception 'Slip request does not match';end if;
 return jsonb_build_object('slip_no',s.slip_no,'actor_name',s.actor_name,'created_at',s.created_at);
end$$;
revoke all on function public.library_print_slip(text,text,jsonb,uuid) from public,anon;
grant execute on function public.library_print_slip(text,text,jsonb,uuid) to authenticated;


alter function public.library_register_page(text,text,date,date,text,uuid,integer) rename to library_register_pre_names;
alter function public.library_register_pre_names(text,text,date,date,text,uuid,integer) set schema app;
revoke all on function app.library_register_pre_names(text,text,date,date,text,uuid,integer) from public,anon,authenticated;
create function public.library_register_page(i text,kind text,from_day date default null,to_day date default null,q text default '',after_id uuid default null,page_size integer default 100)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;rows_data jsonb;begin
 result:=app.library_register_pre_names(i,kind,from_day,to_day,q,after_id,page_size);
 select coalesce(jsonb_agg(x.value||case when kind='collections' then jsonb_build_object('receipt',x.value->>'slip_no')
 when kind='deposits' then jsonb_build_object('payment_receipts',(select coalesce(jsonb_agg(p.slip_no order by p.slip_no),'[]') from app.fine_deposit_items di join app.payments p on p.id=di.payment_id where di.deposit_id=(x.value->>'id')::uuid)) else '{}'::jsonb end order by x.ord),'[]') into rows_data
 from jsonb_array_elements(result->'rows') with ordinality x(value,ord);
 return result||jsonb_build_object('rows',rows_data);
end$$;
revoke all on function public.library_register_page(text,text,date,date,text,uuid,integer) from public,anon;
grant execute on function public.library_register_page(text,text,date,date,text,uuid,integer) to authenticated;
