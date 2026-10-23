-- Assemble each collection once. Avoid repeatedly copying a multi-megabyte JSON object.
create or replace function public.library_workspace(i text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r text;own uuid;u uuid:=auth.uid();begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);r:=app.role_for(i);
 select patron_id into own from app.memberships where user_id=u and institution_id=i;
 return jsonb_build_object(
'titles','[]'::jsonb,
'copies','[]'::jsonb,
'policies',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.policies x where institution_id=i),
'holidays',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.holidays x where institution_id=i),
'patrons',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.patrons x where institution_id=i and (r<>'patron' or id=own)),
'loans',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.loans x where institution_id=i and (r<>'patron' or patron_id=own)),
'holds',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.holds x where institution_id=i and (r<>'patron' or patron_id=own)),
'fines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.fines x where institution_id=i and (r<>'patron' or patron_id=own)),
'payments',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.payments x where institution_id=i) end,
'vendors',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.vendors x where institution_id=i) end,
'acquisitions',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.acquisitions x where institution_id=i) end,
'stock_sessions',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.stock_sessions x where institution_id=i) end,
'stock_items',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.stock_items x where institution_id=i) end,
'audit',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.audit x where institution_id=i) end,
'memberships',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.memberships x where institution_id=i) end,
'authorities',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.authorities x where institution_id=i),
'title_authorities',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.title_authorities x where institution_id=i),
'subscriptions',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.subscriptions x where institution_id=i),
'serial_issues',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.serial_issues x where institution_id=i),
'reading_lists',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.reading_lists x where institution_id=i and (visibility='public' or owner=u)),
'list_entries',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.list_entries x where institution_id=i and exists(select 1 from app.reading_lists l where l.id=x.list_id and (l.visibility='public' or l.owner=u))),
'budgets',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.budgets x where institution_id=i) end,
'funds',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.funds x where institution_id=i) end,
'baskets',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.baskets x where institution_id=i) end,
'saved_reports',case when r='patron' then '[]'::jsonb else (select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.saved_reports x where institution_id=i) end,
'library',(select to_jsonb(x) from app.institutions x where id=i),
'librarian',(select jsonb_build_object('user_id',user_id,'display_name',display_name) from app.library_staff where institution_id=i),
'availability',(select coalesce(jsonb_agg(to_jsonb(x) order by day desc),'[]') from app.library_availability x where institution_id=i),
'today',app.today());
end$$;

create index titles_library_page on app.titles(institution_id,id);
create index copies_library_page on app.copies(institution_id,id);
create function public.library_collection_page(i text,kind text,after_id uuid default null,page_size integer default 5000) returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb;begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);
 if kind<>all(array['titles','copies']) or kind is null or page_size is null or page_size<1 or page_size>5000 then raise exception 'Invalid collection page request';end if;
 execute format('select coalesce(jsonb_agg(to_jsonb(x) order by x.id),''[]''::jsonb) from (select * from app.%I where institution_id=$1 and ($2 is null or id>$2) order by id limit $3) x',kind) into rows using i,after_id,page_size;
 return jsonb_build_object('rows',rows,'next_id',case when jsonb_array_length(rows)=page_size then rows->-1->>'id' else null end);
end$$;
revoke all on function public.library_workspace(text),public.library_collection_page(text,text,uuid,integer) from public,anon;
grant execute on function public.library_workspace(text),public.library_collection_page(text,text,uuid,integer) to authenticated;

create function public.library_catalogue_search(library_code text,q text default '',max_titles integer default 40) returns jsonb language plpgsql security definer set search_path='' as $$
declare ids uuid[];more boolean;begin
 if max_titles is null or max_titles<1 or max_titles>2000 or length(coalesce(q,''))>200 then raise exception 'Narrow the search or use at most 2000 catalogue results';end if;
 if not exists(select 1 from app.institutions where id=library_code and active) then raise exception 'Library not found';end if;
 select coalesce(array_agg(x.id order by x.id),'{}') into ids from (select id from app.titles where institution_id=library_code and strpos(lower(concat_ws(' ',title,author,isbn,subject)),lower(coalesce(q,'')))>0 order by id limit max_titles+1) x;
 more:=cardinality(ids)>max_titles;ids:=ids[1:max_titles];
 return jsonb_build_object('libraries',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by id),'[]') from app.institutions where active),'titles',(select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]') from app.titles x where institution_id=library_code and id=any(ids)), 'copies',(select coalesce(jsonb_agg(jsonb_build_object('title_id',title_id,'accession',accession,'shelf',shelf,'status',status)),'[]') from app.copies where institution_id=library_code and title_id=any(ids)), 'has_more',more);
end$$;
revoke all on function public.library_catalogue_search(text,text,integer) from public;
grant execute on function public.library_catalogue_search(text,text,integer) to anon,authenticated;
