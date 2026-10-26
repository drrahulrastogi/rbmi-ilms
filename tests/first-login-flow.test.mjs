import {test} from 'node:test';import assert from 'node:assert/strict';
import {saveInitialPassword} from '../src/first-login-flow.mjs';
import {endBrowserSession} from '../src/session-flow.mjs';
test('first password change uses the authenticated endpoint and then discards the revoked browser session',async()=>{
 const events=[],values={currentPassword:'InitialExample123!',password:'PrivateExample456!',confirmPassword:'PrivateExample456!'};
 const client={auth:{getSession:async()=>({data:{session:{access_token:'initial-session'}}}),signOut:()=>{throw Error('Already revoked on the server');}}};
 const result=await saveInitialPassword(client,async(url,init)=>{assert.equal(url,'/api/patron-logins');assert.equal(init.headers.Authorization,'Bearer initial-session');assert.deepEqual(JSON.parse(init.body),{mode:'first_change',...values});events.push('server_changed');return {ok:true,json:async()=>({ok:true,signInAgain:true})};},values);
 assert.equal(result.signInAgain,true);
 await endBrowserSession({client,storage:{removeItem:()=>events.push('clear')},key:'project-auth',navigate:()=>events.push('sign_in'),reason:'password_changed',skipRemote:true});
 assert.deepEqual(events,['server_changed','clear','clear','clear','sign_in']);
});
test('missing or expired session cannot submit a password change with an undefined bearer token',async()=>{
 for(const result of [{data:{session:null}},{data:{session:null},error:{message:'Expired'}}]){
  await assert.rejects(saveInitialPassword({auth:{getSession:async()=>result}},()=>{throw Error('Must not send');},{}),/sign-in has expired/);
 }
});
test('a rejected password change remains on the form with the server error',async()=>{
 const client={auth:{getSession:async()=>({data:{session:{access_token:'valid-token'}}})}};
 await assert.rejects(saveInitialPassword(client,async()=>({ok:false,json:async()=>({error:'Your initial/current password is incorrect'})}),{}),/current password is incorrect/);
});
