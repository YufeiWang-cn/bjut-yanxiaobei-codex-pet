'use strict';
const https = require('node:https');
const {execFile} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const API = 'https://api.github.com/repos/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases?per_page=30';
const RELEASES = 'https://github.com/YufeiWang-cn/bjut-yanxiaobei-codex-pet/releases';
const ATOM = RELEASES + '.atom';
const REQUEST_DEADLINE_MS = 5000;
const WINDOWS_DEADLINE_MS = 7500;
const WINDOWS_PROXY_KEY = 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings';
function releaseDownload(remote, platform) {
  if (!version(remote) || !/^(?:windows|macos|native)$/.test(platform)) throw new Error('下载版本或平台无效');
  return `${RELEASES}/download/v${remote}/bjut-yanxiaobei-${platform}.zip`;
}
function version(value) {
  const match = /^v?(\d+)\.(\d+)\.(\d+)$/.exec(String(value || '').trim());
  return match ? match.slice(1).map(Number) : null;
}
function compare(a, b) {
  const x = version(a), y = version(b);
  if (!x || !y) return null;
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i] ? 1 : -1;
  return 0;
}
// Keep the CLI wire format ASCII so Windows PowerShell 5.1 can parse it even
// when launched with a legacy console code page. The in-process Mac API keeps Unicode.
function asciiJSON(value) {
  return JSON.stringify(value).replace(/[\u007f-\uffff]/g,
    char => '\\u' + char.charCodeAt(0).toString(16).padStart(4, '0'));
}
function summarizeReleaseNotes(value) {
  const lines=String(value || '').replace(/\r/g,'').split('\n').map(line=>line
    .replace(/\[([^\]]+)\]\([^)]*\)/g,'$1').replace(/<[^>]*>/g,'')
    .replace(/^[\s#>*•\-\d.)]+/g,'').replace(/[\u0000-\u0009\u000b-\u001f\u007f]/g,'')
    .replace(/[*_`]/g,'').replace(/\s+/g,' ').trim()).filter(Boolean);
  const useful=lines.filter(line=>!/^https?:\/\/|^(?:更新内容|更新日志|下载|安装|附件|校验|changelog|assets)\s*[:：]?$/i.test(line));
  const changes=useful.filter(line=>/^(?:修复|新增|优化|改进|增加|支持|调整|解决|feat|fix|perf|improve)(?:\b|[:：\s]|[\u4e00-\u9fff])/i.test(line));
  const selected=changes.length?changes:useful;
  const unique=[...new Set(selected)].slice(0,5).map(line=>line.length>90?line.slice(0,89)+'…':line);
  return unique.join('\n').slice(0,460)||'此版本没有填写更新说明。';
}
function selectRelease(items, local) {
  if (!Array.isArray(items)) throw new Error('发布列表格式错误');
  const releases = items.filter(r => r && !r.draft && version(r.tag_name) &&
    Array.isArray(r.assets) && r.assets.some(a => /^bjut-yanxiaobei-(?:native|windows|macos)\.zip$/.test(a.name || '')) &&
    /^https:\/\/github\.com\/YufeiWang-cn\/bjut-yanxiaobei-codex-pet\/releases\/tag\/v?\d+\.\d+\.\d+$/.test(r.html_url || ''));
  releases.sort((a, b) => compare(b.tag_name, a.tag_name));
  const latest = releases[0];
  if (!latest) return {status:'no-release',local,link:RELEASES};
  const remote = latest.tag_name.replace(/^v/, '');
  const difference = compare(remote, local);
  return {status:difference > 0 ? 'update' : difference < 0 ? 'ahead' : 'current',local,latest:remote,
    link:latest.html_url,
    summary:summarizeReleaseNotes(latest.body),
    downloads:{windows:releaseDownload(remote,'windows'),macos:releaseDownload(remote,'macos'),native:releaseDownload(remote,'native')}};
}
function decodeEntities(value) {
  return value.replace(/&(#x[0-9a-f]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp);/gi,(entity,name) => {
    if (name[0] === '#') {
      const number=name[1].toLowerCase()==='x' ? parseInt(name.slice(2),16) : Number(name.slice(1));
      return number > 0 && number <= 0x10ffff && !(number >= 0xd800 && number <= 0xdfff)
        ? String.fromCodePoint(number) : '';
    }
    return {amp:'&',lt:'<',gt:'>',quot:'"',apos:"'",nbsp:' '}[name.toLowerCase()];
  });
}
function selectAtomRelease(xml, local) {
  if (typeof xml !== 'string' || xml.length > 512*1024 ||
      !/<feed\b[^>]*xmlns="http:\/\/www\.w3\.org\/2005\/Atom"/.test(xml) ||
      !xml.includes('<id>tag:github.com,2008:'+RELEASES+'</id>')) throw new Error('发布订阅格式错误');
  const candidates=[];
  for (const entry of xml.match(/<entry\b[^>]*>[\s\S]*?<\/entry>/g) || []) {
    const links=entry.match(/<link\b[^>]*\/?\s*>/g) || [];
    const link=links.map(tag=>/\bhref="([^"]+)"/.exec(tag)?.[1]).find(url=>
      /^https:\/\/github\.com\/YufeiWang-cn\/bjut-yanxiaobei-codex-pet\/releases\/tag\/v?\d+\.\d+\.\d+$/.test(url || ''));
    if (!link) continue;
    const tag=link.slice(link.lastIndexOf('/')+1);
    const content=/<content\b[^>]*type="html"[^>]*>([\s\S]*?)<\/content>/.exec(entry)?.[1] || '';
    const html=decodeEntities(content);
    const plain=html.replace(/<\/?(?:p|li|h[1-6]|ul|div|br)\b[^>]*>/gi,'\n').replace(/<[^>]*>/g,'');
    candidates.push({tag,link,summary:summarizeReleaseNotes(decodeEntities(plain))});
  }
  candidates.sort((a,b)=>compare(b.tag,a.tag));
  if (!candidates.length) return {status:'no-release',local,link:RELEASES};
  const latest=candidates[0],remote=latest.tag.replace(/^v/,'');
  const difference=compare(remote,local);
  return {status:difference > 0 ? 'update' : difference < 0 ? 'ahead' : 'current',
    local,latest:remote,link:latest.link,summary:latest.summary,
    downloads:{windows:releaseDownload(remote,'windows'),macos:releaseDownload(remote,'macos'),native:releaseDownload(remote,'native')}};
}
function fetchReleases(get = https.get, deadlineMs = REQUEST_DEADLINE_MS) {
  return new Promise((resolve,reject) => {
    let req, finished = false;
    const settle = (error, value) => {
      if (finished) return;
      finished = true;
      clearTimeout(deadline);
      if (error) reject(error); else resolve(value);
    };
    // A socket timeout alone does not cover DNS resolution or connection setup.
    const deadline = setTimeout(() => {
      if (req) req.destroy();
      settle(new Error('连接 GitHub 超时；请检查网络或代理设置'));
    }, deadlineMs);
    try {
      req = get(API,{headers:{'User-Agent':'BJUT-YanXiaoBei-update-check','Accept':'application/vnd.github+json'},timeout:deadlineMs},res => {
        if (res.statusCode !== 200) {
          res.resume();
          settle(new Error(res.statusCode === 403 || res.statusCode === 429
            ? 'GitHub 暂时限制了更新查询，请稍后重试' : 'GitHub 返回 HTTP '+res.statusCode));
          return;
        }
        let body='';
        res.setEncoding('utf8');
        res.on('data',part=>{
          body+=part;
          if(body.length>512*1024) { req.destroy(); settle(new Error('发布列表响应过大')); }
        });
        res.on('end',()=>{try{settle(null,JSON.parse(body));}catch{settle(new Error('发布列表无效'));}});
        res.on('error',()=>settle(new Error('读取 GitHub 响应失败')));
      });
      req.on('timeout',()=>{req.destroy();settle(new Error('连接 GitHub 超时；请检查网络或代理设置'));});
      req.on('error',()=>settle(new Error('无法连接 GitHub；请检查网络或代理设置')));
    } catch { settle(new Error('无法发起 GitHub 更新查询')); }
  });
}
async function check(local, get) { if (!version(local)) throw new Error('本地版本号无效');return selectRelease(await fetchReleases(get),local); }
async function fetchBodyWithFetch(fetcher, url, deadlineMs, accept) {
  const controller = new AbortController();
  let timer, expired=false;
  const timedOut = new Promise((_,reject) => {
    timer = setTimeout(() => {expired=true;controller.abort();reject(new Error('连接 GitHub 超时；请检查系统代理是否可用'));},deadlineMs);
  });
  const request = async () => {
    const response = await fetcher(url,{headers:{'User-Agent':'BJUT-YanXiaoBei-update-check','Accept':accept},signal:controller.signal,cache:'no-store'});
    if (!response.ok) throw new Error(response.status === 403 || response.status === 429
      ? 'GitHub 暂时限制了更新查询，请稍后重试' : 'GitHub 返回 HTTP '+response.status);
    if (Number(response.headers.get('content-length')) > 512*1024) throw new Error('发布列表响应过大');
    const reader = response.body.getReader();
    const chunks=[];let size=0;
    for (;;) {
      const {done,value}=await reader.read();
      if (done) break;
      size+=value.length;
      if (size > 512*1024) {controller.abort();throw new Error('发布列表响应过大');}
      chunks.push(Buffer.from(value));
    }
    return Buffer.concat(chunks).toString('utf8');
  };
  try {return await Promise.race([request(),timedOut]);}
  catch (error) {
    if (expired) throw new Error('连接 GitHub 超时；请检查系统代理是否可用');
    if (/^(GitHub |发布列表)/.test(error.message)) throw error;
    throw new Error('无法连接 GitHub；请检查系统代理或网络设置');
  }
  finally {clearTimeout(timer);}
}
async function fetchReleasesWithFetch(fetcher, deadlineMs = REQUEST_DEADLINE_MS) {
  try {return JSON.parse(await fetchBodyWithFetch(fetcher,API,deadlineMs,'application/vnd.github+json'));}
  catch (error) {
    if (error instanceof SyntaxError) throw new Error('发布列表无效');
    throw error;
  }
}
async function checkWithFetch(local,fetcher) {
  if (!version(local)) throw new Error('本地版本号无效');
  const started=Date.now();
  try {return selectAtomRelease(await fetchBodyWithFetch(fetcher,ATOM,3500,'application/atom+xml'),local);}
  catch (atomError) {
    const remaining=REQUEST_DEADLINE_MS-(Date.now()-started);
    if (remaining < 250) throw atomError;
    return selectRelease(await fetchReleasesWithFetch(fetcher,remaining),local);
  }
}
function execute(run, file, args, options) {
  return new Promise((resolve,reject) => run(file,args,options,(error,stdout) =>
    error ? reject(error) : resolve(String(stdout || ''))));
}
function fixedProxy(value) {
  const selected=value.includes(';') ? value.split(';').map(part=>part.trim()).find(part=>/^https=/i.test(part))?.slice(6) : value;
  if (!selected) return null;
  const candidate=/^[a-z][a-z0-9+.-]*:\/\//i.test(selected) ? selected : 'http://'+selected;
  try {
    const parsed=new URL(candidate);
    if (!['http:','https:','socks5:','socks5h:'].includes(parsed.protocol) ||
        !parsed.hostname || !parsed.port || parsed.username || parsed.password ||
        parsed.pathname !== '/' || parsed.search || parsed.hash) return null;
    return parsed.href;
  } catch {return null;}
}
async function resolveWindowsProxy(run = execFile, env = process.env) {
  if (env.HTTPS_PROXY || env.https_proxy || env.ALL_PROXY || env.all_proxy) return {kind:'environment'};
  const output=await execute(run,'reg.exe',['query',WINDOWS_PROXY_KEY],
    {windowsHide:true,timeout:900,maxBuffer:32*1024,encoding:'utf8'});
  const enabled=/^\s*ProxyEnable\s+REG_DWORD\s+0x1\s*$/mi.test(output);
  const pac=/^\s*AutoConfigURL\s+REG_\w+\s+\S+/mi.test(output) ||
    /^\s*AutoDetect\s+REG_DWORD\s+0x1\s*$/mi.test(output);
  if (pac) throw new Error('需要系统代理解析');
  if (!enabled) return {kind:'direct'};
  const address=/^\s*ProxyServer\s+REG_\w+\s+([^\r\n]+)$/mi.exec(output)?.[1]?.trim();
  const proxy=address && fixedProxy(address);
  if (!proxy) throw new Error('需要系统代理解析');
  return {kind:'fixed',proxy};
}
async function curlBody(run, url, proxy, timeoutMs, accept) {
  const marker='\nYANXIAOBEI_HTTP_STATUS:';
  const args=['-q','--silent','--show-error','--max-time',String(Math.max(0.2,timeoutMs/1000)),
    '--connect-timeout','2','--max-filesize','524288','--proto','=https',
    '--header','User-Agent: BJUT-YanXiaoBei-update-check','--header','Accept: '+accept,
    '--write-out',marker+'%{http_code}'];
  if (proxy.kind==='fixed') args.push('--proxy',proxy.proxy);
  if (proxy.kind==='direct') args.push('--noproxy','*');
  args.push('--url',url);
  const output=await execute(run,'curl.exe',args,
    {windowsHide:true,timeout:timeoutMs+350,maxBuffer:700*1024,encoding:'utf8'});
  const split=output.lastIndexOf(marker);
  if (split<0) throw new Error('GitHub 响应格式错误');
  const status=Number(output.slice(split+marker.length).trim());
  if (status!==200) throw new Error(status===403 || status===429
    ? 'GitHub 暂时限制了更新查询，请稍后重试' : 'GitHub 返回 HTTP '+status);
  return output.slice(0,split);
}
async function fetchWindowsFast(run = execFile, env = process.env) {
  const started=Date.now();
  let proxy;
  try {proxy=await resolveWindowsProxy(run,env);}
  catch (error) {error.fallback=true;throw error;}
  let atomError;
  try {
    const body=await curlBody(run,ATOM,proxy,3500,'application/atom+xml');
    selectAtomRelease(body,'0.0.0');
    return body;
  } catch (error) {atomError=error;}
  const remaining=REQUEST_DEADLINE_MS-(Date.now()-started);
  if (remaining<500) {atomError.fallback=true;throw atomError;}
  try {
    const body=await curlBody(run,API,proxy,remaining,'application/vnd.github+json');
    return JSON.parse(body);
  } catch (error) {
    if (!/^GitHub 返回 HTTP |^GitHub 暂时限制/.test(error.message)) error.fallback=true;
    throw error;
  }
}
function fetchWindowsReleases(run = execFile, deadlineMs = WINDOWS_DEADLINE_MS) {
  return new Promise((resolve,reject) => {
    run('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'Get-ReleaseJson.ps1'),
      '-TimeoutMilliseconds',String(Math.max(500,deadlineMs-1000))],
      {windowsHide:true,timeout:deadlineMs,maxBuffer:1024*1024,encoding:'utf8'},(error,stdout) => {
        if (error) {
          reject(new Error(error.killed || error.code === 'ETIMEDOUT' ? '连接 GitHub 超时；请检查系统代理是否可用'
            : '无法连接 GitHub；请检查系统代理或网络设置'));
          return;
        }
        const output=String(stdout || '').trim();
        if (output.startsWith('ERROR|HTTP|')) {
          const status=Number(output.slice(11));
          reject(new Error(status === 403 || status === 429 ? 'GitHub 暂时限制了更新查询，请稍后重试' : 'GitHub 返回 HTTP '+status));
          return;
        }
        if (output.startsWith('ERROR|TIMEOUT')) {reject(new Error('连接 GitHub 超时；请检查系统代理是否可用'));return;}
        if (output.startsWith('ERROR|')) {reject(new Error('无法连接 GitHub；请检查系统代理或网络设置'));return;}
        try { resolve(output.startsWith('ATOM|') ? Buffer.from(output.slice(5),'base64').toString('utf8')
          : JSON.parse(Buffer.from(output,'base64').toString('utf8'))); }
        catch { reject(new Error('发布列表无效')); }
      });
  });
}
async function checkWindows(local, run) {
  if (!version(local)) throw new Error('本地版本号无效');
  const started=Date.now();
  let releases;
  if (run) releases=await fetchWindowsReleases(run);
  else {
    try {releases=await fetchWindowsFast();}
    catch (error) {
      const remaining=WINDOWS_DEADLINE_MS-(Date.now()-started);
      if (!error.fallback || remaining<1700) throw error;
      releases=await fetchWindowsReleases(execFile,remaining);
    }
  }
  return typeof releases === 'string' ? selectAtomRelease(releases,local) : selectRelease(releases,local);
}
if (require.main === module) {
  const local = fs.readFileSync(path.resolve(__dirname,'..','VERSION.txt'),'utf8').trim();
  (process.platform === 'win32' ? checkWindows(local) : check(local)).then(result=>process.stdout.write(asciiJSON(result)+'\n'),error=>{
    process.stdout.write(asciiJSON({status:'error',local,message:error.message})+'\n');
  });
}
module.exports={version,compare,asciiJSON,releaseDownload,summarizeReleaseNotes,selectRelease,selectAtomRelease,fetchReleases,fetchReleasesWithFetch,fetchWindowsFast,fetchWindowsReleases,resolveWindowsProxy,check,checkWithFetch,checkWindows,API,ATOM,RELEASES,REQUEST_DEADLINE_MS,WINDOWS_DEADLINE_MS};
