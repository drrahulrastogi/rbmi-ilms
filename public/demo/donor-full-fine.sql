-- One permanent acknowledgement number per donor, shared by every donated title.
alter table app.donors add column acknowledgement_no text unique;
update app.donors d set acknowledgement_no=app.new_slip_number(d.institution_id,'DON',coalesce((select min(received_at) from app.acquisitions a where a.donor_id=d.id),app.today()));
alter table app.donors alter column acknowledgement_no set not null;
create function app.donor_acknowledgement_stamp() returns trigger language plpgsql set search_path='' as $$
begin
 if TG_OP='UPDATE' then new.acknowledgement_no:=old.acknowledgement_no;
 else new.acknowledgement_no:=app.new_slip_number(new.institution_id,'DON',app.today());end if;
 return new;
end$$;
revoke all on function app.donor_acknowledgement_stamp() from public,anon,authenticated;
create trigger donor_acknowledgement_stamp before insert or update on app.donors for each row execute function app.donor_acknowledgement_stamp();
create index acquisitions_donor_acknowledgement on app.acquisitions(institution_id,donor_id,received_at,id) where source='donation' and status='received';
create function public.library_donation_acknowledgement(i text,acquisition_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare donor app.donors;items jsonb;begin
 perform app.require_role(i,array['admin','librarian','accountant','auditor']);
 select d.* into donor from app.donors d join app.acquisitions a on a.donor_id=d.id and a.institution_id=d.institution_id
 where a.id=acquisition_id and a.institution_id=i and a.source='donation' and a.status='received';
 if not found then raise exception 'Received donation not found in this library';end if;
 select jsonb_agg(jsonb_build_object('title',t.title,'author',t.author,'institute',a.institute,'received_at',a.received_at,
 'quantity',a.quantity,'value',a.quantity*a.unit_price,'recorded_by_name',a.recorded_by_name) order by a.received_at,a.slip_no,a.id)
 into items from app.acquisitions a join app.titles t on t.id=a.title_id
 where a.institution_id=i and a.donor_id=donor.id and a.source='donation' and a.status='received';
 return jsonb_build_object('donor_name',donor.name,'donor_contact',donor.contact,'slip_no',donor.acknowledgement_no,'books',items,'as_of',app.today());
end$$;
revoke all on function public.library_donation_acknowledgement(text,uuid) from public,anon;
grant execute on function public.library_donation_acknowledgement(text,uuid) to authenticated;

-- Round the remaining payable balance up to whole rupees. Preserve historic receipts.
create function app.loan_fine_quote_pre_whole(l app.loans) returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('loan_id',l.id,'patron_id',l.patron_id,'returned',l.returned,'due',l.due,
 'title',coalesce(l.issue_title,t.title),'accession',coalesce(l.issue_accession,c.accession),'patron_name',p.name,'patron_code',p.code,
 'fine_id',f.id,'amount',greatest(coalesce(f.amount,0),app.fine_for(l.institution_id,l.due,coalesce(l.returned,app.today()),l.policy)),
 'paid',coalesce(f.paid,0),'waived',coalesce(f.waived,0),
 'balance',greatest(coalesce(f.amount,0),app.fine_for(l.institution_id,l.due,coalesce(l.returned,app.today()),l.policy))-coalesce(f.paid,0)-coalesce(f.waived,0),'as_of',app.today(),'fine_starts',case when l.returned is null or l.returned>=s.start_date then s.start_date else null end)
 from app.patrons p join app.copies c on c.id=l.copy_id join app.titles t on t.id=c.title_id
 left join app.fines f on f.loan_id=l.id cross join lateral(select app.fine_start_date(l.institution_id,l.due,l.policy) as start_date) s where p.id=l.patron_id;
$$;

create or replace function app.loan_fine_quote(l app.loans) returns jsonb language sql stable set search_path='' as $$
 select q||jsonb_build_object('balance',ceil(greatest((q->>'balance')::numeric,0)),
 'amount',(q->>'paid')::numeric+(q->>'waived')::numeric+ceil(greatest((q->>'balance')::numeric,0)))
 from (select app.loan_fine_quote_pre_whole(l) q) x;
$$;
revoke all on function app.loan_fine_quote_pre_whole(app.loans),app.loan_fine_quote(app.loans) from public,anon,authenticated;
alter function public.library_action(text,text,jsonb) rename to library_action_pre_full_fine;
alter function public.library_action_pre_full_fine(text,text,jsonb) set schema app;
revoke all on function app.library_action_pre_full_fine(text,text,jsonb) from public,anon,authenticated;
create function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare l app.loans;f app.fines;pay app.payments;amt numeric;q jsonb;begin
 if action not in ('pay','collect_loan_fine') then return app.library_action_pre_full_fine(i,action,p);end if;
 perform app.require_role(i,array['admin','librarian']);
 perform 1 from app.institutions where id=i for update;
 -- A retried successful collection must remain safe after the balance becomes zero.
 select * into pay from app.payments where institution_id=i and request_key=nullif(p->>'request_key','')::uuid;
 if found then
  if pay.kind<>'payment' or not exists(select 1 from app.fines x where x.id=pay.fine_id and x.institution_id=i
   and ((action='pay' and x.id=(p->>'id')::uuid) or (action='collect_loan_fine' and x.loan_id=(p->>'id')::uuid))) then raise exception 'Receipt belongs to another fine';end if;
  return jsonb_build_object('id',pay.id,'receipt',pay.slip_no,'slip_no',pay.slip_no,'amount',pay.amount,'actor',pay.actor,'collected_on',pay.collected_on,'replayed',true);
 end if;
 if action='pay' and exists(select 1 from app.fine_months where institution_id=i and month=date_trunc('month',coalesce(nullif(p->>'collected_on','')::date,app.today()))::date) then raise exception 'This collection month is submitted; backdated payments are locked';end if;
 if action='collect_loan_fine' then
  select * into l from app.loans where id=(p->>'id')::uuid and institution_id=i for update;
  if not found then raise exception 'Loan not found in this library';end if;
  if l.returned is not null then raise exception 'Loan already returned';end if;
  q:=app.loan_fine_quote(l);amt:=(q->>'balance')::numeric;
 else
  select * into f from app.fines where id=(p->>'id')::uuid and institution_id=i for update;
  if not found then raise exception 'Fine not found';end if;
  select * into l from app.loans where id=f.loan_id;
  if l.returned is null then q:=app.loan_fine_quote(l);amt:=(q->>'balance')::numeric;
  else amt:=ceil(greatest(f.amount-f.paid-f.waived,0));end if;
 end if;
 if amt<=0 then raise exception 'No fine is payable';end if;
 if p ? 'amount' and (nullif(p->>'amount','')::numeric is distinct from amt) then raise exception 'Invalid payment amount: collect the full system-calculated fine of INR %; partial or edited amounts are not permitted',amt;end if;
 if action='pay' and l.returned is not null then
  update app.fines set amount=paid+waived+amt where id=f.id;
 end if;
 return app.library_action_pre_full_fine(i,action,p||jsonb_build_object('amount',amt));
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;
