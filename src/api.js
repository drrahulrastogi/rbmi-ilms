import {createClient} from '@supabase/supabase-js';
import {actors,authStub,seedDemo} from '../scripts/demo.mjs';
const url=import.meta.env.VITE_SUPABASE_URL, key=import.meta.env.VITE_SUPABASE_ANON_KEY;
if(Boolean(url)!==Boolean(key)) throw new Error('Set both Supabase environment variables, or leave both blank for demo.');
export const demo=!url;
export const supabase=demo?null:createClient(url,key);
export const assetURL=path=>import.meta.env.BASE_URL+path.replace(/^\//,'');
let dbPromise;
async function database(){if(!dbPromise)dbPromise=(async()=>{const {PGlite}=await import('@electric-sql/pglite');const db=new PGlite('idb://rbmi-library-v1');await db.waitReady;const existing=await db.query("select 1 from pg_namespace where nspname='app'");if(!existing.rows.length){const files=await Promise.all(['demo/migration.sql','demo/seed.sql'].map(async path=>{const res=await fetch(assetURL(path));if(!res.ok)throw new Error('Demo SQL unavailable');return res.text();}));await db.exec('begin;'+authStub+files.join('\n')+'commit;');await seedDemo(db);}await db.query("select set_config('request.jwt.claim.sub',$1,false)",[actors[sessionStorage.getItem('rbmi-role')||'admin']]);return db;})();return dbPromise;}
export async function rpc(name,args={}){if(!demo){const {data,error}=await supabase.rpc(name,args);if(error)throw new Error(error.message);return data;}const db=await database();const keys={library_bootstrap:[],library_snapshot:['i'],library_action:['i','action','p']}[name];const r=await db.query(`select public.${name}(${keys.map((_,n)=>'$'+(n+1)).join(',')}) as data`,keys.map(k=>args[k]));return r.rows[0].data;}
export async function demoRole(role){sessionStorage.setItem('rbmi-role',role);const db=await database();await db.query("select set_config('request.jwt.claim.sub',$1,false)",[actors[role]]);}
export function today(){return new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());}
export function money(n){return new Intl.NumberFormat('en-IN',{style:'currency',currency:'INR'}).format(Number(n||0));}
export function downloadCSV(name,rows){import('papaparse').then(({default: Papa})=>{const safe=rows.map(row=>Object.fromEntries(Object.entries(row).map(([k,v])=>{if(v&&typeof v==='object')v=JSON.stringify(v);return [k,typeof v==='string'&&/^\s*[=+@\-]/.test(v)?"'"+v:v];})));const blob=new Blob(['\ufeff'+Papa.unparse(safe)],{type:'text/csv;charset=utf-8'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});}

