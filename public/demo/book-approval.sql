create table app.book_edits(
 id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,copy_id uuid not null references app.copies,
 request_no text not null unique,request_key uuid not null unique,requested_by uuid not null references auth.users,requested_by_name text not null,
 requested_at timestamptz not null default now(),remarks text not null check(length(btrim(remarks)) between 1 and 2000),
 original_title jsonb not null,original_copy jsonb not null,changes jsonb not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 reviewed_by uuid references auth.users,reviewed_by_name text,reviewed_at timestamptz,review_message text,
 check((status='pending' and reviewed_at is null and reviewed_by is null) or (status<>'pending' and reviewed_at is not null and reviewed_by is not null)),
 check(status<>'rejected' or length(btrim(coalesce(review_message,''))) between 1 and 2000));
create index book_edits_library on app.book_edits(institution_id,status,id);
alter table app.book_edits enable row level security;
revoke all on app.book_edits from public,anon,authenticated;
create function app.book_edit_title_state(t app.titles) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('title',t.title,'author',t.author,'isbn',t.isbn,'publisher',t.publisher,'subject',t.subject,'classification',t.classification,'year',t.year);
$$;
create function app.book_edit_copy_state(c app.copies) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('accession',c.accession,'barcode',c.barcode,'institute',c.institute,'shelf',c.shelf,'price',c.price,'accessioned_on',c.accessioned_on,'status',c.status);
$$;
revoke all on function app.book_edit_title_state(app.titles),app.book_edit_copy_state(app.copies) from public,anon,authenticated;

create function public.library_book_edit_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c app.copies;t app.titles;r app.book_edits;proposed jsonb;cost numeric;added date;yr integer;campus text;new_status text;note text;begin
 if action not in ('book_edit_request','book_edit_approve','book_edit_reject') then raise exception 'Invalid book edit action';end if;
 if action='book_edit_request' then perform app.require_role(i,array['librarian']);else perform app.require_role(i,array['admin']);end if;
 perform 1 from app.institutions where id=i for update;
 if action='book_edit_request' then
  select * into r from app.book_edits where request_key=(p->>'request_key')::uuid and institution_id=i and requested_by=auth.uid();
  if found then return jsonb_build_object('id',r.id,'request_no',r.request_no,'replayed',true);end if;
  select * into c from app.copies where institution_id=i and id=(p->>'id')::uuid for update;
  if not found then raise exception 'Book copy not found in this library';end if;
  select * into t from app.titles where id=c.title_id and institution_id=i;
  if exists(select 1 from app.book_edits where institution_id=i and copy_id=c.id and requested_by=auth.uid() and status='pending') then raise exception 'You already have a pending edit request for this copy';end if;
  if length(btrim(coalesce(p->>'remarks',''))) not between 1 and 2000 then raise exception 'Librarian remarks are required (maximum 2000 characters)';end if;
  if length(btrim(coalesce(p->>'title','')))=0 or length(btrim(coalesce(p->>'author','')))=0 then raise exception 'Title and author are required';end if;
  if length(btrim(coalesce(p->>'accession',''))) not between 1 and 200 or length(btrim(coalesce(p->>'barcode',''))) not between 1 and 200 then raise exception 'Accession number and barcode are required';end if;
  cost:=(p->>'price')::numeric;added:=coalesce(nullif(p->>'accessioned_on','')::date,c.accessioned_on);yr:=nullif(p->>'year','')::integer;
  if cost is null or cost<0 or cost>9999999999.99 or cost<>round(cost,2) then raise exception 'Invalid price';end if;
  if added<'1900-01-01'::date or added>app.today() or yr not between 1000 and 3000 then raise exception 'Invalid date or publication year';end if;
  campus:=app.book_institute(i,p->>'institute');new_status:=coalesce(nullif(p->>'status',''),c.status);
  if new_status not in ('available','lost','damaged','withdrawn','missing','loaned') or (new_status<>c.status and (c.status='loaned' or new_status='loaned')) then raise exception 'Book issue/return status must be changed through circulation';end if;
  proposed:=jsonb_build_object('title',btrim(p->>'title'),'author',btrim(p->>'author'),'isbn',coalesce(p->>'isbn',''),'publisher',coalesce(p->>'publisher',''),'subject',coalesce(p->>'subject',''),'classification',coalesce(p->>'classification',''),'year',yr,
   'accession',btrim(p->>'accession'),'barcode',btrim(p->>'barcode'),'institute',campus,'shelf',coalesce(p->>'shelf',''),'price',cost,'accessioned_on',added,'status',new_status);
  if proposed=app.book_edit_title_state(t)||app.book_edit_copy_state(c) then raise exception 'Change at least one book detail';end if;
  insert into app.book_edits(institution_id,copy_id,request_no,request_key,requested_by,requested_by_name,remarks,original_title,original_copy,changes)
   values(i,c.id,app.new_slip_number(i,'EDIT',app.today()),(p->>'request_key')::uuid,auth.uid(),app.staff_slip_name(auth.uid(),i),btrim(p->>'remarks'),app.book_edit_title_state(t),app.book_edit_copy_state(c),proposed) returning * into r;
 else
  select * into r from app.book_edits where institution_id=i and id=(p->>'id')::uuid for update;
  if not found then raise exception 'Edit request not found in this library';end if;
  if r.status<>'pending' then raise exception 'This edit request has already been reviewed';end if;
  note:=btrim(coalesce(p->>'message',''));
  if length(note)>2000 or (action='book_edit_reject' and length(note)=0) then raise exception 'A rejection message is required (maximum 2000 characters)';end if;
  if action='book_edit_approve' then
   select * into c from app.copies where id=r.copy_id and institution_id=i for update;
   select * into t from app.titles where id=c.title_id and institution_id=i for update;
   if app.book_edit_title_state(t) is distinct from r.original_title or app.book_edit_copy_state(c) is distinct from r.original_copy then raise exception 'Book details have changed since this request. Reject it with a message and ask for a fresh request';end if;
   perform public.library_action(i,'title',r.changes||jsonb_build_object('id',c.title_id));
   perform public.library_action(i,'copy_edit',r.changes||jsonb_build_object('id',c.id,'reason','Approved '||r.request_no||': '||left(r.remarks,350)));
   if r.changes->>'status'<>c.status then perform public.library_action(i,'copy_status',jsonb_build_object('id',c.id,'status',r.changes->>'status','reason','Approved '||r.request_no));end if;
  end if;
  update app.book_edits set status=case when action='book_edit_approve' then 'approved' else 'rejected' end,reviewed_by=auth.uid(),reviewed_by_name=app.staff_slip_name(auth.uid(),i),reviewed_at=now(),review_message=note where id=r.id returning * into r;
 end if;
 insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,jsonb_build_object('request_id',r.id,'request_no',r.request_no,'copy_id',r.copy_id,'remarks',r.remarks,'message',r.review_message));
 return jsonb_build_object('id',r.id,'request_no',r.request_no,'status',r.status);
end$$;
revoke all on function public.library_book_edit_action(text,text,jsonb) from public,anon;
grant execute on function public.library_book_edit_action(text,text,jsonb) to authenticated;

-- Keep the dispatcher's OID intact: existing import routines recursively call it.
create function app.guard_book_import(p jsonb) returns void language plpgsql set search_path='' as $$
declare item jsonb;begin
 if jsonb_typeof(p->'rows')='array' then for item in select value from jsonb_array_elements(p->'rows') loop
  if nullif(item->>'id','') is not null then raise exception 'Submit existing-book changes through admin approval';end if;
 end loop;end if;
end$$;
revoke all on function app.guard_book_import(jsonb) from public,anon,authenticated;
do $migration$declare body text;definition text;guard text;begin
 select prosrc,pg_get_functiondef(oid) into body,definition from pg_proc where oid='public.library_action(text,text,jsonb)'::regprocedure;
 guard:=$guard$begin
 if action in ('book_edit_request','book_edit_approve','book_edit_reject') then return public.library_book_edit_action(i,action,p);end if;
 if app.role_for(i)='librarian' then
  if action in ('copy_edit','copy_institute','copy_status') or (action='title' and nullif(p->>'id','') is not null) then raise exception 'Access denied: submit a book edit request with remarks. Only admin-approved changes can update existing books';end if;
  if action='marc_import' or (action='import' and p->>'kind'='books') then perform app.guard_book_import(p);end if;
 end if;
 $guard$;
 execute replace(definition,body,regexp_replace(body,'\mbegin\M',guard,'i'));
end$migration$;

create function public.library_book_edits(i text,request_status text default 'all',after_id uuid default null,page_size integer default 100) returns jsonb language plpgsql security definer set search_path='' as $$
declare rows_data jsonb;total bigint;begin
 perform app.require_role(i,array['admin','librarian']);
 if request_status not in ('all','pending','approved','rejected') or page_size is null or page_size not between 1 and 100 then raise exception 'Invalid edit history filter';end if;
 with filtered as(select * from app.book_edits where institution_id=i and (request_status='all' or status=request_status)),paged as(select * from filtered where after_id is null or id>after_id order by id limit page_size)
 select (select coalesce(jsonb_agg(to_jsonb(p) order by id),'[]') from paged p),count(*) into rows_data,total from filtered;
 return jsonb_build_object('rows',rows_data,'total',total,'next_id',case when jsonb_array_length(rows_data)=page_size then rows_data->-1->>'id' else null end);
end$$;
revoke all on function public.library_book_edits(text,text,uuid,integer) from public,anon;
grant execute on function public.library_book_edits(text,text,uuid,integer) to authenticated;
