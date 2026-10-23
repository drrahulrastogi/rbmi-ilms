-- Assemble each collection once. Avoid repeatedly copying a multi-megabyte JSON object.
create or replace function public.library_snapshot(i text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r text;own uuid;u uuid:=auth.uid();begin
 perform app.require_role(i,array['admin','librarian','assistant','accountant','auditor','patron']);r:=app.role_for(i);
 select patron_id into own from app.memberships where user_id=u and institution_id=i;
 return jsonb_build_object(
'titles',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.titles x where institution_id=i),
'copies',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from app.copies x where institution_id=i),
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
