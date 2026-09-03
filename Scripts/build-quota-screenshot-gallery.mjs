import { readFile, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';
import { runInNewContext } from 'node:vm';

const directory = resolve(process.argv[2] ?? 'artifacts/quota-boundary-gallery');
const manifest = JSON.parse(await readFile(join(directory, 'manifest.json'), 'utf8'));
let imageCount = 0;
for (const scenario of manifest.scenarios) {
  for (const capture of scenario.captures) {
    const bytes = await readFile(join(directory, capture.file));
    const digest = createHash('sha256').update(bytes).digest('hex');
    if (digest !== capture.sha256) throw new Error(`Checksum mismatch: ${capture.file}`);
    if (bytes.toString('hex', 0, 8) !== '89504e470d0a1a0a') throw new Error(`Invalid PNG: ${capture.file}`);
    if (bytes.readUInt32BE(16) !== capture.pixelWidth || bytes.readUInt32BE(20) !== capture.pixelHeight) {
      throw new Error(`Dimension mismatch: ${capture.file}`);
    }
    imageCount++;
  }
}
const embedded = JSON.stringify(manifest).replaceAll('<', '\\u003c');
const scenarioCount = new Set(manifest.scenarios.map(row => row.id)).size;
const html = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>CodexFloat · 额度边界原生截图</title>
<style>
*{box-sizing:border-box}html{color-scheme:light;scroll-behavior:smooth}body{margin:0;background:#f6f6f4;color:#252727;font:15px/1.65 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}a{color:inherit}header,main,footer{max-width:1200px;margin:auto;padding:32px 24px}h1{font-size:30px;margin:5px 0 12px;letter-spacing:-1px}h2{font-size:21px;margin:0}p{margin:8px 0}.kicker,.metadata{font-size:12px;color:#767b78}.notice{border-left:3px solid #658b78;padding:8px 16px;background:#ecefe9;max-width:960px}.controls{position:sticky;top:0;z-index:2;background:#f6f6f4ee;backdrop-filter:blur(12px);border-block:1px solid #dadeda}.controls>div{max-width:1200px;margin:auto;display:flex;flex-wrap:wrap;align-items:center;gap:16px;padding:14px 24px}label{display:flex;gap:8px;align-items:center;font-size:13px}select{font:inherit;padding:7px;border:1px solid #cbd0ca;border-radius:7px;background:white;max-width:260px}button{font:inherit;background:white;border:1px solid #cbd0ca;border-radius:7px;padding:7px 12px;cursor:pointer}main{padding-top:10px}.case{padding:30px 0 38px;border-bottom:1px solid #d9ddd8;scroll-margin-top:100px}.case-head{display:flex;gap:12px;justify-content:space-between;align-items:start}.tag{font-size:12px;white-space:nowrap;padding:3px 9px;border-radius:5px;background:#e7ece6}.exhausted{background:#f7e4e5;color:#9a3540}.verify{background:#f4ebd9;color:#886323}.note{color:#67716b;max-width:930px}.inputs{font-size:12px;color:#747b76;margin-bottom:22px}.layout{display:grid;grid-template-columns:minmax(270px,.9fr) minmax(320px,1.4fr);gap:24px}.label{font-size:12px;color:#737973;margin:0 0 10px}.compact-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}.shot{margin:0;border:1px solid #dee3dc;border-radius:9px;background:#fff;padding:14px;min-width:0}.shot.full{grid-column:1/-1}.shot figcaption{font-size:12px;color:#757b76;margin-top:10px}.shot a{display:flex;align-items:center;justify-content:center;min-height:84px;text-decoration:none}.shot img{display:block;object-fit:contain;max-width:100%;height:auto}.compact-grid img{width:calc(var(--w)*2px)}.expanded-shot img{width:100%;max-width:680px}.expanded-shot a{min-height:0}.detail-note{font-size:12px;color:#777e77;margin-top:9px}.feedback{margin-top:16px}.feedback img{width:100%;max-width:700px}.count{font-size:12px;color:#7b827a;margin-left:auto}.empty{padding:80px;text-align:center;color:#777}body.dark{background:#1c1f1e;color:#e6ebe7;color-scheme:dark}body.dark .controls{background:#1c1f1eee;border-color:#39413a}body.dark select,body.dark button{background:#292f2b;color:#e6ebe7;border-color:#4a534b}body.dark .shot{background:#282d29;border-color:#414840}body.dark .case{border-color:#3a423c}body.dark .notice{background:#252f29}body.dark .tag{background:#344038}body.dark .exhausted{background:#533337;color:#f0bcc1}body.dark .verify{background:#50442b;color:#e7c78a}body.dark .note,body.dark .inputs,body.dark .metadata,body.dark .label,body.dark figcaption,body.dark .detail-note{color:#a4b0a5}@media(max-width:760px){header,main,footer{padding:22px 16px}.controls>div{padding:12px 16px;gap:10px}.layout{grid-template-columns:1fr}.case-head{display:block}.tag{display:inline-block;margin-top:10px}h1{font-size:25px}h2{font-size:18px}select{max-width:225px}.count{width:100%;margin:0}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
</style></head><body>
<header><div class="kicker">CODEX FLOAT · NATIVE UI EVIDENCE</div><h1>当前额度边界 · 原生界面截图</h1>
<p>${scenarioCount} 类情况 · 亮色 / 暗色 · ${imageCount} 张原始 PNG · ${manifest.appVersion}</p>
<div class="notice"><strong>真实界面，测试额度。</strong>图片来自当前生产代码实际创建的 NSPanel / SwiftUI 窗口，不是设计稿或 AI 生成图；为安全触发边界，使用隔离的固定样本，并非你账号的实时数据。未修改真实额度、未消耗重置次数、未发送系统通知。</div>
<p class="metadata">范围：本轮额度与手动重置边界，不包括任务列表、Tibo 活动等无关模块。菜单栏小图为生产代码的原生绘图输出，不是整个 macOS 菜单栏的桌面截屏。捕获时间：${manifest.capturedAt}。</p>
</header>
<div class="controls"><div>
<label>情况 <select id="scenario"><option value="all">全部 ${scenarioCount} 类</option></select></label>
<label>外观 <select id="theme"><option value="light">亮色</option><option value="dark">暗色</option></select></label>
<label>展开来源 <select id="mode"><option value="standard">完整额度</option><option value="minimal-vertical">极简竖条</option><option value="minimal-horizontal">极简横条</option><option value="minimal-ring">极简圆环</option><option value="menuBar">菜单栏</option></select></label>
<button id="top" type="button">回到顶部</button><span class="count" id="count"></span>
</div></div><main id="gallery"></main>
<footer>点击任意截图可打开原始 PNG。紧凑组件按 2 倍显示方便检查；像素、透明边缘和内容未做修图。应用内气泡由真实通知规划逻辑触发，只有跨过阈值时才出现，不是常驻耗尽卡片。<br><a href="manifest.json">查看样本、原图尺寸与 SHA-256 清单</a></footer>
<script>const evidence=${embedded};
const qs=s=>document.querySelector(s), esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const unique=[...new Map(evidence.scenarios.map(s=>[s.id,s])).values()];
qs('#scenario').innerHTML+=unique.map(s=>'<option value="'+esc(s.id)+'">'+esc(s.title)+'</option>').join('');
function shot(c,extra=''){return '<figure class="shot '+extra+'"><a href="'+esc(c.file)+'" target="_blank" rel="noopener"><img loading="lazy" src="'+esc(c.file)+'?v='+c.sha256.slice(0,12)+'" alt="'+esc(c.label)+'：原生界面截图，测试数据" style="--w:'+c.width+'" width="'+c.pixelWidth+'" height="'+c.pixelHeight+'"></a><figcaption>'+esc(c.label)+' · '+c.width+' × '+c.height+' pt</figcaption></figure>'}
function render(){
 const theme=qs('#theme').value,filter=qs('#scenario').value,mode=qs('#mode').value;
 document.body.classList.toggle('dark',theme==='dark');
 const rows=evidence.scenarios.filter(s=>s.theme===theme&&(filter==='all'||s.id===filter));
 qs('#count').textContent='正在查看 '+rows.length+' 类情况';
 qs('#gallery').innerHTML=rows.map(s=>{
  const f=s.fixture,kind=f.recovery,tag=kind==='exhausted'?'显示手动重置入口':kind==='none'?'不新增重置引导':'先确认 / 查看限制';
  const compacts=s.captures.filter(c=>c.role==='compact');
  const expanded=s.captures.find(c=>c.role==='expanded'&&c.mode===mode);
  const feedback=s.captures.find(c=>c.role==='feedback');
  const inputs='测试输入：5 小时 '+(f.fiveHourRemaining===null?'未返回':f.fiveHourRemaining+'%')+' · 每周 '+(f.weeklyRemaining===null?'未返回':f.weeklyRemaining+'%')+' · 有效重置 '+(f.availableResets===null?'未知':f.availableResets+' 次')+' · 5 小时展示 '+(s.dual?'开启':'默认');
  return '<section class="case" id="'+esc(s.id)+'"><div class="case-head"><h2>'+esc(s.title)+'</h2><span class="tag '+(kind==='exhausted'?'exhausted':kind==='none'?'':'verify')+'">'+tag+'</span></div><p class="note">'+esc(s.note)+'</p><div class="inputs">'+esc(inputs)+'</div><div class="layout"><div><div class="label">收起状态 · 全部形态</div><div class="compact-grid">'+compacts.map(c=>shot(c,c.mode==='standard'?'full':'')).join('')+'</div></div><div><div class="label">展开后的原生窗口 · '+esc(expanded.label)+'</div>'+shot(expanded,'expanded-shot')+(feedback?'<div class="feedback"><div class="label">从 60% 降至当前值时的应用内气泡 · 非系统通知截图</div>'+shot(feedback)+'</div>':'<p class="detail-note">此固定样本不触发应用内阈值气泡。</p>')+'</div></div></section>';
 }).join('');
}
for(const id of ['scenario','theme','mode'])qs('#'+id).addEventListener('change',render);
qs('#top').addEventListener('click',()=>window.scrollTo({top:0,behavior:'smooth'}));render();
</script></body></html>`;
await writeFile(join(directory, 'index.html'), html);
// Check all filter combinations without a browser or network. This verifies
// index behavior, not browser layout or screenshot fidelity.
const controls = new Map();
for (const id of ['scenario', 'theme', 'mode', 'top', 'count', 'gallery']) {
  controls.set('#' + id, {
    value: id === 'scenario' ? 'all' : id === 'theme' ? 'light' : 'standard',
    innerHTML: '', textContent: '', addEventListener() {},
  });
}
const context = {
  document: { querySelector: selector => controls.get(selector), body: { classList: { toggle() {} } } },
  window: { scrollTo() {} },
};
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
runInNewContext(script, context);
let checked = 0;
for (const theme of ['light', 'dark']) {
  for (const mode of ['standard', 'minimal-vertical', 'minimal-horizontal', 'minimal-ring', 'menuBar']) {
    for (const id of ['all', ...new Set(manifest.scenarios.map(row => row.id))]) {
      controls.get('#theme').value = theme;
      controls.get('#mode').value = mode;
      controls.get('#scenario').value = id;
      context.render();
      const actual = (controls.get('#gallery').innerHTML.match(/<section class="case"/g) ?? []).length;
      if (actual !== (id === 'all' ? scenarioCount : 1)) throw new Error('Incorrect case filter');
      checked++;
    }
  }
}
console.log(`Verified ${imageCount} unmodified PNGs across ${scenarioCount} scenarios. Gallery: ${join(directory, 'index.html')}`);
console.log(`Index logic: ${checked} filter combinations passed (not a browser layout check).`);
