import {mkdir,copyFile,cp,readFile,writeFile,readdir} from 'node:fs/promises';
await mkdir('public/demo',{recursive:true});
await copyFile('supabase/migrations/202610090001_library.sql','public/demo/migration.sql');
await copyFile('supabase/seed.sql','public/demo/seed.sql');
// Publish the authoritative help sources and printable manual on every build.
await mkdir('public/manual',{recursive:true});
await cp('docs/help','public/manual',{recursive:true});

const migrations=(await readdir('supabase/migrations')).filter(x=>x.endsWith('.sql')).sort();
await writeFile('public/demo/upgrades.sql',(await Promise.all(migrations.slice(1).map(x=>readFile('supabase/migrations/'+x,'utf8')))).join('\n'));
