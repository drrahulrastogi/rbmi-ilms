create index fines_borrower_receipts on app.fines(institution_id,patron_id,id);
create index payments_borrower_receipts on app.payments(institution_id,fine_id,id) where kind='payment';
-- Borrowers can reprint their own posted payment receipts without finance-register access.
create function public.library_my_receipts(i text,after_id uuid default null,page_size integer default 100) returns jsonb
language plpgsql security definer set search_path='' as $$
declare own uuid;rows_data jsonb;total bigint;begin
 perform app.require_role(i,array['patron']);perform app.read_budget('records');
 if page_size is null or page_size not between 1 and 200 then raise exception 'Invalid receipt page';end if;
 select m.patron_id into own from app.memberships m join app.patrons p on p.id=m.patron_id and p.institution_id=i
  where m.user_id=auth.uid() and m.institution_id=i;
 if own is null then raise exception 'Linked borrower account required';end if;
 with receipts as materialized (
  select x.id,x.slip_no,x.collected_on,x.amount,x.payment_method,x.reason,x.actor_name,p.name patron_name,p.code patron_code
  from app.payments x join app.fines f on f.id=x.fine_id and f.institution_id=i
   join app.patrons p on p.id=f.patron_id and p.institution_id=i
  where x.institution_id=i and f.patron_id=own and x.kind='payment'
 ), paged as(select * from receipts where after_id is null or id>after_id order by id limit page_size)
 select (select coalesce(jsonb_agg(to_jsonb(p) order by id),'[]') from paged p),(select count(*) from receipts) into rows_data,total;
 return jsonb_build_object('rows',rows_data,'total',total,'next_id',case when jsonb_array_length(rows_data)=page_size then rows_data->-1->>'id' else null end);
end$$;
revoke all on function public.library_my_receipts(text,uuid,integer) from public,anon;
grant execute on function public.library_my_receipts(text,uuid,integer) to authenticated;
notify pgrst,'reload schema';
