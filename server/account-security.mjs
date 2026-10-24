import {createClient} from '@supabase/supabase-js';import {createHash,randomUUID} from 'node:crypto';
export function secureAccountEndpoint(operation,methods,work){return async(req,res)=>{
 const started=Date.now(),requestId=randomUUID();res.setHeader('Cache-Control','no-store');res.setHeader('X-Request-ID',requestId);
 try{
  if(!methods.includes(req.method)){res.setHeader('Allow',methods.join(', '));return res.status(405).json({error:methods.join(' or ')+' required'});}
  const token=/^Bearer (.+)$/.exec(req.headers.authorization||'')?.[1];if(!token)return res.status(401).json({error:'Sign in required'});
  const url=process.env.VITE_SUPABASE_URL,key=process.env.VITE_SUPABASE_ANON_KEY,secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!url||!key||!secret)return res.status(503).json({error:'Account service is not configured'});
  if(Buffer.byteLength(JSON.stringify(req.body||{}))>65536)return res.status(413).json({error:'Account request is too large'});
  const opts={auth:{persistSession:false,autoRefreshToken:false}},client=createClient(url,key,{...opts,global:{headers:{Authorization:'Bearer '+token}}}),service=createClient(url,secret,opts);
  async function quota(kind,subject){const {data,error}=await service.rpc('library_api_quota',{operation:kind,subject});if(error||typeof data?.allowed!=='boolean'){res.status(503).json({error:'Account security service is unavailable'});return false;}if(!data.allowed){res.setHeader('Retry-After',String(Math.max(1,Number(data.retry_after)||60)));res.status(429).json({error:'Too many account requests. Please wait and retry.'});return false;}return true;}
  const ip=process.env.VERCEL==='1'?String(req.headers['x-vercel-forwarded-for']||req.headers['x-forwarded-for']||req.socket?.remoteAddress||'unknown'):String(req.socket?.remoteAddress||'local');
  const ipHash=createHash('sha256').update(secret+'\0'+ip.split(',')[0].trim()).digest('hex');if(!await quota('preauth','ip:'+ipHash))return;
  const {data:auth,error}=await client.auth.getUser(token);if(error||!auth?.user)return res.status(401).json({error:'Sign in required'});
  if(!await quota(operation,'user:'+auth.user.id))return;
  const {data:security,error:stateError}=await client.rpc('library_security_state');if(stateError||!security)return res.status(503).json({error:'Account security state is unavailable'});
  if(security.mfa_required){let claims;try{claims=JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString());}catch{}if(claims?.aal!=='aal2')return res.status(403).json({error:'Verify your administrator second factor'});}
  return await work(req,res,{client,service,opts,auth,token,url,key});
 }catch{return res.status(503).json({error:'Account service unavailable; retry later'});}
 finally{console.info(JSON.stringify({event:'account_request',request_id:requestId,operation,status:res.statusCode||200,duration_ms:Date.now()-started}));}
};}
