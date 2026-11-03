-- Module assignments apply to staff and non-student borrowers only.
do $$declare d text;b text;needle text;begin
 select pg_get_functiondef(oid),prosrc into d,b from pg_proc where oid='public.library_permissions(text,text,uuid,integer)'::regprocedure;
 needle:='where m.institution_id=i and (m.role<>''librarian'' or s.user_id is not null)';
 if strpos(b,needle)=0 then raise exception 'Unexpected permission search definition';end if;
 execute replace(d,b,replace(b,needle,'where m.institution_id=i and (m.role<>''patron'' or p.category is distinct from ''student'') and (m.role<>''librarian'' or s.user_id is not null)'));
 select pg_get_functiondef(oid),prosrc into d,b from pg_proc where oid='public.library_set_modules(text,uuid,text[],bigint,text)'::regprocedure;
 needle:='perform app.require_role(i,array[''admin'']);';
 if strpos(b,needle)=0 then raise exception 'Unexpected permission assignment definition';end if;
 execute replace(d,b,replace(b,needle,needle||' if exists(select 1 from app.memberships m join app.patrons p on p.id=m.patron_id and p.institution_id=i where m.user_id=target and m.institution_id=i and m.role=''patron'' and p.category=''student'') then raise exception ''Student accounts are excluded from module permission changes'';end if;'));
end$$;
