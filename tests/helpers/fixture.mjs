import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {authStub,seedDemo,actors} from '../../scripts/demo.mjs';
export {actors};
export async function fixture(){
 const db=new PGlite();await db.exec(authStub);const files=(await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();await db.exec(await readFile('supabase/migrations/'+files[0],'utf8'));await db.exec(await readFile('supabase/seed.sql','utf8'));await seedDemo(db);for(const f of files.slice(1))await db.exec(await readFile('supabase/migrations/'+f,'utf8'));return db;
}
