'use strict';
// A deliberately small renderer for BEGINNER.md: no dependencies or remote assets.
const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..');
const escape=text=>text.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
function inline(text){return escape(text).replace(/\[([^\]]+)\]\((https:\/\/[^\s)]+)\)/g,'<a href="$2" rel="noreferrer">$1</a>').replace(/`([^`]+)`/g,'<code>$1</code>');}
function render(source,version){
  let code=false,list=false,out=[],sections=[];const close=()=>{if(list){out.push('</ul>');list=false;}};
  for(const line of source.replace(/\r/g,'').trimEnd().split('\n')){
    if(line.startsWith('```')){close();out.push(code?'</code></pre>':'<pre><code>');code=!code;continue;}
    if(code){out.push(escape(line)+'\n');continue;}
    if(!line.trim()){close();continue;}
    const heading=line.match(/^(#{1,3}) (.+)$/);
    if(heading){close();const level=heading[1].length;let id='';if(level===2){id='section-'+sections.length;sections.push({id,title:heading[2]});}out.push(`<h${level}${id?' id="'+id+'"':''}>${inline(heading[2])}</h${level}>`);continue;}
    if(line.startsWith('- ')){if(!list){out.push('<ul>');list=true;}out.push('<li>'+inline(line.slice(2))+'</li>');continue;}
    close();out.push('<p>'+inline(line)+'</p>');
  }
  close();if(code)throw Error('Unclosed code block in beginner guide');
  const shortTitle=title=>title.startsWith('A.')?'Windows 安装':title.startsWith('B.')?'原生素材安装':title.startsWith('C.')?'Mac 安装':title.startsWith('第一')?'选下载包':title.startsWith('第二')?'怎样解压':title.startsWith('第三')?'日常使用':title.startsWith('第四')?'更新与卸载':'更多说明';
  const navigation='<nav aria-label="快速跳转" style="display:flex;flex-wrap:wrap;gap:8px;padding:16px 0">'+sections.map(s=>`<a href="#${s.id}" style="padding:5px 12px;border-radius:8px;background:#e9f3f6;text-decoration:none">${shortTitle(s.title)}</a>`).join('')+'</nav>';
  out.splice(1,0,navigation);
  return `<!doctype html>\n<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><title>燕小北 · 安装先读我</title><style>body{margin:0;background:#f3f6fa;color:#1b3142;font:16px/1.85 system-ui,-apple-system,"Microsoft YaHei",sans-serif}main{max-width:880px;margin:32px auto;padding:32px 44px;background:white;border-radius:20px;box-shadow:0 8px 35px #1830470d}h1{font-size:30px;line-height:1.4}h2{margin-top:44px;padding-top:20px;border-top:1px solid #dce5eb;color:#12687b;font-size:23px;line-height:1.5}h3{margin-top:30px;font-size:19px}p,li{overflow-wrap:anywhere}li{margin:10px 0}a{color:#086f8b}pre{background:#152d40;color:#e6f9fc;padding:16px 20px;border-radius:10px;white-space:pre-wrap;overflow-wrap:anywhere;user-select:all;line-height:1.6}code{font-family:ui-monospace,Consolas,monospace}.version{color:#687e8d;font-size:14px}@media(max-width:600px){main{margin:0;padding:22px;border-radius:0}h1{font-size:25px}}@media print{body,main{background:white;box-shadow:none;margin:0;padding:0}pre{color:black;background:#eee}}</style></head><body><main><div class="version">BJUT 燕小北 · 个人制作 · v${escape(version)} · 可离线阅读</div>${out.join('\n')}<p class="version">本页面从 docs/BEGINNER.md 自动生成；内容更新请改原文后重新生成，不要手改本页。</p></main></body></html>\n`;
}
if(require.main===module){
  const html=render(fs.readFileSync(path.join(root,'docs/BEGINNER.md'),'utf8'),fs.readFileSync(path.join(root,'VERSION.txt'),'utf8').trim());
  const dest=path.join(root,'START-HERE.html');
  if(process.argv.includes('--check')){if(!fs.existsSync(dest)||fs.readFileSync(dest,'utf8')!==html)throw Error('START-HERE.html is stale; run node scripts/Render-StartHere.cjs');console.log('PASS: offline guide matches beginner source');}
  else{fs.writeFileSync(dest,html);console.log('Generated START-HERE.html (offline, no scripts or external assets)');}
}
module.exports={render};
