import {mkdir,copyFile,cp,readFile,writeFile,readdir} from 'node:fs/promises';
await mkdir('public/demo',{recursive:true});
await copyFile('supabase/migrations/202610090001_library.sql','public/demo/migration.sql');
await copyFile('supabase/seed.sql','public/demo/seed.sql');
// Publish the authoritative help sources and printable manual on every build.
await mkdir('public/manual',{recursive:true});
await cp('docs/help','public/manual',{recursive:true});

const migrations=(await readdir('supabase/migrations')).filter(x=>x.endsWith('.sql')).sort();
await copyFile('supabase/migrations/20261028132148_accession_and_student_lifecycle.sql','public/demo/lifecycle.sql');
await writeFile('public/demo/upgrades.sql',(await Promise.all(migrations.slice(1).map(x=>readFile('supabase/migrations/'+x,'utf8')))).join('\n'));

await copyFile('supabase/migrations/20261102024955_donation_and_fine_registers.sql','public/demo/registers.sql');

await copyFile('supabase/migrations/20261102034045_pre_return_fines_and_monthly_accounts.sql','public/demo/monthly-fines.sql');

await copyFile('supabase/migrations/20261102080311_fine_start_date_column.sql','public/demo/fine-start.sql');

await copyFile('supabase/migrations/20261102084456_named_numbered_slips.sql','public/demo/named-slips.sql');

await copyFile('supabase/migrations/20261102091740_borrower_payment_receipts.sql','public/demo/borrower-receipts.sql');

await copyFile('supabase/migrations/20261102124927_donor_acknowledgements_full_fine.sql','public/demo/donor-full-fine.sql');

await copyFile('supabase/migrations/20261102142307_disable_fine_waivers.sql','public/demo/no-waivers.sql');

await copyFile('supabase/migrations/20261102162113_accountant_fine_workspace.sql','public/demo/accountant-fines.sql');

await copyFile('supabase/migrations/20261103001732_admin_edit_book_copies.sql','public/demo/copy-edit.sql');

await copyFile('supabase/migrations/20261103002206_book_edit_approval_workflow.sql','public/demo/book-approval.sql');

await copyFile('supabase/migrations/20261103003338_book_edit_decision_refresh.sql','public/demo/book-edit-refresh.sql');

await copyFile('supabase/migrations/20261103100143_librarian_holiday_management.sql','public/demo/librarian-holidays.sql');

await copyFile('supabase/migrations/20261103101309_user_module_permissions.sql','public/demo/module-permissions.sql');

await copyFile('supabase/migrations/20261103124912_non_student_module_permissions.sql','public/demo/non-student-permissions.sql');

await copyFile('supabase/migrations/20261103130847_full_module_assignment.sql','public/demo/full-module-assignment.sql');
