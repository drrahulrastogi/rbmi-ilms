-- Unreturned books precede returned books across all pages and exports.
-- Keep the existing UUID cursor and role/library/borrower filters.
create or replace function app.library_circulation_pre_fines(i text,after_id text default null,page_size integer default 50,q text default '',from_day date default null,to_day date default null,date_field text default 'issued',loan_status text default 'all') returns jsonb language plpgsql security definer set search_path='' as $$
declare r text;own uuid;rows jsonb;total bigint;begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);perform app.read_budget('records');
 r:=app.role_for(i);select patron_id into own from app.memberships where user_id=auth.uid() and institution_id=i;
 if page_size is null or page_size<1 or page_size>1000 or length(coalesce(q,''))>200
  or date_field is null or date_field not in ('issued','due','returned') or loan_status is null or loan_status not in ('all','active','returned')
  or (from_day is not null and to_day is not null and from_day>to_day) then raise exception 'Invalid circulation filters';end if;
 with filtered as materialized (
  select l.id,(l.returned is not null)::integer as return_rank,to_jsonb(l)||jsonb_build_object('_title',coalesce(nullif(l.issue_title,''),t.title),'_barcode',coalesce(nullif(l.issue_barcode,''),c.barcode),
   '_accession',coalesce(nullif(l.issue_accession,''),c.accession),'_patron_name',p.name,'_patron_code',p.code,
   '_fine',(select coalesce(sum(f.amount),0) from app.fines f where f.loan_id=l.id and f.institution_id=i)) as record
  from app.loans l left join app.copies c on c.id=l.copy_id and c.institution_id=i
   left join app.titles t on t.id=c.title_id and t.institution_id=i left join app.patrons p on p.id=l.patron_id and p.institution_id=i
  where l.institution_id=i and (r<>'patron' or l.patron_id=own)
   and (loan_status='all' or loan_status='active' and l.returned is null or loan_status='returned' and l.returned is not null)
   and (from_day is null or (case date_field when 'due' then l.due when 'returned' then l.returned else l.issued end)>=from_day)
   and (to_day is null or (case date_field when 'due' then l.due when 'returned' then l.returned else l.issued end)<=to_day)
   and (coalesce(btrim(q),'')='' or strpos(lower(concat_ws(' ',l.issue_title,t.title,l.issue_barcode,c.barcode,l.issue_accession,c.accession,p.name,p.code)),lower(btrim(q)))>0)
 ), page as (select * from filtered where after_id is null or (return_rank,id)>(
   coalesce((select (anchor.returned is not null)::integer from app.loans anchor where anchor.id=after_id::uuid and anchor.institution_id=i and (r<>'patron' or anchor.patron_id=own)),0),after_id::uuid)
   order by return_rank,id limit page_size)
 select (select count(*) from filtered),coalesce(jsonb_agg(record order by return_rank,id),'[]'::jsonb) into total,rows from page;
 return jsonb_build_object('rows',rows,'total',total,'next_id',case when jsonb_array_length(rows)=page_size then rows->-1->>'id' else null end);
end$$;

revoke all on function app.library_circulation_pre_fines(text,text,integer,text,date,date,text,text) from public,anon,authenticated;
