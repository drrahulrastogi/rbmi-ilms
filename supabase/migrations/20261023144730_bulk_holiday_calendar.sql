-- One atomic, administrator-approved calendar upload per selected library.
create function app.import_holidays(i text, rows_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare row_data jsonb; d date; n integer:=0; seen date[]:=array[]::date[]; label text;
begin
 perform app.require_role(i,array['admin']);
 if jsonb_typeof(rows_data) is distinct from 'array' then raise exception 'Holiday rows must be an array'; end if;
 if jsonb_array_length(rows_data) not between 1 and 1000 then raise exception 'Upload 1 to 1000 holidays per batch'; end if;
 for row_data in select value from jsonb_array_elements(rows_data) loop
  n:=n+1;
  if jsonb_typeof(row_data) is distinct from 'object' or coalesce(row_data->>'day','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Row %: date must be YYYY-MM-DD',n; end if;
  begin d:=(row_data->>'day')::date; exception when others then raise exception 'Row %: invalid calendar date',n; end;
  if d < date '1900-01-01' or d > date '2100-12-31' then raise exception 'Row %: date must be between 1900 and 2100',n; end if;
  label:=btrim(row_data->>'name');
  if label is null or length(label) not between 1 and 200 then raise exception 'Row %: holiday name must contain 1 to 200 characters',n; end if;
  if d=any(seen) then raise exception 'Row %: duplicate holiday date %',n,d; end if;
  seen:=array_append(seen,d);
  insert into app.holidays(institution_id,day,name) values(i,d,label)
   on conflict(institution_id,day) do update set name=excluded.name;
 end loop;
 insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),'holiday_import',jsonb_build_object('imported',n,'rows',rows_data));
 return jsonb_build_object('imported',n);
end$$;
revoke all on function app.import_holidays(text,jsonb) from public,anon,authenticated;
create or replace function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; rowdata jsonb; n integer:=0; v uuid;
begin
 if action='holiday_import' then return app.import_holidays(i,p->'rows');
 elsif action='holiday' then return app.import_holidays(i,jsonb_build_array(p)); end if;
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
