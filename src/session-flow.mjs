export function authStorageKey(url){return 'sb-'+new URL(url).hostname.split('.')[0]+'-auth-token';}

export function isSessionFailure(error){
 const code=String(error?.code||'');
 return ['PGRST301','refresh_token_not_found','refresh_token_already_used','session_not_found'].includes(code)||
  error?.name==='AuthSessionMissingError'||
  /sign in again after changing your initial password|jwt (?:is )?expired|invalid (?:jwt|refresh token)|auth session missing|session (?:is )?(?:expired|missing)/i.test(error?.message||'');
}

export function isCurrentSession(owner,token,activeOwner,activeToken){return owner===activeOwner&&token===activeToken;}

export async function endBrowserSession({client,storage,key,navigate,path='/',reason='signed_out',skipRemote=false,scope='local',timeoutMs=2000}){
 let timer;
 try{
  if(client&&!skipRemote)await Promise.race([
   Promise.resolve().then(()=>client.auth.signOut({scope})).catch(()=>undefined),
   new Promise(resolve=>{timer=setTimeout(resolve,timeoutMs);})
  ]);
 }finally{
  clearTimeout(timer);
  // Clear only this application's credentials. Keep theme and other sites' data.
  for(const suffix of ['','-code-verifier','-user']){
   try{storage?.removeItem(key+suffix);}catch{/* A disabled browser store must not trap the sign-out screen. */}
  }
  const marker=reason==='password_changed'?'password_changed':reason==='session_expired'?'expired':'1';
  navigate(path+'?signed_out='+marker);
 }
}
