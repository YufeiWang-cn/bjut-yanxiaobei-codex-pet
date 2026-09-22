'use strict';
const assert=require('node:assert/strict');
const {EventEmitter}=require('node:events');
const http=require('node:http');
const path=require('node:path');
const {execFile}=require('node:child_process');
const {selectRelease,selectAtomRelease,releaseDownload,summarizeReleaseNotes,compare,asciiJSON,fetchReleases,fetchReleasesWithFetch,fetchWindowsFast,fetchWindowsReleases,resolveWindowsProxy,checkWithFetch,checkWindows,ATOM,API,REQUEST_DEADLINE_MS}=require('../windows-companion/update-check');
if(process.argv.includes('--emit-fixture')) {
  process.stdout.write(JSON.stringify({status:'current',summary:'燕小北中文更新说明 — 等待确认'})+'\n');
  process.exit(0);
}
const release=(tag,body='修复审批\n- 改进卸载')=>({tag_name:'v'+tag,body,draft:false,html_url:'https://github.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases/tag/v'+tag,assets:[{name:'bjut-yanxiaobei-windows.zip'}]});
const atom=(tags=['0.2.5'])=>`<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">
<id>tag:github.com,2008:https://github.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases</id>
${tags.map(tag=>`<entry><link rel="alternate" type="text/html" href="https://github.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases/tag/v${tag}"/><content type="html">&lt;h2&gt;燕小北 v${tag}&lt;/h2&gt;&lt;p&gt;修复代理 &amp;amp; 更新检查&lt;/p&gt;</content></entry>`).join('\n')}
</feed>`;
assert.equal(compare('0.2.10','0.2.9'),1);
assert.equal(compare('0.2.3','0.2.3'),0);
assert.equal(selectRelease([release('0.2.4'),release('0.2.10')],'0.2.3').latest,'0.2.10');
assert.equal(selectRelease([release('0.2.3')],'0.2.3').status,'current');
assert.equal(selectRelease([release('0.2.3')],'0.2.4').status,'ahead');
assert.equal(releaseDownload('0.2.6','windows'),'https://github.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases/download/v0.2.6/bjut-yanxiaobei-windows.zip');
assert.equal(selectRelease([release('0.2.6')],'0.2.5').downloads.windows,releaseDownload('0.2.6','windows'));
assert.equal(selectRelease([],'0.2.4').status,'no-release');
assert.equal(selectRelease([{...release('9.0.0'),draft:true},release('0.2.4')],'0.2.3').latest,'0.2.4');
assert.equal(selectRelease([{...release('9.0.0'),assets:[]},release('0.2.4')],'0.2.3').latest,'0.2.4');
assert.equal(selectRelease([{...release('9.0.0'),html_url:'https://evil.example/bad'},release('0.2.4')],'0.2.3').latest,'0.2.4');
assert.match(selectRelease([release('0.2.4')],'0.2.3').summary,/修复审批/);
const detailed=selectRelease([release('0.2.5','# 燕小北 v0.2.5\n## 更新内容\n- 新增右键使用说明\n- 修复自动审批误报等待\n- 优化额度刷新\n## 下载\n请从附件选择平台压缩包')],'0.2.4').summary;
assert.match(detailed,/新增右键使用说明/);assert.match(detailed,/修复自动审批误报等待/);
assert.match(detailed,/优化额度刷新/);assert.doesNotMatch(detailed,/附件选择/);
assert.ok(summarizeReleaseNotes('修复'+'长'.repeat(300)).length<=91);
assert.match(asciiJSON({summary:'燕小北'}),/^\{"summary":"\\u[0-9a-f]{4}/);
assert.deepEqual(JSON.parse(asciiJSON({summary:'燕小北'})),{summary:'燕小北'});
assert.equal(REQUEST_DEADLINE_MS,5000);
assert.equal(selectAtomRelease(atom(['0.2.9','0.2.10']),'0.2.4').latest,'0.2.10');
assert.equal(selectAtomRelease(atom(['0.2.3']),'0.2.4').status,'ahead');
assert.equal(selectAtomRelease(atom([]),'0.2.4').status,'no-release');
assert.match(selectAtomRelease(atom(),'0.2.4').summary,/修复代理 & 更新检查/);
const atomNotes=atom().replace('&lt;p&gt;修复代理 &amp;amp; 更新检查&lt;/p&gt;',
  '&lt;ul&gt;&lt;li&gt;新增使用说明&lt;/li&gt;&lt;li&gt;修复自动审批误报&lt;/li&gt;&lt;li&gt;优化更新弹窗&lt;/li&gt;&lt;/ul&gt;');
assert.match(selectAtomRelease(atomNotes,'0.2.4').summary,/新增使用说明/);
assert.match(selectAtomRelease(atomNotes,'0.2.4').summary,/修复自动审批误报/);
assert.throws(()=>selectAtomRelease(atom().replace('YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases</id>','evil.example/releases</id>'),'0.2.4'),/格式/);
assert.equal(selectAtomRelease(atom().replace('/tag/v0.2.5','/tag/v0.2.5?redirect=evil'),'0.2.4').status,'no-release');
(async()=>{
  let destroyed=false;
  const stalled=()=>{
    const req=new EventEmitter();
    req.destroy=()=>{destroyed=true;};
    return req;
  };
  const started=Date.now();
  await assert.rejects(fetchReleases(stalled,35),/超时/);
  assert.ok(destroyed && Date.now()-started<500,'Hard deadline must include connection setup');
  const rejected=(_url,_options,respond)=>{
    const req=new EventEmitter();req.destroy=()=>{};
    process.nextTick(()=>respond({statusCode:403,resume(){}}));
    return req;
  };
  await assert.rejects(fetchReleases(rejected,100),/限制/);
  const payload=[release('0.2.5','代理连接成功')];
  const urls=[];
  const fetched=await checkWithFetch('0.2.4',async url=>{
    urls.push(url);
    return new Response(atom(),{status:200});
  });
  assert.equal(fetched.latest,'0.2.5');
  assert.deepEqual(urls,[ATOM],'A valid release feed must not spend GitHub REST API quota');
  const fallbackUrls=[];
  const fallback=await checkWithFetch('0.2.4',async url=>{
    fallbackUrls.push(url);
    return url===ATOM ? new Response('rate limited',{status:403}) : new Response(JSON.stringify(payload),{status:200});
  });
  assert.equal(fallback.latest,'0.2.5');
  assert.deepEqual(fallbackUrls,[ATOM,API]);
  await assert.rejects(fetchReleasesWithFetch(async()=>new Response('blocked',{status:403})),/限制/);
  await assert.rejects(fetchReleasesWithFetch((_url,{signal})=>new Promise((_resolve,reject)=>{
    signal.addEventListener('abort',()=>reject(new Error('aborted')));
  }),25),/超时/);
  const base64=Buffer.from(JSON.stringify(payload)).toString('base64');
  const run=(_exe,_args,_opts,callback)=>callback(null,base64+'\n');
  assert.equal((await fetchWindowsReleases(run))[0].tag_name,'v0.2.5');
  const atomRun=(_exe,_args,_opts,callback)=>callback(null,'ATOM|'+Buffer.from(atom()).toString('base64')+'\n');
  assert.equal((await checkWindows('0.2.4',atomRun)).latest,'0.2.5');
  const registry='ProxyEnable    REG_DWORD    0x1\r\nProxyServer    REG_SZ    http://127.0.0.1:7890\r\n';
  const fastCalls=[];
  const fastRun=(file,args,_options,callback)=>{
    fastCalls.push({file,args});
    if(file==='reg.exe') return callback(null,registry);
    if(file==='curl.exe') return callback(null,atom()+'\nYANXIAOBEI_HTTP_STATUS:200');
    callback(new Error('Unexpected process: '+file));
  };
  assert.equal(selectAtomRelease(await fetchWindowsFast(fastRun,{}),'0.2.4').latest,'0.2.5');
  assert.deepEqual(fastCalls.map(call=>call.file),['reg.exe','curl.exe']);
  assert.equal(fastCalls[1].args[fastCalls[1].args.indexOf('--proxy')+1],'http://127.0.0.1:7890/');
  const direct=await resolveWindowsProxy((_file,_args,_options,callback)=>callback(null,'ProxyEnable REG_DWORD 0x0'),{});
  assert.equal(direct.kind,'direct');
  await assert.rejects(resolveWindowsProxy((_file,_args,_options,callback)=>callback(null,
    'ProxyEnable REG_DWORD 0x0\nAutoConfigURL REG_SZ http://proxy.example/proxy.pac'),{}),/系统代理解析/);
  const fastFallbackUrls=[];
  const fastFallback=(_file,args,_options,callback)=>{
    if(_file==='reg.exe') return callback(null,registry);
    const url=args[args.indexOf('--url')+1];fastFallbackUrls.push(url);
    callback(null,(url===ATOM ? 'blocked' : JSON.stringify(payload))+'\nYANXIAOBEI_HTTP_STATUS:'+(url===ATOM?'403':'200'));
  };
  assert.equal((await fetchWindowsFast(fastFallback,{}))[0].tag_name,'v0.2.5');
  assert.deepEqual(fastFallbackUrls,[ATOM,API]);
  await assert.rejects(fetchWindowsReleases((_exe,_args,_opts,callback)=>callback(null,'ERROR|HTTP|403\n')),/限制/);
  await assert.rejects(fetchWindowsReleases((_exe,_args,_opts,callback)=>callback(null,'ERROR|TIMEOUT\n')),/超时/);
  if(process.platform==='win32') {
    let proxied=false;
    const server=http.createServer((request,response)=>{
      proxied=request.url==='http://updates.example.invalid/releases';
      response.setHeader('Content-Type','application/json; charset=utf-8');
      response.end(JSON.stringify(payload));
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    try {
      const script=path.resolve(__dirname,'../windows-companion/Get-ReleaseJson.ps1');
      const proxy=`http://127.0.0.1:${server.address().port}`;
      const result=await new Promise((resolve,reject)=>execFile('powershell.exe',[
        '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',script,
        '-Url','http://updates.example.invalid/releases'
      ],{windowsHide:true,timeout:6000,env:{...process.env,HTTPS_PROXY:proxy,NO_PROXY:''}},
      (error,stdout)=>error?reject(error):resolve(stdout.trim())));
      assert.ok(proxied,'Windows HTTP client must use the configured proxy');
      assert.deepEqual(JSON.parse(Buffer.from(result,'base64').toString('utf8')),payload);
    } finally {server.close();}
  }
  console.log('PASS: release feed, fast proxy/direct checks, API/PowerShell fallback, deadlines and errors');
})().catch(error=>{console.error(error);process.exitCode=1;});
