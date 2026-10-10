import {mkdir,copyFile} from 'node:fs/promises';
await mkdir('public/demo',{recursive:true});
await copyFile('supabase/migrations/202610090001_library.sql','public/demo/migration.sql');
await copyFile('supabase/seed.sql','public/demo/seed.sql');
