import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { readConfig, createTokenHandler } from './server.mjs';
import { createContextHandler, readContextConfig } from './context-handler.mjs';
import { readAdmissionConfig, reserveAdmission } from './admission.mjs';

const uid = 'a0000000-0000-4000-8000-000000000001';
const token = 'mock-user-session-token';
const env = { OPENAI_API_KEY: 'mock-openai-secret', FEEL_VOICE_AUTH_MODE: 'supabase',
  SUPABASE_URL: 'https://project.supabase.co', SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_mock_key',
  SUPABASE_SECRET_KEY: 'sb_secret_mock_server_key' };
const admission = readAdmissionConfig(env);
const allowed = { allowed: true, reason: 'allowed', retry_after_seconds: 0 };
const denied = { allowed: false, reason: 'quota_exceeded', retry_after_seconds: 42 };
const timestamp = 1800000000000;
const ephemeral = { value: 'mock-ephemeral-secret', expires_at: timestamp / 1000 + 300 };
async function invoke(handler, changes = {}) {
  const req = { method: 'POST', url: '/session', headers: { 'x-forwarded-proto': 'https', authorization: `Bearer ${token}` }, ...changes };
  const res = new EventEmitter();
  res.writeHead = (status, headers) => { res.status = status; res.headers = headers; };
  res.end = body => { res.body = JSON.parse(body); res.writableEnded = true; };
  await handler(req, res); return res;
}
function fixture({ user = { id: uid, is_anonymous: false }, quota = allowed, fetchImpl, ...options } = {}) {
  const calls = [];
  const handler = createTokenHandler(readConfig(env), { now: () => timestamp, fetchImpl: fetchImpl || (async (url, init) => {
    calls.push({ url, init });
    const value = url.endsWith('/user') ? user : url.endsWith('/feel_reserve_admission') ? quota : ephemeral;
    return value instanceof Response ? value : Response.json(value);
  }), ...options });
  return { handler, calls };
}
test('production voice verifies account, reserves fixed admission then mints without forwarding secrets', async () => {
  const { handler, calls } = fixture();
  const response = await invoke(handler);
  assert.equal(response.status,200); assert.deepEqual(response.body,ephemeral); assert.equal(calls.length,3);
  assert.equal(calls[0].url,`${env.SUPABASE_URL}/auth/v1/user`);
  assert.equal(calls[0].init.headers.Authorization,`Bearer ${token}`);
  assert.equal(calls[1].url,`${env.SUPABASE_URL}/rest/v1/rpc/feel_reserve_admission`);
  assert.deepEqual(JSON.parse(calls[1].init.body),{p_user_id:uid,p_operation:'voice_session'});
  assert.equal(calls[1].init.headers.apikey,env.SUPABASE_SECRET_KEY);
  assert.equal(calls[1].init.headers.Authorization,undefined,'Modern secret is not a JWT');
  assert.equal(calls[2].init.headers.Authorization,`Bearer ${env.OPENAI_API_KEY}`);
  assert.ok(!calls[1].init.body.includes(token));
  for(const {init} of calls) assert.equal(init.redirect,'error');
});
test('configuration is explicit, demo remains default and production requires durable credentials',()=>{
  const demo=readConfig({OPENAI_API_KEY:env.OPENAI_API_KEY,FEEL_VOICE_ACCESS_TOKEN:'mock-demo-access-key-longer-than-32-chars'});
  assert.equal(demo.authMode,'demo');assert.equal(demo.admission,undefined);
  assert.equal(readConfig(env).requireHTTPS,true);
  for(const bad of [{...env,FEEL_VOICE_AUTH_MODE:'typo'},{...env,SUPABASE_SECRET_KEY:''},
    {...env,SUPABASE_SECRET_KEY:env.SUPABASE_PUBLISHABLE_KEY},{...env,SUPABASE_URL:'http://localhost'},
    {...env,SUPABASE_SECRET_KEY:'not-a-server-secret'}]) assert.throws(()=>readConfig(bad));
});
test('anonymous, revoked and unverified accounts never reserve quota or call the provider',async()=>{
  for(const user of [{id:uid,is_anonymous:true},{id:uid}, {id:'someone:else',is_anonymous:false},
    new Response('upstream secret',{status:401}),new Response('upstream secret',{status:403})]){
    const {handler,calls}=fixture({user});const res=await invoke(handler);
    assert.ok([401,403].includes(res.status));assert.equal(calls.length,1);
    assert.ok(!JSON.stringify(res.body).includes('secret'));
  }
});
test('caller identity and user metadata cannot choose the admission principal',async()=>{
  const {handler,calls}=fixture({user:{id:uid,is_anonymous:false,user_metadata:{sub:'another-user',user_id:'another-user'}}});
  assert.equal((await invoke(handler,{body:{p_user_id:'another-user'}})).status,400);assert.equal(calls.length,0);
  assert.equal((await invoke(handler)).status,200);assert.equal(JSON.parse(calls[1].init.body).p_user_id,uid);
});
test('denied, absent, malformed or unavailable durable policies never mint sessions',async()=>{
  for(const quota of [denied,{allowed:false,reason:'not_enabled',retry_after_seconds:0},
    new Response('secret database details',{status:404}),new Response('secret',{status:500}),
    {allowed:'true',reason:'allowed',retry_after_seconds:0},{allowed:true,reason:'allowed',retry_after_seconds:0,extra:'secret'},
    {allowed:true,reason:'quota_exceeded',retry_after_seconds:0},[allowed],null]){
    const {handler,calls}=fixture({quota});const res=await invoke(handler);
    assert.equal(res.status,quota===denied?429:503);assert.equal(calls.length,2);
    if(quota===denied)assert.equal(res.headers['Retry-After'],'42');
    assert.ok(!JSON.stringify(res.body).includes('secret'));
  }
});
test('auth/admission failures are bounded and return stable errors',async()=>{
  for(const failAt of [1,2]){
    let calls=0;
    const {handler}=fixture({fetchImpl:async()=>{
      if(++calls===failAt)throw new Error('sensitive diagnostic');return Response.json({id:uid,is_anonymous:false});
    }});
    const res=await invoke(handler);assert.equal(res.status,503);assert.deepEqual(res.body,{error:'admission_unavailable'});
  }
  for(const failAt of [1,2]){
    let calls=0;
    const {handler}=fixture({fetchImpl:async()=>++calls===failAt?new Response('x'.repeat(40000)):Response.json({id:uid,is_anonymous:false})});
    assert.equal((await invoke(handler)).status,503);
  }
});
test('admission socket timeout aborts before minting and reservations are never refunded or retried',async()=>{
  let calls=0;let aborted=false;
  const {handler}=fixture({upstreamTimeoutMs:15,fetchImpl:async(_url,{signal})=>{
    if(++calls===1)return Response.json({id:uid,is_anonymous:false});
    return new Promise((_,reject)=>signal.addEventListener('abort',()=>{aborted=true;reject(new Error('abort'));},{once:true}));
  }});
  const res=await invoke(handler);assert.equal(res.status,504);assert.equal(calls,2);assert.equal(aborted,true);
  let mints=0;let reservations=0;
  const failed=fixture({fetchImpl:async(url)=>{
    if(url.endsWith('/user'))return Response.json({id:uid,is_anonymous:false});
    if(url.endsWith('/feel_reserve_admission')){reservations++;return Response.json(allowed);}
    mints++;return new Response('provider failure',{status:500});
  }});
  assert.equal((await invoke(failed.handler)).status,502);assert.equal(reservations,1);assert.equal(mints,1);
});
test('two independently constructed handlers consult the same durable admission before concurrent mints',async()=>{
  // This models atomic RPC replies, not PostgreSQL's implementation or locks.
  let reservations=0;let mints=0;
  const fetchImpl=async(url)=>{
    if(url.endsWith('/user'))return Response.json({id:uid,is_anonymous:false});
    if(url.endsWith('/feel_reserve_admission'))return Response.json(++reservations===1?allowed:denied);
    mints++;return Response.json(ephemeral);
  };
  const first=fixture({fetchImpl}),second=fixture({fetchImpl});
  const results=await Promise.all([invoke(first.handler),invoke(second.handler)]);
  assert.deepEqual(results.map(r=>r.status).sort(),[200,429]);assert.equal(reservations,2);assert.equal(mints,1);
});
test('legacy service-role JWT uses both API key and Authorization without accepting a user key',async()=>{
  const legacy=`eyJ.test-header.${Buffer.from('unused').toString('base64url')}`;
  const key=`eyJ.${Buffer.from(JSON.stringify({role:'service_role'})).toString('base64url')}.signature`;
  const cfg=readAdmissionConfig({...env,SUPABASE_SECRET_KEY:'',SUPABASE_SERVICE_ROLE_KEY:key});
  let init;
  await reserveAdmission(uid,'voice_session',cfg,{fetchImpl:async(_url,options)=>{init=options;return Response.json(allowed);}});
  assert.equal(init.headers.Authorization,`Bearer ${key}`);assert.equal(init.headers.apikey,key);
  assert.throws(()=>readAdmissionConfig({...env,SUPABASE_SECRET_KEY:legacy}));
});
test('context production mode uses the same verified principal and durable allowlisted operation',async()=>{
  const config=readContextConfig({...env,CHALK_CLIENT_ID:'test-client',CHALK_CLIENT_SECRET:'test-secret',CHALK_ENV_ID:'test-env',CHALK_CONTEXT_ENGINE_ORIGIN:'https://engine.chalk.ai'});
  const calls=[];
  const handler=createContextHandler({loadConfig:()=>config,fetchImpl:async(url,init)=>{
    calls.push({url,init});
    if(url.endsWith('/user'))return Response.json({id:uid,is_anonymous:false});
    if(url.endsWith('/feel_reserve_admission'))return Response.json(allowed);
    if(url.endsWith('/token'))return Response.json({access_token:'mock-chalk-access-token',engines:{'test-env':'https://engine.chalk.ai'}});
    return Response.json({data:[{field:'object_history.spoken',value:'Keys were at the desk.'}]});
  }});
  const res=await invoke(handler,{url:'/context',headers:{authorization:`Bearer ${token}`,'x-forwarded-proto':'https','content-type':'application/json'},body:{operation:'last_seen',object:'keys'}});
  assert.equal(res.status,200);assert.equal(calls.length,4);
  assert.deepEqual(JSON.parse(calls[1].init.body),{p_user_id:uid,p_operation:'context_last_seen'});
  assert.equal(JSON.parse(calls[3].init.body).inputs['object_history.id'],`${uid}:keys`);
});
test('production context rejects anonymous sessions and quota denial before Chalk OAuth',async()=>{
  for(const anonymous of [true,false]){
    let calls=0;
    const config=readContextConfig({...env,CHALK_CLIENT_ID:'test-client',CHALK_CLIENT_SECRET:'test-secret',CHALK_ENV_ID:'test-env',CHALK_CONTEXT_ENGINE_ORIGIN:'https://engine.chalk.ai'});
    const handler=createContextHandler({loadConfig:()=>config,fetchImpl:async()=>Response.json(++calls===1?{id:uid,is_anonymous:anonymous}:denied)});
    const res=await invoke(handler,{url:'/context',headers:{authorization:`Bearer ${token}`,'x-forwarded-proto':'https','content-type':'application/json'},body:{operation:'last_seen',object:'keys'}});
    assert.equal(res.status,anonymous?403:429);assert.equal(calls,anonymous?1:2);
  }
});
