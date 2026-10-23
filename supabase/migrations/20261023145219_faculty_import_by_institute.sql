-- Institute-scoped faculty memberships; no Auth login is created by patron import.
create or replace function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; rowdata jsonb; n integer:=0; v uuid; institute_code text; seen_codes text[]:=array[]::text[];
begin
 if action='holiday_import' then return app.import_holidays(i,p->'rows');
 elsif action='holiday' then return app.import_holidays(i,jsonb_build_array(p)); end if;
 if action='import' and p->>'kind' in ('students','faculty') then
  perform app.require_role(i,array['admin','librarian']);
  if jsonb_typeof(p->'rows') is distinct from 'array' or jsonb_array_length(p->'rows')>1000 then raise exception 'At most 1000 patrons per batch'; end if;
  for rowdata in select value from jsonb_array_elements(p->'rows') loop
   if p->>'kind'='faculty' then
    if nullif(btrim(rowdata->>'code'),'') is null or nullif(btrim(rowdata->>'name'),'') is null then raise exception 'Faculty code and name are required'; end if;
    if rowdata->>'code'=any(seen_codes) then raise exception 'Duplicate faculty code in batch'; end if;
    seen_codes:=array_append(seen_codes,rowdata->>'code');
    if exists(select 1 from app.patrons where institution_id=i and code=rowdata->>'code' and category<>'faculty') then raise exception 'Faculty code already belongs to another patron category'; end if;
    rowdata:=rowdata||jsonb_build_object('category','faculty','institute',coalesce(nullif(btrim(rowdata->>'institute'),''),i));
   end if;
   perform public.library_action(i,'patron',rowdata||jsonb_build_object('code',coalesce(nullif(rowdata->>'code',''),nullif(rowdata->>'card_no',''),rowdata->>'roll_no'),'category',case when p->>'kind'='faculty' then 'faculty' else 'student' end,'expires',nullif(btrim(rowdata->>'expires'),''),'active',coalesce(rowdata->'active','true'::jsonb),'department',coalesce(rowdata->>'department',concat_ws(' / ',rowdata->>'course',rowdata->>'branch',rowdata->>'year')),'profile',coalesce(rowdata->'profile',rowdata-'name'-'email'))); n:=n+1;
  end loop;
  return jsonb_build_object('imported',n);
 elsif action='patron' then
  perform app.require_role(i,array['admin','librarian']);
  if p ? 'institute' or p->>'category'='faculty' then
   institute_code:=upper(btrim(coalesce(nullif(p->>'institute',''),p->'profile'->>'institute',i)));
   if not exists(select 1 from app.institutions where id=i and active and institute_code=any(campuses)) then raise exception 'Institute must belong to the selected library'; end if;
   p:=p||jsonb_build_object('profile',coalesce(p->'profile','{}'::jsonb)||jsonb_build_object('institute',institute_code));
  end if;
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
