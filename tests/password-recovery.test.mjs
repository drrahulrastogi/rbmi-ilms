import {test,afterEach} from 'node:test';
import assert from 'node:assert/strict';
import handler from '../api/recovery.js';
import {readRecoveryLink,confirmRecoveryLink} from '../src/recovery-link.mjs';
import {requestPasswordRecovery} from '../src/recovery-flow.mjs';
import {librarySiteURL} from '../server/site-url.mjs';

const originalFetch=globalThis.fetch,originalEnv={...process.env};
afterEach(()=>{globalThis.fetch=originalFetch;for(const k of ['VITE_SUPABASE_URL','VITE_SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE_KEY','VERCEL_URL','VERCEL','APP_URL']){if(originalEnv[k]===undefined)delete process.env[k];else process.env[k]=originalEnv[k];}});
function setup(recover={},quota={allowed:true}){
 delete process.env.APP_URL;
 process.env.VITE_SUPABASE_URL='https://qa.example.invalid';process.env.VITE_SUPABASE_ANON_KEY='qa-public';process.env.SUPABASE_SERVICE_ROLE_KEY='qa-private';delete process.env.VERCEL;
 const calls=[];globalThis.fetch=async(input,init)=>{const url=new URL(input);calls.push({url,init,body:JSON.parse(init.body||'{}')});const payload=url.pathname==='/rest/v1/rpc/library_api_quota'?quota:recover;return payload instanceof Response?payload:new Response(JSON.stringify(payload),{status:200,headers:{'Content-Type':'application/json'}});};return calls;
}
async function invoke({method='POST',body={email:'reader@example.test'},headers={}}={}){
 const result={status:200,headers:{}};const res={statusCode:200,setHeader:(k,v)=>result.headers[k]=v,status(code){this.statusCode=code;result.status=code;return this;},json(value){result.body=value;return result;}};
 await handler({method,body,headers:{'content-type':'application/json',origin:'https://rbmi-ilms.vercel.app',...headers},socket:{remoteAddress:'192.0.2.1'}},res);return result;
}
test('anonymous reset request uses fixed callback, hashed quotas, no identity lookup and no secret response',async()=>{
 const calls=setup();const result=await invoke({body:{email:'  Reader@Example.Test  '}});assert.equal(result.status,200);assert.equal(result.headers['Cache-Control'],'no-store');assert.equal(calls.length,3);
 const send=calls.find(c=>c.url.pathname==='/auth/v1/recover');assert.equal(send.body.email,'reader@example.test');assert.equal(send.url.searchParams.get('redirect_to'),'https://rbmi-ilms.vercel.app/?recovery=1');
 assert.ok(calls.slice(0,2).every(c=>!JSON.stringify(c.body).includes('reader@example.test')));assert.ok(!JSON.stringify(result).includes('qa-private'));assert.ok(!calls.some(c=>c.url.pathname.includes('/admin/users')));
});
test('invalid input, foreign origins, oversized bodies and unsupported methods cannot send email',async()=>{
 const calls=setup();for(const [options,status] of [[{method:'GET'},405],[{body:{email:'bad'}},400],[{body:{email:'sample@example.invalid'}},400],[{body:{email:'reader@example.test',redirectTo:'https://attacker.example'}},400],[{body:{email:'x'.repeat(1100)}},413],[{headers:{origin:'https://attacker.example'}},403],[{headers:{'sec-fetch-site':'cross-site'}},403],[{headers:{'content-type':'application/x-www-form-urlencoded'}},415]])assert.equal((await invoke(options)).status,status);assert.equal(calls.length,0);
});

test('clone recovery uses the configured site and still rejects arbitrary origins',async()=>{
 const calls=setup();process.env.APP_URL='https://rbmi-library-clone.vercel.app';
 assert.equal((await invoke({headers:{origin:process.env.APP_URL}})).status,200);
 assert.equal(calls.find(c=>c.url.pathname==='/auth/v1/recover').url.searchParams.get('redirect_to'),process.env.APP_URL+'/?recovery=1');
 const count=calls.length;assert.equal((await invoke({headers:{origin:'https://attacker.example'}})).status,403);assert.equal(calls.length,count);
});

test('site configuration rejects non-HTTPS, embedded credentials and URL paths',()=>{
 for(const value of ['http://example.com','https://user:password@example.com','https://example.com/path','https://example.com/?redirect=other','https://example.com/#fragment']){process.env.APP_URL=value;assert.throws(()=>librarySiteURL());}
});
test('failed security quota stops upstream requests and throttles without revealing identity',async()=>{
 let calls=setup({},{});assert.equal((await invoke()).status,503);assert.equal(calls.length,1);
 calls=setup({},{allowed:false,retry_after:90});const result=await invoke();assert.equal(result.status,429);assert.equal(result.headers['Retry-After'],'90');assert.equal(calls.length,1);
});
test('SMTP failures are actionable and provider throttling returns a retry delay',async()=>{
 setup(new Response(JSON.stringify({code:'email_address_not_authorized',msg:'SMTP authorization failed'}),{status:403,headers:{'Content-Type':'application/json'}}));let result=await invoke();assert.equal(result.status,503);assert.match(result.body.error,/administrator/);assert.ok(!result.body.error.includes('reader@example.test'));
 setup(new Response(JSON.stringify({code:'over_email_send_rate_limit',msg:'Email rate limit exceeded'}),{status:429,headers:{'Content-Type':'application/json'}}));result=await invoke();assert.equal(result.status,429);assert.equal(result.body.retryAfter,60);
});
test('missing server configuration fails closed before external calls',async()=>{
 const calls=setup();delete process.env.SUPABASE_SERVICE_ROLE_KEY;assert.equal((await invoke()).status,503);assert.equal(calls.length,0);
});
test('known and unknown accounts receive the same accepted response',async()=>{
 setup();const existing=await invoke();setup(new Response(JSON.stringify({code:'user_not_found',error_code:'user_not_found',msg:'No user'}),{status:400,headers:{'Content-Type':'application/json'}}));const unknown=await invoke();assert.deepEqual(existing.body,unknown.body);
});
test('recovery snapshot survives Auth removing the implicit callback fragment',async()=>{
 const location={search:'',hash:'#access_token=private-token&refresh_token=refresh&type=recovery'};const link=readRecoveryLink(location);location.hash='';assert.equal(link.requested,true);assert.equal(link.accessToken,'private-token');
 const session={access_token:'private-token'};const client={auth:{getSession:async()=>({data:{session}}),getUser:async token=>{assert.equal(token,'private-token');return {data:{user:{id:'borrower'}}};}}};assert.equal(await confirmRecoveryLink(client,link),session);
 client.auth.getSession=async()=>({data:{session:{access_token:'old-sign-in-token'}}});await assert.rejects(confirmRecoveryLink(client,link),/invalid/);
});
test('one-use token links work across browsers, and other verification types stay outside recovery',async()=>{
 const link=readRecoveryLink({search:'?token_hash=private-hash&type=recovery',hash:''});assert.equal(link.requested,true);
 const session={access_token:'recovered'};const client={auth:{verifyOtp:async value=>{assert.deepEqual(value,{token_hash:'private-hash',type:'recovery'});return {data:{session}};}}};assert.equal(await confirmRecoveryLink(client,link),session);
 assert.equal(readRecoveryLink({search:'?token_hash=other&type=signup',hash:''}).requested,false);
 assert.equal(readRecoveryLink({search:'?recovery=1&type=signup&token_hash=other',hash:''}).tokenHash,null);
});
test('PKCE, expired, reused and incomplete links have explicit safe outcomes',async()=>{
 const session={access_token:'recovered'};const client={auth:{exchangeCodeForSession:async code=>{assert.equal(code,'code');return {data:{session}};}}};assert.equal(await confirmRecoveryLink(client,readRecoveryLink({search:'?recovery=1&code=code'})),session);
 await assert.rejects(confirmRecoveryLink(client,readRecoveryLink({search:'?recovery=1',hash:'#error_code=otp_expired'})),/expired/);
 assert.equal(readRecoveryLink({hash:'#error_code=otp_expired'}).requested,true);
 await assert.rejects(confirmRecoveryLink(client,readRecoveryLink({search:'?recovery=1'})),/complete link/);
 client.auth.verifyOtp=async()=>({error:{message:'Invalid one-use token'}});await assert.rejects(confirmRecoveryLink(client,{tokenHash:'used'}),/already been used/);
});
test('request helper normalizes email and exposes cooldown and delivery errors without credentials',async()=>{
 const response={ok:true,json:async()=>({message:'Check email',retryAfter:60})};const request=async(url,init)=>{assert.equal(url,'/api/recovery');assert.deepEqual(JSON.parse(init.body),{email:'reader@example.test'});assert.equal(init.headers.Authorization,undefined);return response;};assert.equal((await requestPasswordRecovery(request,' Reader@Example.Test ')).retryAfter,60);
 await assert.rejects(requestPasswordRecovery(async()=>({ok:false,status:429,headers:{get:()=> '90'},json:async()=>({error:'Wait'})}),'reader@example.test'),error=>error.message==='Wait'&&error.retryAfter===90);
 await assert.rejects(requestPasswordRecovery(async()=>({ok:false,status:503,json:async()=>({error:'Email service unavailable'})}),'reader@example.test'),/Email service unavailable/);
});
