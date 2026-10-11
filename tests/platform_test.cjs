const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('platform/yandex_bridge.js', 'utf8');
let checks = 0;
const check = (value, description) => { assert.ok(value, description); checks++; };
const turn = () => new Promise(resolve => setImmediate(resolve));

(async () => {
  const calls = [], listeners = {}, visibility = {};
  let callbacks, cloud, fail = false;
  const player = {
    async setData(value, flush) { if (fail) throw Error('offline'); cloud = value; calls.push(['save',flush]); },
    async getData(keys) { if (fail) throw Error('offline'); calls.push(['load',keys]); return cloud || {}; }
  };
  const sdk = {
    features: {LoadingAPI:{ready:()=>calls.push('ready')}, GameplayAPI:{start:()=>calls.push('start'),stop:()=>calls.push('stop')}},
    on(name, callback) { listeners[name] = callback; },
    async getPlayer(options) { calls.push(['player',options]); return player; },
    adv:{showRewardedVideo(options) { callbacks=options.callbacks; }}
  };
  const document = {hidden:false,addEventListener:(name,cb)=>visibility[name]=cb};
  const window = {YaGames:{init:async()=>sdk}};
  vm.runInNewContext(source,{window,document,location:{hostname:'localhost'}});
  const api=window.LittleWorldsPlatform;
  api.ready(); await turn();
  check(calls.filter(c=>c==='ready').length===1,'ready happens after SDK init and game readiness');
  api.ready(); check(calls.filter(c=>c==='ready').length===1,'ready is idempotent');
  check(JSON.parse(api.poll()).some(e=>e.kind==='available'),'SDK availability reaches the game');
  api.gameplay('start'); check(calls.at(-1)==='start','gameplay starts'); api.poll();
  listeners.game_api_pause(); check(JSON.parse(api.poll()).some(e=>e.kind==='suspend'&&e.value),'SDK pause suspends game');
  listeners.game_api_resume(); check(JSON.parse(api.poll()).some(e=>e.kind==='suspend'&&!e.value),'SDK resume releases pause');
  document.hidden=true; visibility.visibilitychange(); check(calls.at(-1)==='stop','hidden browser tab stops gameplay');
  document.hidden=false; visibility.visibilitychange(); check(calls.at(-1)==='start','visible tab resumes gameplay'); api.poll();
  api.rewarded(); callbacks.onOpen(); callbacks.onRewarded(); callbacks.onRewarded(); callbacks.onClose(); callbacks.onClose();
  let events=JSON.parse(api.poll());
  check(events.filter(e=>e.kind==='reward').length===1,'duplicate rewarded callbacks grant one reward');
  check(events.at(-1).kind==='suspend'&&!events.at(-1).value,'ad close resumes');
  api.rewarded(); callbacks.onError(Error('offline')); events=JSON.parse(api.poll());
  check(!events.some(e=>e.kind==='reward')&&events.some(e=>e.kind==='suspend'&&!e.value),'failed ad resumes without reward');
  await api.save('compressed-world'); check(cloud.littleWorldsV7==='compressed-world','cloud stores the supplied snapshot');
  check(calls.some(c=>Array.isArray(c)&&c[0]==='player'&&c[1].scopes===false),'player access requests no extended scopes');
  api.poll(); await api.load(); check(JSON.parse(api.poll()).some(e=>e.kind==='cloud'&&e.data==='compressed-world'),'cloud load returns stored payload');
  fail=true; await api.save('next'); check(JSON.parse(api.poll()).some(e=>e.kind==='message'),'cloud errors report local fallback');
  fail=false; await api.save('after-error'); check(cloud.littleWorldsV7==='after-error','cloud operations recover after failure');
  const offlineWindow={};
  vm.runInNewContext(source,{window:offlineWindow,document:{hidden:false,addEventListener(){}},location:{hostname:'localhost'}});
  offlineWindow.LittleWorldsPlatform.ready(); offlineWindow.LittleWorldsPlatform.gameplay('start');
  check(JSON.parse(offlineWindow.LittleWorldsPlatform.poll()).length===1,'standalone site works without SDK');
  console.log(`Platform: ${checks} checks, 0 failures.`);
})().catch(error=>{console.error(error);process.exitCode=1;});
