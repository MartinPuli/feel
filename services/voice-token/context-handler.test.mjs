import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { Readable } from 'node:stream';
import { createContextHandler, readContextConfig } from './context-handler.mjs';
const uid = 'a0000000-0000-4000-8000-000000000001';
const other = 'b0000000-0000-4000-8000-000000000002';
const config = { supabaseOrigin: 'https://example.supabase.co', publishableKey: 'test-public-key',
  clientID: 'test-client', clientSecret: 'test-chalk-secret', environmentID: 'test-env',
  engineOrigin: 'https://engine.chalk.ai', rooms: new Set(['venue:tag']) };
const token = 'test-user-access-token';
const grant = { access_token: 'test-chalk-access-token', engines: { 'test-env': config.engineOrigin } };
const rows = [{ field: 'object_history.spoken', value: 'Keys: last confirmed at the desk.' }];
const headers = { authorization: `Bearer ${token}`, 'x-forwarded-proto': 'https', 'content-type': 'application/json' };
function fixture(options = {}) {
  const calls = [];
  const handler = createContextHandler({ loadConfig: () => config, fetchImpl: async (url, init) => {
    calls.push({ url, init });
    if (url.endsWith('/user')) return Response.json({ id: uid });
    if (url.endsWith('/token')) return Response.json(grant);
    return Response.json({ data: rows });
  }, ...options });
  return { handler, calls };
}
async function invoke(handler, changes = {}) {
  const req = { method: 'POST', url: '/api/context', headers, body: { operation: 'last_seen', object: 'Keys' }, ...changes };
  const res = new EventEmitter();
  res.writeHead = (status, headers) => { res.status = status; res.headers = headers; };
  res.end = value => { res.body = JSON.parse(value); res.writableEnded = true; };
  await handler(req, res); return res;
}
function customResponses(final, auth = { id: uid }, oauth = grant) {
  const calls = [];
  const handler = createContextHandler({ loadConfig: () => config, fetchImpl: async (url, init) => {
    calls.push({url,init});
    const value = calls.length === 1 ? auth : calls.length === 2 ? oauth : final;
    return value instanceof Response ? value : Response.json(value);
  } });
  return {handler,calls};
}
test('verified identity precedes server credential exchange and fixed private query', async () => {
  const { handler, calls } = fixture(); const res = await invoke(handler);
  assert.equal(res.status,200); assert.deepEqual(res.body,{values:{'object_history.spoken':rows[0].value}});
  assert.equal(res.headers['Cache-Control'],'no-store'); assert.equal(calls.length,3);
  assert.equal(calls[0].url,`${config.supabaseOrigin}/auth/v1/user`);
  assert.equal(calls[0].init.headers.Authorization,`Bearer ${token}`);
  assert.deepEqual(JSON.parse(calls[1].init.body),{client_id:config.clientID,client_secret:config.clientSecret,grant_type:'client_credentials'});
  assert.deepEqual(JSON.parse(calls[2].init.body),{inputs:{'object_history.id':`${uid}:keys`},outputs:['object_history.spoken'],query_name:'last_seen'});
  for(const {init} of calls) assert.equal(init.redirect,'error');
});
test('spoofed identity, arbitrary queries and compound-key injection fail before auth',async()=>{
  const {handler,calls}=fixture();
  for(const body of [
    {operation:'last_seen',object:'keys',user_id:other}, {operation:'last_seen',object:'keys',userId:other},
    {operation:'last_seen',object:`${other}:keys`}, {operation:'last_seen',object:'\u202ekeys'},
    {operation:'last_seen',object:'\nkeys'}, {operation:'last_seen',object:''}, {operation:'last_seen',object:'x'.repeat(81)},
    {operation:'last_seen',inputs:{'object_history.id':`${other}:keys`},outputs:['secret.data']},
    {operation:'venue_pack',venue_id:'venue'}, [],null
  ]) assert.equal((await invoke(handler,{body})).status,400);
  assert.equal(calls.length,0);
});
test('verified user id overrides all user metadata and the caller cannot select another user',async()=>{
  const {handler,calls}=customResponses({data:rows},{id:other,user_metadata:{user_id:uid},app_metadata:{user_id:uid}});
  assert.equal((await invoke(handler)).status,200);
  assert.equal(JSON.parse(calls[2].init.body).inputs['object_history.id'],`${other}:keys`);
});
test('revoked or malformed auth cannot reach Chalk or expose upstream errors',async()=>{
  for(const auth of [new Response('secret',{status:401}),new Response('secret',{status:403}),{id:'attacker:keys'},{user:{id:uid}}]){
    const {handler,calls}=customResponses({data:rows},auth); const res=await invoke(handler);
    assert.equal(res.status,401); assert.deepEqual(res.body,{error:'unauthorized'}); assert.equal(calls.length,1);
  }
});
test('rooms require exact server authorization and return only fixed features',async()=>{
  const queries=[];
  const {handler}=fixture({fetchImpl:async(url,init)=>{
    if(url.endsWith('/user'))return Response.json({id:uid});
    if(url.endsWith('/token'))return Response.json(grant);
    const q=JSON.parse(init.body); queries.push(q);
    return Response.json({data:q.outputs.map(field=>({field,value:field.endsWith('.structure')?null:field.endsWith('.structure_visits')?0:field.endsWith('.targets')?'[]':'No targets.'}))});
  }});
  assert.equal((await invoke(handler,{body:{operation:'room_structure',venue_id:'private',tag_id:'room'}})).status,403);
  for(const operation of ['room_structure','room_anchors']){
    const res=await invoke(handler,{body:{operation,venue_id:'venue',tag_id:'tag'}});
    assert.equal(res.status,200); assert.equal(Object.keys(res.body.values).length,operation==='room_structure'?2:1);
    assert.deepEqual(queries.at(-1).inputs,{'room_memory.id':'venue:tag'});
    assert.equal(queries.at(-1).query_name,operation);
  }
});
test('untrusted engine origins and malformed tokens never receive a Chalk credential',async()=>{
  for(const oauth of [
    {...grant,engines:{'test-env':'https://evil.example'}}, {...grant,engines:{'test-env':'https://engine.chalk.ai/other'}},
    {...grant,engines:{'test-env':'http://127.0.0.1'}}, {...grant,engines:{}}, {...grant,access_token:'bad\r\nheader'}
  ]){
    const {handler,calls}=customResponses({data:rows},{id:uid},oauth);
    assert.equal((await invoke(handler)).status,502); assert.equal(calls.length,2);
  }
  const {handler}=fixture({fetchImpl:async()=>new Response('',{status:302,headers:{Location:'https://evil.example'}})});
  assert.equal((await invoke(handler)).status,502);
});
test('extra response features are stripped and missing, duplicate or errored results fail closed',async()=>{
  for(const data of [{data:[]},{errors:[{message:'secret'}],data:rows},{data:[...rows,...rows]},
    {data:[{...rows[0],error:{message:'secret'}}]},{data:[{...rows[0],value:42}]},{data:[{...rows[0],value:'x'.repeat(2001)}]}]){
    const {handler}=customResponses(data); const res=await invoke(handler);
    assert.equal(res.status,502); assert.deepEqual(res.body,{error:'context_unavailable'});
  }
  const {handler}=customResponses({data:[...rows,{field:'secret.data',value:'not returned'}]});
  assert.deepEqual((await invoke(handler)).body,{values:{'object_history.spoken':rows[0].value}});
});
test('request bytes and response bytes are bounded for parsed and streamed data',async()=>{
  const {handler,calls}=fixture();
  assert.equal((await invoke(handler,{body:'x'.repeat(2049)})).status,413);
  assert.equal((await invoke(handler,{body:'{'})).status,400); assert.equal(calls.length,0);
  const stream=Readable.from([Buffer.alloc(2049)]); Object.assign(stream,{method:'POST',url:'/context',headers});
  const res=new EventEmitter(); res.writeHead=status=>{res.status=status;};res.end=()=>{};
  await handler(stream,res); assert.equal(res.status,413);
  for(const stage of [1,3]){
    let count=0;const bounded=fixture({fetchImpl:async()=>{
      count++;if(count===stage)return new Response('x'.repeat(140000));
      return Response.json(count===1?{id:uid}:grant);
    }});
    assert.equal((await invoke(bounded.handler)).status,502);
  }
});
test('absolute deadline includes stalled upstream response body and aborts transport',async()=>{
  let signal; let cancelled = false;
  const {handler}=fixture({timeoutMs:15,fetchImpl:async(_url,init)=>{
    signal=init.signal;return new Response(new ReadableStream({start(){},cancel(){cancelled=true;}}));
  }});
  const res=await invoke(handler); assert.equal(res.status,504);
  assert.deepEqual(res.body,{error:'context_timeout'}); assert.equal(signal.aborted,true); assert.equal(cancelled,true);
});
test('per-user and instance rate limits stop further Chalk exchanges',async()=>{
  const {handler,calls}=fixture({requestsPerMinute:1});
  assert.equal((await invoke(handler)).status,200);assert.equal((await invoke(handler)).status,429);assert.equal(calls.length,4);
  const limited=fixture({instanceRequestsPerMinute:1});
  assert.equal((await invoke(limited.handler)).status,200);assert.equal((await invoke(limited.handler)).status,429);assert.equal(limited.calls.length,3);
});
test('transport method config and exact-path errors are sanitized; session route remains separate',async()=>{
  const {handler,calls}=fixture();
  for(const url of ['/api/session','/api/context?user=other'])assert.equal((await invoke(handler,{url})).status,404);
  assert.equal((await invoke(handler,{method:'GET'})).status,405);
  assert.equal((await invoke(handler,{headers:{'x-forwarded-proto':'http'}})).status,426);
  assert.equal((await invoke(handler,{headers:{'x-forwarded-proto':'https'}})).status,401);assert.equal(calls.length,0);
  const bad=fixture({loadConfig:()=>{throw new Error('secret');}});
  assert.deepEqual((await invoke(bad.handler)).body,{error:'context_not_configured'});
  const failed=fixture({fetchImpl:async()=>{throw new Error('secret');}});
  assert.deepEqual((await invoke(failed.handler)).body,{error:'context_unavailable'});
});
test('config defaults rooms closed and rejects insecure service origins',()=>{
  const env={SUPABASE_URL:config.supabaseOrigin,SUPABASE_PUBLISHABLE_KEY:config.publishableKey,
    CHALK_CLIENT_ID:config.clientID,CHALK_CLIENT_SECRET:config.clientSecret,CHALK_ENV_ID:config.environmentID,
    CHALK_CONTEXT_ENGINE_ORIGIN:config.engineOrigin};
  assert.equal(readContextConfig(env).rooms.size,0);
  for(const bad of ['http://engine.chalk.ai','https://user:pass@engine.chalk.ai','https://engine.chalk.ai/path']){
    assert.throws(()=>readContextConfig({...env,CHALK_CONTEXT_ENGINE_ORIGIN:bad}));
  }
  assert.throws(()=>readContextConfig({...env,CHALK_CONTEXT_ROOMS:'venue:*'}));assert.throws(()=>readContextConfig({}));
});
