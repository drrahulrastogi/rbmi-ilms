-- Store a human-readable issuer name separately from the immutable Auth reference.
alter table app.loans add column issued_by_name text;
create function app.loan_issuer_display_name(issuer uuid,library text) returns text
language sql stable security invoker set search_path='' as $$
 select coalesce(
  (select nullif(btrim(display_name),'') from app.library_staff where user_id=issuer and institution_id=library),
  (select coalesce(nullif(btrim(to_jsonb(u)->'raw_user_meta_data'->>'full_name'),''),nullif(btrim(to_jsonb(u)->'raw_user_meta_data'->>'name'),'')) from auth.users u where u.id=issuer)
 )
$$;
revoke all on function app.loan_issuer_display_name(uuid,text) from public,anon,authenticated;
update app.loans set issued_by_name=app.loan_issuer_display_name(issued_by,institution_id) where issued_by is not null;
create function app.stamp_loan_issuer_name() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then
  new.issued_by_name:=app.loan_issuer_display_name(new.issued_by,new.institution_id);
 else
  new.issued_by_name:=old.issued_by_name;
 end if;
 return new;
end$$;
revoke all on function app.stamp_loan_issuer_name() from public,anon,authenticated;
-- PostgreSQL executes BEFORE triggers alphabetically: capture after stamp_library_loan sets issued_by.
create trigger zz_stamp_loan_issuer_name before insert or update on app.loans for each row execute function app.stamp_loan_issuer_name();
notify pgrst,'reload schema';
