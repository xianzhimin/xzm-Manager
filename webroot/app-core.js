/* ══════════════════════════════════════════════
   xzm 管理器 · 前端逻辑
   桥接层：优先用 KernelSU exec()，否则用本机降级（调试用）
   ══════════════════════════════════════════════ */

const MODDATA = '/data/adb/xzm_manager';
const CTL = MODDATA + '/bin/../../..'; // 占位，实际用模块路径
let moduleDir = '/data/adb/modules/xzm_manager'; // 会被探测覆盖

/* ── 桥接：执行 shell ── */
let ksu = null;
let bridgeKind = 'fallback';

async function initBridge(){
  // 独立 WebUI 本地服务：页面通过 http(s) 加载，且同源提供 cgi-bin/shell —— 优先
  if(location.protocol === 'http:' || location.protocol === 'https:'){
    try{
      const probe = await httpShell('echo __xzm_probe__');
      if((probe.out||'').includes('__xzm_probe__')){
        bridgeKind = 'httpcgi'; return 'httpcgi';
      }
    }catch(e){ /* 非本服务，继续尝试 ksu */ }
  }
  // 电脑预览/调试：强制降级模式（?demo=1）
  const forceDemo = /[?&]demo=1/.test(location.search);
  if(forceDemo){
    bridgeKind = 'fallback'; return 'fallback';
  }
  // 1) window.ksu 原生注入对象（回调式）—— 先探测确认真的能用
  if(window.ksu && typeof window.ksu.exec === 'function'){
    ksu = window.ksu;
    const probe = await ksuExecCallback('echo __xzm_probe__');
    if((probe.out||'').includes('__xzm_probe__')){
      bridgeKind = 'ksu-global'; return 'kernelsu';
    }
  }
  // 2) 官方 npm 包（CDN）—— 用经典 script 注入，避免动态 import() 在旧 WebView 上 SyntaxError
  //    注意：只有在 window.ksu 不可用时才尝试
  try{
    const m = await loadKernelsuCdn();
    if(m && typeof m.exec === 'function'){
      try{
        const probe = await m.exec('echo __xzm_probe__');
        if(probe && (probe.stdout||'').includes('__xzm_probe__')){
          ksu = m; bridgeKind = 'kernelsu-cdn'; return 'kernelsu';
        }
      }catch(e){ /* 无效 */ }
    }
  }catch(e){ /* 降级 */ }
  bridgeKind = 'fallback';
  return 'fallback';
}

/* 通过 <script> 注入加载 kernelsu CDN 包（返回其默认导出），带超时 */
function loadKernelsuCdn(){
  return new Promise((resolve)=>{
    var done = false;
    var finish = (v)=>{ if(!done){ done=true; resolve(v); } };
    setTimeout(()=>finish(null), 3000);
    try{
      var s = document.createElement('script');
      s.type = 'module';
      s.textContent = "import ksu from 'https://cdn.jsdelivr.net/npm/kernelsu/+esm'; window.__xzm_ksu_cdn = ksu;";
      s.onload = ()=>finish(window.__xzm_ksu_cdn || null);
      s.onerror = ()=>finish(null);
      document.head.appendChild(s);
      // module 脚本无可靠 onload 时，轮询兜底
      var tries = 0;
      var iv = setInterval(()=>{
        tries++;
        if(window.__xzm_ksu_cdn){ clearInterval(iv); finish(window.__xzm_ksu_cdn); }
        else if(tries>30){ clearInterval(iv); finish(null); }
      }, 100);
    }catch(e){ finish(null); }
  });
}

/* ── 调用原生 ksu.exec（回调式）：ksu.exec(cmd, optsJson, callbackName) ── */
function ksuExecCallback(cmd){
  return new Promise((resolve)=>{
    const cbName = '__xzm_cb_' + Date.now() + '_' + Math.floor(Math.random()*100000);
    let done = false;
    window[cbName] = (errno, stdout, stderr)=>{
      if(done) return; done = true;
      try{ delete window[cbName]; }catch(e){}
      resolve({ code: (errno === undefined || errno === null) ? 0 : errno, out: stdout || '', err: stderr || '' });
    };
    try{
      // 原生签名：exec(cmd, optionsJson, callbackName) —— 无返回值
      window.ksu.exec(cmd, '{}', cbName);
    }catch(e){
      resolve({ code:1, out:'', err:'ksu.exec 调用异常: '+String(e) });
    }
    // 兜底超时
    setTimeout(()=>{ if(!done){ done=true; resolve({ code:124, out:'', err:'ksu.exec 超时无回调' }); } }, 15000);
  });
}

/* ── HTTP CGI 桥接（独立 WebUI 本地服务的 cgi-bin/shell）── */
async function httpShell(cmd){
  // 短命令用 GET（便于日志），长命令用 POST（避免 URL 长度限制）
  let r;
  if(cmd.length < 1500){
    r = await fetch('cgi-bin/shell?cmd=' + encodeURIComponent(cmd), { cache:'no-store', method:'GET' });
  }else{
    r = await fetch('cgi-bin/shell', { cache:'no-store', method:'POST', body: cmd });
  }
  const t = await r.text();
  return { code: r.ok ? 0 : r.status, out: t, err: r.ok ? '' : ('HTTP ' + r.status) };
}

async function sh(cmd){
  // 0) 独立 WebUI 本地服务：同源 CGI（busybox httpd）
  if(bridgeKind === 'httpcgi'){
    try{ return await httpShell(cmd); }
    catch(e){ return { code:1, out:'', err:'httpcgi 异常: '+String(e) }; }
  }
  if(ksu){
    try{
      // 兼容两种形态：
      // A) npm 包封装：exec(cmd) 返回 Promise<{errno,stdout,stderr}>
      // B) 原生注入：window.ksu.exec(cmd, optsJson, cbName) 回调式，无返回值
      if(ksu === (window.ksu) && typeof window.ksu.exec === 'function' && window.ksu.exec.length >= 3){
        return await ksuExecCallback(cmd);
      }
      const r = await ksu.exec(cmd);
      if(r && typeof r === 'object' && ('stdout' in r || 'errno' in r)){
        return { code: (r.errno === undefined || r.errno === null) ? 0 : r.errno, out: r.stdout || '', err: r.stderr || '' };
      }
      // 返回的不是预期结构 → 退回回调式
      return await ksuExecCallback(cmd);
    }catch(e){
      return { code:1, out:'', err:'ksu.exec 异常: '+String(e) };
    }
  }
  // 降级：本机调试服务器
  try{
    const r = await fetch('/__shell__', { method:'POST', body: cmd, cache:'no-store' });
    const t = await r.text();
    return { code: r.ok?0:r.status, out:t, err: r.ok?'':('HTTP '+r.status) };
  }catch(e){
    return { code:127, out:'', err:'无执行环境（未检测到 KernelSU，且非调试模式）: '+String(e) };
  }
}

/* ── 后端调用：跑 xzmctl.sh，返回 JSON ── */
async function ctl(action, args = []){
  const quoted = args.map(a => `'${String(a).replace(/'/g, "'\\''")}'`).join(' ');
  const cmd = `XZM_DATA_DIR=${MODDATA} sh ${moduleDir}/bin/xzmctl.sh ${action} ${quoted} 2>&1`;
  const r = await sh(cmd);
  const raw = (r.out || '').trim();
  // 取最后一个非空行尝试解析为 JSON
  const lines = raw.split('\n').map(s=>s.trim()).filter(Boolean);
  for(let i = lines.length-1; i >= 0; i--){
    const ln = lines[i];
    if(ln.startsWith('{') || ln.startsWith('[')){
      try{ return JSON.parse(ln); }catch(e){ /* 继续找上一行 */ }
    }
  }
  return { ok:false, error:'后端响应异常: ' + (raw ? raw.slice(0,200) : (r.err||'empty')) +
    ` [bridge=${bridgeKind}, modDir=${moduleDir}, code=${r.code}]` };
}

/* ── 探测模块目录 ── */
async function detectModuleDir(){
  const probe = await sh(`[ -f ${moduleDir}/bin/xzmctl.sh ] && echo yes`);
  if(probe.out.trim()==='yes') return;
  // 尝试各管理器常见路径
  for(const p of ['/data/adb/modules/xzm_manager',
                  '/data/adb/modules_update/xzm_manager',
                  '/data/adb/ap/modules/xzm_manager']){
    const t = await sh(`[ -f ${p}/bin/xzmctl.sh ] && echo yes`);
    if(t.out.trim()==='yes'){ moduleDir = p; return; }
  }
}

/* ── 状态 ── */
const state = {
  active: 'A',
  path: { A:'/sdcard', B:'/sdcard/Download' },
  entries:{ A:[], B:[] },
  selected: { A:null, B:null },
  multi: new Set(),
  multiMode:false,
  history:{ A:[], B:[] },
  bookmarks: [],
  editorPath:null,
  termReady:false,
  sortBy:'name',   // name | size | time | type
  sortDir:'asc',   // asc | desc
};

/* ── DOM 助手 ── */
const $ = id => document.getElementById(id);
function toast(msg, type=''){
  const t = $('toast');
  t.textContent = msg; t.className = 'toast on ' + type;
  clearTimeout(t._t); t._t = setTimeout(()=>t.className='toast', 1900);
}
function busy(on){ $('busybar').classList.toggle('on', on); }

const TYPE_ICON = { dir:'📁', image:'🖼️', text:'📄', archive:'🗜️', script:'📜',
  exec:'⚙️', video:'🎬', audio:'🎵', link:'🔗', file:'📄' };
function iconClass(t){ return 'ic ' + (TYPE_ICON[t]?'':'file ')+t; }
function iconGlyph(t){ return TYPE_ICON[t] || '📄'; }
