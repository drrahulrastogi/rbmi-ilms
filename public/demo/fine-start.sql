-- First day on which the existing fine formula produces a positive amount.
create function app.fine_start_date(i text,due date,pol jsonb) returns date language plpgsql stable set search_path='' as $$
declare charge_day date:=due;eligible integer:=0;grace integer:=coalesce((pol->>'grace_days')::integer,0);begin
 if due is null or coalesce((pol->>'fine_rate')::numeric,0)<=0 or coalesce((pol->>'fine_cap')::numeric,0)<=0 then return null;end if;
 loop
  charge_day:=charge_day+1;
  if (not coalesce((pol->>'exclude_weekends')::boolean,false) or extract(isodow from charge_day)<=5)
   and not exists(select 1 from app.holidays where institution_id=i and day=charge_day)
   and not exists(select 1 from app.library_availability where institution_id=i and day=charge_day and not available) then
   eligible:=eligible+1;if eligible>grace then return charge_day;end if;
  end if;
 end loop;
end$$;
revoke all on function app.fine_start_date(text,date,jsonb) from public,anon,authenticated;

create or replace function app.loan_fine_quote(l app.loans) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('loan_id',l.id,'patron_id',l.patron_id,'returned',l.returned,'due',l.due,
 'title',coalesce(l.issue_title,t.title),'accession',coalesce(l.issue_accession,c.accession),'patron_name',p.name,'patron_code',p.code,
 'fine_id',f.id,'amount',greatest(coalesce(f.amount,0),app.fine_for(l.institution_id,l.due,coalesce(l.returned,app.today()),l.policy)),
 'paid',coalesce(f.paid,0),'waived',coalesce(f.waived,0),
 'balance',greatest(coalesce(f.amount,0),app.fine_for(l.institution_id,l.due,coalesce(l.returned,app.today()),l.policy))-coalesce(f.paid,0)-coalesce(f.waived,0),'as_of',app.today(),'fine_starts',case when l.returned is null or l.returned>=s.start_date then s.start_date else null end)
 from app.patrons p join app.copies c on c.id=l.copy_id join app.titles t on t.id=c.title_id
 left join app.fines f on f.loan_id=l.id cross join lateral(select app.fine_start_date(l.institution_id,l.due,l.policy) as start_date) s where p.id=l.patron_id;
$$;
revoke all on function app.loan_fine_quote(app.loans) from public,anon,authenticated;

create or replace function public.library_circulation_page(i text,after_id text default null,page_size integer default 50,q text default '',from_day date default null,to_day date default null,date_field text default 'issued',loan_status text default 'all') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;rows_data jsonb;begin
 result:=app.library_circulation_pre_fines(i,after_id,page_size,q,from_day,to_day,date_field,loan_status);
 select coalesce(jsonb_agg(x.value||jsonb_build_object('_fine',quote->'amount','_fine_paid',quote->'paid','_fine_balance',quote->'balance','_fine_starts',quote->'fine_starts') order by x.ord),'[]') into rows_data
 from jsonb_array_elements(result->'rows') with ordinality x(value,ord) join app.loans l on l.id=(x.value->>'id')::uuid cross join lateral(select app.loan_fine_quote(l) quote) f;
 return result||jsonb_build_object('rows',rows_data);
end$$;
