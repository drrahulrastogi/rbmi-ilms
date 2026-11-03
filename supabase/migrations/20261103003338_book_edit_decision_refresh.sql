create function public.library_book_edit_revision(i text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform app.require_role(i,array['admin','librarian']);
 return (select jsonb_build_object('count',count(*),'last_reviewed_at',max(reviewed_at)) from app.book_edits where institution_id=i and status<>'pending');
end$$;
revoke all on function public.library_book_edit_revision(text) from public,anon;
grant execute on function public.library_book_edit_revision(text) to authenticated;
