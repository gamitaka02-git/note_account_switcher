import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';

const source = await fs.readFile(new URL('../FetchAnalytics.js', import.meta.url), 'utf8');
const metrics = {impressionCount:null,pageViewCount:12,likeCount:3,commentCount:0};
const summary = {data:{dashboardSummary:{lastUpdatedAt:'2026-09-19T12:00:00Z',metrics}}};
const page = (ids, next = false, cursor = null) => ({data:{dashboardNoteListConnection:{
  pageInfo:{hasNextPage:next,endCursor:cursor},
  edges:ids.map(id => ({node:{id,note:{title:id,publishedAt:null,link:{absoluteUrl:'https://note.com/example/n/'+id}},metrics}}))
}}});
function setup(replies, cookie = 'note_gql_auth_token=test-only') {
  const calls = [], document = {cookie};
  const fetch = async (url, options) => {
    calls.push({url,options});
    const next = replies.shift();
    if (!next) throw Error('unexpected request');
    if (url.endsWith('/auth') && !next.status) document.cookie = 'note_gql_auth_token=refreshed-test-only';
    return {ok:!next.status,status:next.status ?? 200,json:async()=>next};
  };
  const context = vm.createContext({fetch, document, location:{origin:'https://note.com'}, AbortSignal, Date, setTimeout});
  vm.runInContext(source,context);
  return {run: async (period='LAST_28_DAYS') => JSON.parse(JSON.stringify(await context.fetchNoteAnalytics(period))),calls};
}
test('combines every page, preserves null impressions and zero comments', async()=>{
  const x=setup([summary,page(['one'],true,'cursor1'),page(['one','two'])]);
  const result=await x.run();
  assert.equal(result.ok,true); assert.equal(result.snapshot.articles.length,2);
  assert.equal(result.snapshot.totals.impressions,null); assert.equal(result.snapshot.totals.comments,0);
  assert.equal(JSON.parse(x.calls[2].options.body).variables.after,'cursor1');
  assert.equal(JSON.stringify(result).includes('test-only'),false);
});
test('logged out state is explicit and contains no partial snapshot', async()=>{
  const x=setup([{status:401}],''); assert.deepEqual(await x.run(),{ok:false,code:'loginRequired'});
});
test('expired token is refreshed once', async()=>{
  const x=setup([{data:null,errors:[{message:'Unauthenticated'}]}, {},summary,page([])]);
  assert.equal((await x.run()).ok,true); assert.equal(x.calls.filter(c=>c.url.endsWith('/auth')).length,1);
});
test('schema changes are not converted into zero', async()=>{
  const x=setup([{data:{dashboardSummary:{metrics:{pv:12}}}}]);
  assert.deepEqual(await x.run(),{ok:false,code:'schemaChanged'});
});
test('page failure discards partial results', async()=>{
  const x=setup([summary,page(['one'],true,'a'),{status:500}]);
  assert.deepEqual(await x.run(),{ok:false,code:'network'});
});
test('repeated cursor is rejected instead of looping', async()=>{
  const x=setup([summary,page(['one'],true,'a'),page(['two'],true,'a')]);
  assert.deepEqual(await x.run(),{ok:false,code:'schemaChanged'});
});
test('invalid period does not access note', async()=>{
  const x=setup([]); assert.equal((await x.run('CUSTOM')).code,'invalidPeriod'); assert.equal(x.calls.length,0);
});
