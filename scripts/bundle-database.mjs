import {readFile,readdir,writeFile} from 'node:fs/promises';
const files=(await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort(),sql=await Promise.all(files.map(f=>readFile('supabase/migrations/'+f,'utf8'))),seed=await readFile('supabase/seed.sql','utf8');
await writeFile('database/schema.sql','-- Supabase platform prerequisite; no live data.\n'+sql.join('\n'));await writeFile('database/seed.sql',seed);
await writeFile('database/install-new-supabase.sql',"begin;\ndo $$begin if exists(select 1 from pg_namespace where nspname='app') then raise exception 'Application schema already exists. Apply only missing migrations.';end if;end$$;\n"+sql[0]+'\n'+seed+'\n'+sql.slice(1).join('\n')+'\ncommit;\n');console.log('Bundled '+files.length+' migrations');
