-- Preserve source fields without exposing private import archives through the catalogue.
alter table app.patrons add column profile jsonb not null default '{}'::jsonb check(jsonb_typeof(profile)='object');
create table app.import_batches(id uuid primary key default gen_random_uuid(),institution_id text not null references app.institutions,source_name text not null,source_hash text not null,counts jsonb not null default '{}',created_at timestamptz not null default now(),actor uuid references auth.users,unique(institution_id,source_hash));
create table app.import_records(id uuid primary key default gen_random_uuid(),batch_id uuid not null references app.import_batches,kind text not null check(kind in ('student','book')),source_sheet text not null,source_row integer not null,entity_id uuid not null,source_data jsonb not null,unique(batch_id,source_sheet,source_row));
create index import_records_entity on app.import_records(entity_id,kind);
alter table app.import_batches enable row level security;
alter table app.import_records enable row level security;
revoke all on app.import_batches,app.import_records from public,anon,authenticated;
create index titles_library_isbn on app.titles(institution_id,isbn);
create index copies_library_title on app.copies(institution_id,title_id);
create index patrons_library on app.patrons(institution_id);
alter function public.library_action(text,text,jsonb) rename to library_action_v3;
alter function public.library_action_v3(text,text,jsonb) set schema app;
revoke all on function app.library_action_v3(text,text,jsonb) from public,anon,authenticated;
create function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; rowdata jsonb; n integer:=0; v uuid;
begin
 if action='import' and p->>'kind'='students' then
  perform app.require_role(i,array['admin','librarian']);
  if jsonb_typeof(p->'rows') is distinct from 'array' or jsonb_array_length(p->'rows')>1000 then raise exception 'At most 1000 students per batch'; end if;
  for rowdata in select value from jsonb_array_elements(p->'rows') loop
   perform public.library_action(i,'patron',rowdata||jsonb_build_object('code',coalesce(nullif(rowdata->>'code',''),nullif(rowdata->>'card_no',''),rowdata->>'roll_no'),'category','student','active',coalesce(rowdata->'active','true'::jsonb),'department',coalesce(rowdata->>'department',concat_ws(' / ',rowdata->>'course',rowdata->>'branch',rowdata->>'year')),'profile',coalesce(rowdata->'profile',rowdata-'name'-'email'))); n:=n+1;
  end loop;
  return jsonb_build_object('imported',n);
 elsif action='patron' then
  if p ? 'profile' and jsonb_typeof(p->'profile')<>'object' then raise exception 'Student profile must be an object'; end if;
  result:=app.library_action_v3(i,action,p);
  update app.patrons set profile=profile||coalesce(p->'profile','{}') where institution_id=i and code=p->>'code';return result;
 elsif action='source_details' then
  perform app.require_role(i,array['admin','librarian']);
  return coalesce((select jsonb_agg(jsonb_build_object('source',b.source_name,'sheet',r.source_sheet,'row',r.source_row,'fields',r.source_data)) from app.import_records r join app.import_batches b on b.id=r.batch_id where b.institution_id=i and r.entity_id=(p->>'id')::uuid),'[]'::jsonb);
 end if;
 return app.library_action_v3(i,action,p);
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;

alter function app.today() set search_path='';
