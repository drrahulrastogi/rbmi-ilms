// NOT RUN against production. Requires an isolated staging Supabase project with synthetic data.
import http from 'k6/http';import {check,sleep} from 'k6';
const base=(__ENV.STAGING_SUPABASE_URL||'http://127.0.0.1:54321').replace(/\/$/,'');
if(base.includes('gpjbcvyueuatwzeqtwhv')||base.includes('rbmi-ilms.vercel.app'))throw Error('Production target prohibited');
if(!/^http:\/\/127\.0\.0\.1:/.test(base)&&__ENV.CONFIRM_STAGING_TARGET!==base)throw Error('Set CONFIRM_STAGING_TARGET to the exact isolated staging URL');
export const options={scenarios:{catalogue:{executor:'ramping-vus',startVUs:0,stages:[{duration:'30s',target:100},{duration:'30s',target:500},{duration:'30s',target:1000},{duration:'30s',target:5000},{duration:'30s',target:0}],gracefulRampDown:'10s'}},thresholds:{http_req_failed:['rate<0.01'],http_req_duration:['p(95)<2000']}};
export default function(){const r=http.post(base+'/rest/v1/rpc/library_catalogue_search',JSON.stringify({library_code:'RBCET',q:'Synthetic',max_titles:40}),{headers:{apikey:__ENV.STAGING_ANON_KEY,'Content-Type':'application/json'},timeout:'10s'});check(r,{'RPC succeeds':r=>r.status===200,'catalogue shape':r=>{try{return Array.isArray(r.json('titles'));}catch{return false;}}});sleep(5);}
