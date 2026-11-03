-- Admin corrections apply equally to imports, manual entries and donations.
alter function public.library_action(text,text,jsonb) rename to library_action_pre_copy_edit;
alter function public.library_action_pre_copy_edit(text,text,jsonb) set schema app;
revoke all on function app.library_action_pre_copy_edit(text,text,jsonb) from public,anon,authenticated;
create function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare original app.copies;changed app.copies;acc text;bar text;campus text;cost numeric;added date;begin
 if action<>'copy_edit' then return app.library_action_pre_copy_edit(i,action,p);end if;
 perform app.require_role(i,array['admin']);
 perform 1 from app.institutions where id=i for update;
 select * into original from app.copies where institution_id=i and id=(p->>'id')::uuid for update;
 if not found then raise exception 'Copy not found in the selected library';end if;
 acc:=btrim(coalesce(p->>'accession',''));bar:=btrim(coalesce(p->>'barcode',''));
 if length(acc) not between 1 and 200 or length(bar) not between 1 and 200 then raise exception 'Accession number and barcode are required (maximum 200 characters)';end if;
 if length(btrim(coalesce(p->>'reason',''))) not between 1 and 500 then raise exception 'An edit reason is required';end if;
 cost:=(p->>'price')::numeric;added:=coalesce(nullif(p->>'accessioned_on','')::date,original.accessioned_on);
 if cost is null or cost<0 or cost>9999999999.99 or cost<>round(cost,2) then raise exception 'Enter a valid book price';end if;
 if added<'1900-01-01'::date or added>app.today() then raise exception 'Enter a valid accession date';end if;
 campus:=app.book_institute(i,p->>'institute');
 if exists(select 1 from app.copies where institution_id=i and id<>original.id and (lower(btrim(accession))=lower(acc) or lower(btrim(barcode))=lower(bar))) then raise exception 'Accession number or barcode already belongs to another copy';end if;
 update app.copies set accession=acc,barcode=bar,institute=campus,shelf=coalesce(p->>'shelf',''),price=cost,accessioned_on=added where id=original.id returning * into changed;
 insert into app.audit(institution_id,actor,action,details) values(i,auth.uid(),'copy_edit',jsonb_build_object('copy_id',original.id,'reason',btrim(p->>'reason'),'before',to_jsonb(original),'after',to_jsonb(changed)));
 return jsonb_build_object('id',changed.id,'saved',true);
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;
