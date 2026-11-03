-- Assigned librarians may manage their own calendar; validation and audit remain mandatory.
create or replace function app.import_holidays(i text, rows_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare row_data jsonb; d date; n integer:=0; seen date[]:=array[]::date[]; label text;
begin
 perform app.require_role(i,array['admin','librarian']);
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
