import {test} from 'node:test';import assert from 'node:assert/strict';
import {authStorageKey,isSessionFailure,endBrowserSession,isCurrentSession} from '../src/session-flow.mjs';
test('stale password-change tokens and expired authentication are recognized without logging out ordinary failures',()=>{
 for(const error of [{message:'Sign in again after changing your initial password'},{code:'refresh_token_not_found'},{message:'JWT expired'},{name:'AuthSessionMissingError'}])assert.equal(isSessionFailure(error),true);
 for(const error of [{message:'Network request failed'},{message:'Access denied for this institution/action'},{message:'Change your initial password before accessing library records'},{message:'Title not found'}])assert.equal(isSessionFailure(error),false);
});
test('logout clears only this project auth credentials and returns to sign in',async()=>{
 const key=authStorageKey('https://gpjbcvyueuatwzeqtwhv.supabase.co'),items=new Map([[key,'old-session'],[key+'-code-verifier','private'],[key+'-user','old-user'],['theme','green']]);
 const storage={removeItem:k=>items.delete(k)},calls=[];
 await endBrowserSession({client:{auth:{signOut:async p=>{calls.push(p);return {error:null};}}},storage,key,navigate:url=>calls.push(url),path:'/rbmi-ilms/',reason:'signed_out'});
 assert.deepEqual(calls,[{scope:'local'},'/rbmi-ilms/?signed_out=1']);assert.deepEqual([...items],[['theme','green']]);
});
test('logout is usable when the remote logout rejects or returns an error',async()=>{
 for(const signOut of [async()=>{throw Error('network error');},async()=>({error:{message:'Session revoked'}})]){
  const removed=[],destinations=[];
  await endBrowserSession({client:{auth:{signOut}},storage:{removeItem:k=>removed.push(k)},key:'project-auth',navigate:u=>destinations.push(u),path:'/',reason:'session_expired'});
  assert.equal(removed.length,3);assert.deepEqual(destinations,['/?signed_out=expired']);
 }
});
test('a hung SDK/network cannot trap the user on logout',async()=>{
 let navigated=false;
 await endBrowserSession({client:{auth:{signOut:()=>new Promise(()=>{})}},storage:{removeItem:()=>{}},key:'project-auth',navigate:()=>{navigated=true;},path:'/',timeoutMs:10});
 assert.equal(navigated,true);
});
test('completed first-password setup clears the old session without another server logout',async()=>{
 let calls=0,url;
 await endBrowserSession({client:{auth:{signOut:async()=>{calls++;}}},storage:{removeItem:()=>{}},key:'project-auth',navigate:u=>{url=u;},path:'/',reason:'password_changed',skipRemote:true});
 assert.equal(calls,0);assert.equal(url,'/?signed_out=password_changed');
});
test('ordinary password recovery retains global session revocation before clearing the browser',async()=>{
 const calls=[];
 await endBrowserSession({client:{auth:{signOut:async p=>{calls.push(p);return {error:null};}}},storage:{removeItem:()=>{}},key:'project-auth',navigate:()=>{},path:'/',reason:'password_changed',scope:'global'});
 assert.deepEqual(calls,[{scope:'global'}]);
});
test('blocked browser storage does not prevent reaching the sign-in screen',async()=>{
 let navigated=false;
 await endBrowserSession({client:null,storage:{removeItem:()=>{throw Error('blocked storage');}},key:'project-auth',navigate:()=>{navigated=true;},path:'/',skipRemote:true});
 assert.equal(navigated,true);
});
test('a delayed response from an older session cannot replace a new session for the same user',()=>{
 assert.equal(isCurrentSession('same-user','old-token','same-user','new-token'),false);
 assert.equal(isCurrentSession('old-user','token','new-user','token'),false);
 assert.equal(isCurrentSession('user','token','user','token'),true);
});
