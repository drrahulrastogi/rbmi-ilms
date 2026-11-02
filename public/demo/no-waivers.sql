-- No role, including admin, can create a waiver. Preserve historic accounting.
alter function public.library_action(text,text,jsonb) rename to library_action_pre_no_waivers;
alter function public.library_action_pre_no_waivers(text,text,jsonb) set schema app;
revoke all on function app.library_action_pre_no_waivers(text,text,jsonb) from public,anon,authenticated;
create function public.library_action(i text,action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if action='waive' then raise exception 'Fine waivers are disabled for everyone. Collect the full fine.';end if;
 return app.library_action_pre_no_waivers(i,action,p);
end$$;
revoke all on function public.library_action(text,text,jsonb) from public,anon;
grant execute on function public.library_action(text,text,jsonb) to authenticated;

-- Also reject waiver writes through any older internal operation.
create function app.reject_fine_waiver() returns trigger language plpgsql set search_path='' as $$
begin
 if TG_TABLE_NAME='fines' then
  if TG_OP='INSERT' then
   if new.waived<>0 then raise exception 'Fine waivers are disabled for everyone';end if;
  elsif new.waived is distinct from old.waived then raise exception 'Fine waivers are disabled for everyone';end if;
 elsif new.kind='waiver' then raise exception 'Fine waivers are disabled for everyone';end if;
 return new;
end$$;
revoke all on function app.reject_fine_waiver() from public,anon,authenticated;
create trigger no_fine_waivers before insert or update on app.fines for each row execute function app.reject_fine_waiver();
create trigger no_waiver_receipts before insert or update on app.payments for each row execute function app.reject_fine_waiver();
