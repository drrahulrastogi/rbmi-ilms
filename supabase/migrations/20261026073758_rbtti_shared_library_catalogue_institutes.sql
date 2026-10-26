-- RBCET/RBMI/RBTTI share one physical library and its existing designated librarian.
-- Institute denotes a copy's owning collection, not a separate issuing library.
update app.institutions set name='RBCET / RBMI / RBTTI Central Library',
 campuses=array['RBCET','RBMI','RBTTI'] where id='RBCET';
alter table app.copies add column institute text;

-- Owner-approved mapping of the original Central Library workbook.
update app.copies c set institute=case
 when exists(select 1 from app.import_records r where r.kind='book' and r.entity_id=c.id
   and r.source_sheet in ('B.Ed','B.Ed (Book Bank)')) then 'RBTTI'
 when exists(select 1 from app.import_records r where r.kind='book' and r.entity_id=c.id
   and r.source_sheet='B.COM') then 'RBMI'
 else 'RBCET' end where c.institution_id='RBCET';
update app.copies c set institute=i.campuses[1] from app.institutions i
 where c.institution_id=i.id and i.active and cardinality(i.campuses)=1;
create index copies_library_institute_title_page on app.copies(institution_id,institute,title_id,id);

create function app.book_institute(i text,value text) returns text
language plpgsql stable security invoker set search_path='' as $$
declare code text:=nullif(upper(btrim(value)),'');begin
 if code is not null and (length(code)>32 or not exists(
  select 1 from app.institutions x where x.id=i and x.active and code=any(x.campuses)))
 then raise exception 'Institute must belong to the selected library';end if;
 return code;
end$$;
create function app.stamp_copy_institute() returns trigger
language plpgsql security definer set search_path='' as $$begin
 new.institute:=app.book_institute(new.institution_id,new.institute);
 if new.institute is null then
  select campuses[1] into new.institute from app.institutions
   where id=new.institution_id and active and cardinality(campuses)=1;
 end if;
 return new;
end$$;
create trigger copy_institute before insert or update of institute,institution_id on app.copies
 for each row execute function app.stamp_copy_institute();

alter function public.library_action(text,text,jsonb) rename to library_action_pre_institutes;
alter function public.library_action_pre_institutes(text,text,jsonb) set schema app;
revoke all on function app.library_action_pre_institutes(text,text,jsonb) from public,anon,authenticated;
create function public.library_action(i text,action text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;rowdata jsonb;code text;before_code text;copy_id uuid;begin
 if action='copy_institute' then
  perform app.require_role(i,array['admin','librarian']);
  code:=app.book_institute(i,p->>'institute');
  select id,institute into copy_id,before_code from app.copies
   where institution_id=i and id=(p->>'id')::uuid for update;
  if not found then raise exception 'Copy not found in this library';end if;
  update app.copies set institute=code where id=copy_id;
  insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),action,
   jsonb_build_object('copy_id',copy_id,'before',before_code,'institute',code));
  return jsonb_build_object('saved',true);
 end if;
 if action='copy' then
  perform app.require_role(i,array['admin','librarian']);
  code:=app.book_institute(i,p->>'institute');
 elsif action='import' and p->>'kind'='books' then
  perform app.require_role(i,array['admin','librarian']);
  if jsonb_typeof(p->'rows') is distinct from 'array' or jsonb_array_length(p->'rows') not between 1 and 1000
   then raise exception 'Provide 1 to 1000 book rows';end if;
  for rowdata in select value from jsonb_array_elements(p->'rows') loop
   perform app.book_institute(i,rowdata->>'institute');
  end loop;
 end if;
 result:=app.library_action_pre_institutes(i,action,p);
 if action='copy' then
  update app.copies set institute=code where institution_id=i and barcode=p->>'barcode';
 elsif action='import' and p->>'kind'='books' then
  for rowdata in select value from jsonb_array_elements(p->'rows') loop
   update app.copies set institute=app.book_institute(i,rowdata->>'institute')
    where institution_id=i and barcode=rowdata->>'barcode';
  end loop;
 end if;
 return result;
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;

create function app.catalogue_institute_filter(i text,value text) returns text
language plpgsql stable security invoker set search_path='' as $$
declare code text:=nullif(upper(btrim(value)),'');begin
 if not exists(select 1 from app.institutions where id=i and active) then raise exception 'Library not found';end if;
 if code='UNASSIGNED' then return code;end if;
 return app.book_institute(i,code);
end$$;

-- New named RPCs leave the old public catalogue contracts intact.
create function public.library_institute_titles_page(library_code text,institute text default '',
 q text default '',after_id uuid default null,page_size integer default 40) returns jsonb
language plpgsql security definer set search_path='' as $$
declare selected text;ids uuid[];more boolean;begin
 perform app.read_budget('catalogue');
 if page_size is null or page_size<1 or page_size>100 or length(coalesce(q,''))>200
 then raise exception 'Use 1 to 100 titles per page and at most 200 search characters';end if;
 selected:=app.catalogue_institute_filter(library_code,institute);
 select coalesce(array_agg(id order by id),'{}') into ids from (
  select t.id from app.titles t where t.institution_id=library_code and (after_id is null or t.id>after_id)
  and (selected is null or exists(select 1 from app.copies c where c.institution_id=library_code
   and c.title_id=t.id and (c.institute=selected or selected='UNASSIGNED' and c.institute is null)))
  and (strpos(lower(concat_ws(' ',t.title,t.author,t.isbn,t.subject,t.classification)),lower(coalesce(q,'')))>0
   or exists(select 1 from app.copies c where c.institution_id=library_code and c.title_id=t.id
    and (selected is null or c.institute=selected or selected='UNASSIGNED' and c.institute is null)
    and strpos(lower(concat_ws(' ',c.barcode,c.accession)),lower(coalesce(q,'')))>0))
  order by t.id limit page_size+1) t;
 more:=cardinality(ids)>page_size;ids:=ids[1:page_size];
 return jsonb_build_object(
  'libraries',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'campuses',campuses) order by id) from app.institutions where active),
  'titles',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from app.titles t where t.institution_id=library_code and id=any(ids)),
  'copies',(select coalesce(jsonb_agg(jsonb_build_object('title_id',title_id,'accession',accession,'shelf',shelf,'status',status,'institute',x.institute)),'[]')
   from (select c.*,row_number() over(partition by title_id order by id) rn from app.copies c
    where c.institution_id=library_code and title_id=any(ids)
    and (selected is null or c.institute=selected or selected='UNASSIGNED' and c.institute is null)) x where rn<=4),
  'copy_counts',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (
   select title_id,count(*) total,count(*) filter(where status='available') available from app.copies c
    where c.institution_id=library_code and title_id=any(ids)
    and (selected is null or c.institute=selected or selected='UNASSIGNED' and c.institute is null) group by title_id) x),
  'has_more',more,'next_id',case when more then ids[cardinality(ids)] else null end);
end$$;
create function public.library_institute_copies_page(library_code text,title uuid,institute text default '',
 after_id uuid default null,page_size integer default 50) returns jsonb
language plpgsql security definer set search_path='' as $$
declare selected text;rows jsonb;begin
 perform app.read_budget('copies');
 if page_size is null or page_size<1 or page_size>100 then raise exception 'Use 1 to 100 copies per page';end if;
 selected:=app.catalogue_institute_filter(library_code,institute);
 if not exists(select 1 from app.titles t where t.id=$2 and t.institution_id=library_code) then raise exception 'Title not found';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') into rows from (
  select c.id,c.title_id,c.accession,c.shelf,c.status,c.institute from app.copies c
  where c.institution_id=library_code and c.title_id=title and (after_id is null or c.id>after_id)
  and (selected is null or c.institute=selected or selected='UNASSIGNED' and c.institute is null)
  order by c.id limit page_size) x;
 return jsonb_build_object('rows',rows,'next_id',case when jsonb_array_length(rows)=page_size then rows->-1->>'id' else null end);
end$$;
revoke all on function app.book_institute(text,text),app.stamp_copy_institute(),app.catalogue_institute_filter(text,text) from public,anon,authenticated;
revoke all on function public.library_institute_titles_page(text,text,text,uuid,integer),public.library_institute_copies_page(text,uuid,text,uuid,integer) from public;
grant execute on function public.library_institute_titles_page(text,text,text,uuid,integer),public.library_institute_copies_page(text,uuid,text,uuid,integer) to anon,authenticated;
notify pgrst,'reload schema';
