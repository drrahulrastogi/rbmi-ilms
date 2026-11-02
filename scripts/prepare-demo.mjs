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
