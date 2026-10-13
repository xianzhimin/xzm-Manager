/* ══════════════════════════════════════════════
   xzm 管理器 · 长按菜单与操作
   ══════════════════════════════════════════════ */

let sheetCtx = { side:'A', name:null };

function openSheet(side, name){
  sheetCtx = { side, name };
  const p = state.path[side] + '/' + name;
  const it = state.entries[side].find(x=>x.name===name) || {};
  $('sheetTitle').firstChild.textContent = name;
  $('sheetSub').textContent = p;

  const isDir = it.type==='dir';
  const isArchive = it.type==='archive';
  const isText = it.type==='text' || it.type==='script';

  const groups = [];

  // 基础操作
  groups.push(['基础操作', [
    ['⧉','复制到对栏','blue',()=>opCopy(side,name)],
    ['➦','移动到对栏','blue',()=>opMove(side,name)],
    ['✎','重命名','amber',()=>opRename(side,name)],
    ['🗑','删除','red',()=>opDelete(side,name)],
    ['📋','复制路径','',()=>{ navigator.clipboard?.writeText(p); toast('已复制路径','ok'); }],
    ['🔖','加书签','amber',()=>addBookmark(p)],
    ['👁','属性','green',()=>showProps(p)],
    ['🔐','权限','green',()=>opPerms(p)],
  ]]);

  // 打开/查看
  const openItems = [];
  if(isDir) openItems.push(['📂','进入','green',()=>loadDir(side,p)]);
  if(isText) openItems.push(['📝','文本编辑','green',()=>openEditor(p)]);
  // 运行（可执行 / 脚本）—— MT 管理器式
  if(it.type==='exec' || it.type==='script'){
    openItems.push(['🚀','以 Root 运行','green',()=>runFile(p)]);
    openItems.push(['▶️','运行（带参数）','amber',()=>inputDlg('运行参数','为「'+name+'」输入命令行参数（可留空）','',(v)=>runFile(p,v))]);
    openItems.push(['⌨️','在终端中运行','blue',()=>openInTerminal(p)]);
  }
  if(!isDir) openItems.push(['🎯','打开方式','green',()=>toast('v1.1：调用系统打开方式')]);
  if(!isDir) openItems.push(['#️⃣','文件校验','green',()=>showProps(p)]);
  if(openItems.length) groups.push(['打开 / 查看', openItems]);

  // APK 安装
  if(!isDir && /\.(apk|xapk|apks)$/i.test(name)){
    groups.push(['安装应用', [
      ['📲','安装','green',()=>installApkConfirm(side,name,{})],
      ['🔁','覆盖安装','amber',()=>installApkConfirm(side,name,{replace:true})],
      ['🔑','安装并授权','green',()=>installApkConfirm(side,name,{replace:true,grant:true})],
      ['⬇️','覆盖+允许降级+授权','blue',()=>installApkConfirm(side,name,{replace:true,downgrade:true,grant:true})],
    ]]);
  }

  // 压缩包
  if(isArchive){
    groups.push(['压缩包', [
      ['👁','预览内容','green',()=>archivePreview(side,name)],
      ['📤','解压到对栏','amber',()=>opExtract(side,name,'opposite')],
      ['📂','解压到…','amber',()=>opExtract(side,name,'choose')],
      ['🗂️','解压到当前目录','amber',()=>opExtract(side,name,'here')],
    ]]);
  } else {
    groups.push(['压缩包', [
      ['🗜️','压缩为 ZIP','amber',()=>opCompress(side,[name])],
    ]]);
  }

  // 权限/属主
  groups.push(['权限 / 属主', [
    ['🔐','修改权限','blue',()=>opPerms(p)],
    ['👤','所有者/组','blue',()=>opChown(p)],
  ]]);

  $('sheetActs').innerHTML = groups.map(([gname, items])=>
    `<div class="grp"><div class="grp-name">${gname}</div><div class="acts">` +
    items.map((it,i)=>`<button class="act ${it[2]}" data-g="${esc(gname)}" data-i="${i}">
      <span class="ai">${it[0]}</span>${esc(it[1])}</button>`).join('') +
    `</div></div>`
  ).join('');

  // 绑定
  const flat = {};
  groups.forEach(([g,items])=>items.forEach((it,i)=>flat[g+'_'+i]=it[3]));
  $('sheetActs').querySelectorAll('.act').forEach(btn=>{
    btn.addEventListener('click',()=>{
      const fn = flat[btn.dataset.g+'_'+btn.dataset.i];
      closeSheet(); if(fn) fn();
    });
  });

  $('sheetBk').classList.add('on');
}
function closeSheet(){ $('sheetBk').classList.remove('on'); }
$('sheetBk').addEventListener('click', e=>{ if(e.target===$('sheetBk')) closeSheet(); });

/* ── 复制 / 移动 ── */
function otherSide(side){ return side==='A'?'B':'A'; }

async function opCopy(side, name){
  const dst = state.path[otherSide(side)];
  const src = state.path[side] + '/' + name;
  const r = await ctl('copy', [src, dst, '0']);
  if(r.ok){ toast('已复制到 '+dst, 'ok'); refreshBoth(); }
  else if(r.conflict){
    confirmDlg('目标已存在', `「${name}」在目标栏已存在，是否覆盖？`, ()=>{
      ctl('copy',[src,dst,'1']).then(r2=>{ if(r2.ok){toast('已覆盖复制','ok');refreshBoth();} else toast(r2.error,'err'); }).catch(e=>{ try{toast('复制失败: '+(e&&e.message||e),'err');}catch(_){} });
    });
  } else toast(r.error||'复制失败','err');
}

async function opMove(side, name){
  const dst = state.path[otherSide(side)];
  const src = state.path[side] + '/' + name;
  const r = await ctl('move', [src, dst, '0']);
  if(r.ok){ toast('已移动到 '+dst, 'ok'); refreshBoth(); }
  else if(r.conflict){
    confirmDlg('目标已存在', `「${name}」在目标栏已存在，是否覆盖？`, ()=>{
      ctl('move',[src,dst,'1']).then(r2=>{ if(r2.ok){toast('已覆盖移动','ok');refreshBoth();} else toast(r2.error,'err'); }).catch(e=>{ try{toast('移动失败: '+(e&&e.message||e),'err');}catch(_){} });
    });
  } else toast(r.error||'移动失败','err');
}

/* ── 重命名 ── */
function opRename(side, name){
  inputDlg('重命名', '输入新名称', name, async val=>{
    if(!val || val===name) return;
    const src = state.path[side]+'/'+name;
    const dst = state.path[side]+'/'+val;
    const r = await ctl('rename',[src,dst]);
    if(r.ok){ toast('已重命名','ok'); refreshBoth(); } else toast(r.error,'err');
  });
}

/* ── 解压 ── */
async function opExtract(side, name, mode){
  const src = state.path[side]+'/'+name;
  let dest;
  if(mode==='here') dest = state.path[side];
  else if(mode==='opposite') dest = state.path[otherSide(side)];
  else dest = null;

  if(mode==='choose'){
    const def = state.path[otherSide(side)];
    return inputDlg('解压到…', '输入目标目录路径', def, (v)=>{
      if(!v) return;
      doExtract(src, v, name);
    });
  }
  doExtract(src, dest, name);
}

async function doExtract(src, dest, name){
  busy(true); toast('正在解压…');
  let r;
  try{
    r = await ctl('extract',[src, dest]);
  }catch(e){ busy(false); showRunResult('解压失败', String(e), false); return; }
  busy(false);
  if(r && r.ok){
    toast('解压完成','ok');
    refreshBoth();
    const log = r.output ? ('\n\n'+r.output) : '';
    showRunResult('解压完成 ✓', '已解压到：\n'+(r.dest||dest)+log, true);
  } else {
    showRunResult('解压失败', (r && (r.error||r.output)) || '后端无响应', false);
  }
}

/* ── 压缩包预览 ── */
/* 长按压缩包 → 预览内容：列出包内条目，点文本条目可看内容、可单解 */
async function archivePreview(side, name){
  const src = state.path[side]+'/'+name;
  busy(true); toast('读取压缩包…');
  let r;
  try{ r = await ctl('archive-list',[src]); }
  catch(e){ busy(false); showRunResult('预览失败', String(e), false); return; }
  busy(false);
  if(!r || !r.ok){ showRunResult('预览失败', (r&&r.error)||'后端无响应', false); return; }

  const items = r.items||[];
  const dirs = items.filter(i=>i.d).length;
  const total = items.reduce((a,i)=>a+(i.s||0),0);
  const head = `${items.length} 个条目（${dirs} 目录） · 原始大小 ${fmtSize(total)}`;

  $('dlgMark').textContent='🗜️';
  $('dlgTitle').textContent = name;
  $('dlgMsg').innerHTML =
    `<div class="arc-head">${esc(head)}</div>`+
    `<div class="arc-list">${ items.length?items.map((it,i)=>{
        const nm = it.d ? it.n.replace(/\/$/,'') : it.n;
        const parts = nm.split('/');
        const fn = parts.pop(); const pad = parts.length;
        return `<div class="arc-row" data-i="${i}">
          <span class="arc-ico">${it.d?'📁':fileEmoji(fn)}</span>
          <span class="arc-name" style="padding-left:${pad*10}px">${esc(fn)}${it.d?'/':''}</span>
          <span class="arc-size">${it.d?'':esc(fmtSize(it.s||0))}</span>
          <button class="arc-out" data-i="${i}" title="解出此文件">⤓ 解出</button>
        </div>`;
      }).join('') : '<div class="arc-empty">（空压缩包）</div>'
    }</div>`;
  $('dlgInput').style.display='none';
  $('dlgCheckWrap').style.display='none';
  $('dlgCancel').style.display='none';
  $('dlgOk').textContent='关闭';
  $('dlgOk').className='primary';
  showDlg(()=>{});

  $('dlgMsg').querySelectorAll('.arc-row').forEach(row=>{
    const it = items[+row.dataset.i];
    const outBtn = row.querySelector('.arc-out');
    // 点行 → 预览（目录略过）
    row.addEventListener('click',(e)=>{
      if(e.target.closest('.arc-out')) return;
      if(it.d) return;
      archivePreviewFile(src, it.n, name);
    });
    // 点「解出」 → 解到对栏
    if(outBtn){
      outBtn.addEventListener('click',(e)=>{
        e.stopPropagation();
        archiveExtractOne(side, name, src, it.n);
      });
    }
  });
}

/* 从预览里解出单个条目到对栏 */
async function archiveExtractOne(side, arcName, src, entry){
  const dest = (typeof state!=='undefined' && state.path) ? state.path[otherSide(side)] : null;
  toast('正在解出…');
  let r;
  try{ r = await ctl('archive-extract-one',[src, btoa(unescape(encodeURIComponent(entry))), dest||'']); }
  catch(e){ showRunResult('解出失败', String(e), false); return; }
  if(r && r.ok){
    toast('已解出到对栏','ok');
    if(typeof refreshBoth==='function') refreshBoth();
  } else {
    showRunResult('解出失败', (r&&(r.error||r.output))||'后端无响应', false);
  }
}

/* ══════════════════════════════════════════════
   压缩包内部浏览（点击压缩包直接进入）
   ══════════════════════════════════════════════ */
let arcCtx = { side:'A', name:null, path:'', src:null, items:[] };

async function openArchive(side, name){
  const src = state.path[side]+'/'+name;
  arcCtx = { side, name, path:'', src, items:[] };
  document.querySelectorAll('.tab').forEach(t=>t.classList.toggle('on', t.dataset.page==='arc'));
  document.querySelectorAll('.page').forEach(p=>p.classList.remove('on'));
  const pg = document.getElementById('page-arc'); if(pg) pg.classList.add('on');
  $('arcPageName').textContent = name;
  $('arcPageList').innerHTML = '<div class="arc-empty">读取中…</div>';
  busy(true);
  let r;
  try{ r = await ctl('archive-list',[src]); }
  catch(e){ busy(false); $('arcPageList').innerHTML = '<div class="arc-empty">读取失败：'+esc(String(e))+'</div>'; return; }
  busy(false);
  if(!r || !r.ok){ $('arcPageList').innerHTML = '<div class="arc-empty">'+esc((r&&r.error)||'无法读取压缩包')+'</div>'; return; }
  arcCtx.items = r.items||[];
  arcRender();
}

function arcRender(){
  const {items, path} = arcCtx;
  const prefix = path ? (path.replace(/\/$/,'')+'/') : '';
  const seen = {};
  const rows = [];
  items.forEach(it=>{
    let n = it.n;
    if(it.d) n = n.replace(/\/$/,'');
    if(prefix && !n.startsWith(prefix)) return;
    let rest = n.slice(prefix.length);
    if(rest==='') return;
    const slash = rest.indexOf('/');
    if(slash>=0){
      const dn = rest.slice(0,slash);
      if(seen['d:'+dn]) return;
      seen['d:'+dn]=1;
      rows.push({name:dn, dir:true, full:prefix+dn+'/', size:0});
    } else {
      if(seen['f:'+rest]) return;
      seen['f:'+rest]=1;
      rows.push({name:rest, dir:false, full:prefix+rest, size:it.s||0});
    }
  });
  rows.sort((a,b)=> (b.dir-a.dir) || a.name.localeCompare(b.name,'zh'));

  $('arcPageCrumb').textContent = prefix ? ('/'+prefix) : '（根目录）';
  $('arcBack').style.display = path ? '' : 'none';

  if(!rows.length){
    $('arcPageList').innerHTML = '<div class="arc-empty">（此目录为空）</div>';
    return;
  }
  $('arcPageList').innerHTML = rows.map((r,i)=>
    `<div class="arc-item" data-i="${i}">
      <span class="ai">${r.dir?'📁':fileEmoji(r.name)}</span>
      <span class="an">${esc(r.name)}${r.dir?'/':''}</span>
      ${r.dir?'':`<span class="as">${esc(fmtSize(r.size))}</span>
      <button class="arc-out" data-out="${esc(r.full)}">⤓ 解出</button>`}
    </div>`
  ).join('');

  $('arcPageList').querySelectorAll('.arc-item').forEach(el=>{
    const r = rows[+el.dataset.i];
    el.addEventListener('click',(e)=>{
      if(e.target.closest('.arc-out')) return;
      if(r.dir){ arcCtx.path = r.full.replace(/\/$/,'')+'/'; arcRender(); }
      else { archivePreviewFile(arcCtx.src, r.full, arcCtx.name); }
    });
    const ob = el.querySelector('.arc-out');
    if(ob) ob.addEventListener('click',(e)=>{ e.stopPropagation(); archiveExtractOne(arcCtx.side, arcCtx.name, arcCtx.src, r.full); });
  });
}

function arcUp(){
  let p = arcCtx.path.replace(/\/$/,'');
  const i = p.lastIndexOf('/');
  p = (i >= 0) ? p.slice(0, i) : '';
  arcCtx.path = p ? (p+'/') : '';
  arcRender();
}

function arcExit(){
  switchPage('file');
}

/* ══════════════════════════════════════════════
   应用管理（已安装应用列表 / 卸载）
   ══════════════════════════════════════════════ */
let appsCache = [];

async function loadApps(){
  const list = $('appList'); if(!list) return;
  list.innerHTML = '<div class="arc-empty">读取中…</div>';
  let r;
  try{ r = await ctl('list-apps-full',['72']); }
  catch(e){ list.innerHTML = '<div class="arc-empty">读取失败：'+esc(String(e))+'</div>'; return; }
  if(!r || !r.ok){
    // 退化到仅包名
    try{ r = await ctl('list-apps',[]); }catch(e){}
    if(r && r.ok) r.apps = (r.apps||[]).map(a=>({pkg: (a.pkg||a), label:'', ver:'', icon:''}));
  }
  if(!r || !r.ok){ list.innerHTML = '<div class="arc-empty">'+esc((r&&r.error)||'无法获取应用列表')+'</div>'; return; }
  appsCache = (r.apps||[]).map(a=> typeof a==='string'? {pkg:a,label:'',icon:''} : a);
  appsCache.sort((a,b)=>(a.label||a.pkg).localeCompare(b.label||b.pkg,'zh'));
  $('appCount').textContent = appsCache.length + ' 个';
  renderApps($('appSearch') ? $('appSearch').value.trim().toLowerCase() : '');
}

function renderApps(filter){
  const list = $('appList'); if(!list) return;
  let rows = appsCache;
  if(filter) rows = rows.filter(a=>(a.pkg||'').toLowerCase().includes(filter) || (a.label||'').toLowerCase().includes(filter));
  if(!rows.length){ list.innerHTML = '<div class="arc-empty">（无匹配应用）</div>'; return; }
  list.innerHTML = rows.map(a=>{
    const ico = a.icon ? `<img class="app-ico" src="${a.icon}" alt="">` : '<span class="app-ico ph">📦</span>';
    return `<div class="arc-item app-row" data-pkg="${esc(a.pkg)}">
      ${ico}
      <span class="app-meta">
        <span class="app-name">${esc(a.label||a.pkg)}</span>
        <span class="app-pkg">${esc(a.pkg)}</span>
      </span>
      <button class="arc-out app-op" data-op="info">ℹ️</button>
      <button class="arc-out app-op" data-op="uninstall">🗑</button>
    </div>`;
  }).join('');
  list.querySelectorAll('.arc-item').forEach(el=>{
    const pkg = el.dataset.pkg;
    el.querySelector('[data-op="info"]').addEventListener('click',e=>{ e.stopPropagation(); showAppInfo(pkg); });
    el.querySelector('[data-op="uninstall"]').addEventListener('click',e=>{ e.stopPropagation(); uninstallApp(pkg); });
    el.addEventListener('click',()=>showAppInfo(pkg));
  });
}

async function showAppInfo(pkg){
  busy(true);
  let r;
  try{ r = await ctl('app-info',[pkg]); }
  catch(e){ busy(false); showRunResult('读取失败', String(e), false); return; }
  busy(false);
  if(!r || !r.ok){ showRunResult('读取失败', (r&&r.error)||'无响应', false); return; }
  const size = r.size? fmtSize(r.size) : '未知';
  const body = '包名：'+pkg+'\n版本：'+(r.ver||'未知')+'\n大小：'+size+'\n路径：'+(r.path||'—');
  confirmDlg('应用详情', body, ()=>uninstallApp(pkg), '🗑 卸载');
}

function uninstallApp(pkg){
  confirmDlg('卸载应用', '确定卸载「'+pkg+'」？\n此操作不可撤销。', async()=>{
    busy(true);
    let r;
    try{ r = await ctl('uninstall-apk',[pkg]); }
    catch(e){ busy(false); showRunResult('卸载失败', String(e), false); return; }
    busy(false);
    if(r && r.ok){ toast('已卸载','ok'); showRunResult('卸载成功 ✓', pkg+'\n\n'+(r.output||'Success'), true); loadApps(); }
    else { showRunResult('卸载失败', (r&&(r.error? (r.error+'\n\n'+(r.output||'')) : r.output))||'无响应', false); }
  }, '确认卸载');
}

// 应用页绑定
(function bindAppsPage(){
  const rf=document.getElementById('appRefresh'); if(rf) rf.addEventListener('click', loadApps);
  const sr=document.getElementById('appSearch');
  if(sr) sr.addEventListener('input', ()=>renderApps(sr.value.trim().toLowerCase()));
})();

/* ══════════════════════════════════════════════
   安装 APK
   ══════════════════════════════════════════════ */
// 安装前先读取 APK 信息并确认
async function installApkConfirm(side, name, flags){
  const apk = state.path[side]+'/'+name;
  busy(true);
  let info = null;
  try{ info = await ctl('apk-info',[apk]); }catch(e){}
  busy(false);
  let detail = '';
  if(info && info.ok && info.pkg){
    detail = '包名：'+info.pkg+'\n版本：'+(info.ver||'未知')+(info.code?(' ('+info.code+')'):'')+(info.minSdk?('\n最低 SDK：'+info.minSdk):'');
  } else {
    detail = '（无法读取包信息）';
  }
  const act = flags.replace ? '覆盖安装' : '安装';
  confirmDlg('安装应用', detail+'\n\n是否'+act+'「'+name+'」？', ()=>installApk(side,name,flags), '📲 '+act);
}

async function installApk(side, name, flags){
  const apk = state.path[side]+'/'+name;
  const fl = [];
  if(flags.replace) fl.push('replace');
  if(flags.downgrade) fl.push('downgrade');
  if(flags.grant) fl.push('grant');
  const label = flags.replace ? (flags.grant ? (flags.downgrade?'覆盖+降级+授权':'覆盖安装并授权') : '覆盖安装') : '安装';
  busy(true); toast('正在'+label+'…');
  let r;
  try{
    const b64 = btoa(unescape(encodeURIComponent(fl.join(','))));
    r = await ctl('install-apk',[apk, b64]);
  }catch(e){ busy(false); showRunResult('安装失败', String(e), false); return; }
  busy(false);
  if(r && r.ok){
    toast('安装成功','ok');
    showRunResult('安装成功 ✓', (name+'\n\n'+(r.output||'Success')), true);
  } else {
    showRunResult('安装失败', (r && (r.error? (r.error+'\n\n'+(r.output||'')) : r.output)) || '后端无响应', false);
  }
}

// 绑定压缩包浏览页按钮
(function bindArcPage(){
  const b1=document.getElementById('arcBack'); if(b1) b1.addEventListener('click', arcUp);
  const b2=document.getElementById('arcClose'); if(b2) b2.addEventListener('click', arcExit);
  const b3=document.getElementById('arcExtractAll');
  if(b3) b3.addEventListener('click', ()=>{ if(arcCtx.src) opExtract(arcCtx.side, arcCtx.name, 'opposite'); });
  const b4=document.getElementById('arcExtractHere');
  if(b4) b4.addEventListener('click', ()=>{ if(arcCtx.src) opExtract(arcCtx.side, arcCtx.name, 'here'); });
})();

async function archivePreviewFile(src, entry, arcName){
  let r;
  try{ r = await ctl('archive-read',[src, btoa(unescape(encodeURIComponent(entry)))]); }
  catch(e){ showRunResult('读取失败', String(e), false); return; }
  if(!r || !r.ok){
    showRunResult('无法预览', (r&&(r.error||r.output))||'该文件无法预览', false);
    return;
  }
  let text='';
  try{ text = decodeURIComponent(escape(atob(r.b64))); }catch(e){ text=''; }
  let printable = 0, tot = Math.min(text.length, 500);
  for(let i=0;i<tot;i++){ const c=text.charCodeAt(i); if(c===9||c===10||c===13||(c>=32&&c<127)||c>127) printable++; }
  const looksText = tot>0 && printable/tot > 0.85;

  if(!looksText){
    showRunResult('二进制文件', `「${entry}」\n大小：${fmtSize(r.size||0)}\n\n不是文本文件，无法直接预览。\n可用「解压」后查看。`, false);
    return;
  }
  showRunResult('👁 '+entry, text, true);
}

function fileEmoji(fn){
  const l=(fn||'').toLowerCase();
  if(/\.(png|jpg|jpeg|gif|webp|bmp|svg|heic)$/.test(l)) return '🖼️';
  if(/\.(mp4|mkv|avi|mov|webm|3gp)$/.test(l)) return '🎬';
  if(/\.(mp3|flac|wav|ogg|m4a|aac)$/.test(l)) return '🎵';
  if(/\.(sh|py|js|lua|rb|pl)$/.test(l)) return '📜';
  if(/\.(zip|rar|7z|tar|gz|tgz|bz2|xz|apk|jar)$/.test(l)) return '🗜️';
  if(/\.(txt|md|json|xml|conf|ini|log|prop|yml|yaml|html|css)$/.test(l)) return '📄';
  return '📄';
}
function fmtSize(b){
  b=+b||0;
  if(b<1024) return b+' B';
  if(b<1048576) return (b/1024).toFixed(2)+' KB';
  if(b<1073741824) return (b/1048576).toFixed(2)+' MB';
  return (b/1073741824).toFixed(2)+' GB';
}

/* ── 压缩 ── */
async function opCompress(side, names){
  const dir = state.path[side];
  const list = (names||[]).map(n=>dir+'/'+n);
  if(!list.length) return;
  const base = names.length===1 ? names[0].replace(/\.[^.]+$/,'') : (dir.split('/').filter(Boolean).pop()||'archive');
  const defZip = dir+'/'+base+'.zip';
  inputDlg('压缩为 ZIP', '输出压缩包路径', defZip, async (out)=>{
    if(!out) return;
    busy(true); toast('正在压缩…');
    let r;
    try{
      const b64 = btoa(unescape(encodeURIComponent(list.join('\n'))));
      r = await ctl('compress',[out, b64]);
    }catch(e){ busy(false); showRunResult('压缩失败', String(e), false); return; }
    busy(false);
    if(r && r.ok){
      toast('压缩完成','ok'); refreshBoth();
      showRunResult('压缩完成 ✓', '已生成：\n'+(r.out||out)+(r.output?('\n\n'+r.output):''), true);
    } else {
      showRunResult('压缩失败', (r && (r.error||r.output)) || '后端无响应', false);
    }
  });
}

/* ── 删除 ── */
function opDelete(side, name){
  const p = state.path[side]+'/'+name;
  confirmDlg('删除确认', `确定删除「${name}」？此操作不可撤销。`, async ()=>{
    const r = await ctl('delete',[p,'1']);
    if(r.ok){ toast('已删除','ok'); refreshBoth(); } else toast(r.error,'err');
  }, '删除');
}

/* ── 权限 ── */
function opPerms(path){
  inputDlg('修改权限', '输入八进制权限（如 755 / 644）', '755', async val=>{
    if(!/^[0-7]{3,4}$/.test(val)){ toast('权限格式不正确','err'); return; }
    const r = await ctl('chmod',[path,val,'0']);
    if(r.ok){ toast('权限已修改为 '+val,'ok'); } else toast(r.error,'err');
  });
}

/* ── 属主 ── */
function opChown(path){
  inputDlg('修改属主', '输入 用户:组（如 0:0）', '0:0', async val=>{
    const r = await ctl('chown',[path,val,'0']);
    if(r.ok){ toast('属主已修改','ok'); } else toast(r.error,'err');
  });
}

/* ── 属性 ── */
async function showProps(path){
  busy(true);
  const r = await ctl('stat',[path]);
  busy(false);
  if(!r.ok){ toast(r.error,'err'); return; }
  const rows = [
    ['路径', r.path], ['权限', r.perms], ['大小', r.sizeText],
    ['修改时间', r.mtime], ['属主', r.owner], ['MD5', r.md5||'—'],
  ];
  $('dlgMark').textContent = 'ℹ️';
  $('dlgTitle').textContent = '属性';
  $('dlgMsg').innerHTML = rows.map(([k,v])=>
    `<div style="display:grid;grid-template-columns:76px 1fr;gap:8px;padding:6px 0;border-bottom:1px solid var(--line)">
      <span style="color:var(--muted)">${k}</span>
      <span style="font-family:var(--mono);word-break:break-all">${esc(v)}</span></div>`).join('');
  $('dlgInput').style.display='none';
  $('dlgCheckWrap').style.display='none';
  $('dlgCancel').style.display='none';
  $('dlgOk').textContent = '关闭';
  showDlg(()=>{});
}

/* ══ 通用对话框 ══ */
let dlgCb = null;
function showDlg(cb){ dlgCb = cb; $('dlgBk').classList.add('on'); }
function closeDlg(){ $('dlgBk').classList.remove('on'); dlgCb=null; }

function confirmDlg(title, msg, cb, okTxt='确定'){
  $('dlgMark').textContent = '⚠️';
  $('dlgTitle').textContent = title;
  $('dlgMsg').textContent = msg;
  $('dlgInput').style.display='none';
  $('dlgCheckWrap').style.display='none';
  $('dlgCancel').style.display=''; $('dlgCancel').textContent='取消';
  $('dlgOk').textContent = okTxt;
  $('dlgOk').className = okTxt==='删除' ? 'danger' : 'primary';
  showDlg(cb);
}

function inputDlg(title, msg, defVal, cb){
  $('dlgMark').textContent = '✎';
  $('dlgTitle').textContent = title;
  $('dlgMsg').textContent = msg;
  const inp = $('dlgInput');
  inp.style.display='block'; inp.value = defVal||'';
  $('dlgCheckWrap').style.display='none';
  $('dlgCancel').style.display=''; $('dlgCancel').textContent='取消';
  $('dlgOk').textContent='确定'; $('dlgOk').className='primary';
  showDlg(()=>cb(inp.value.trim()));
  setTimeout(()=>inp.focus(),50);
}

$('dlgOk').addEventListener('click',()=>{ const cb=dlgCb; closeDlg(); if(cb) cb(); });
$('dlgCancel').addEventListener('click', closeDlg);
$('dlgBk').addEventListener('click', e=>{ if(e.target===$('dlgBk')) closeDlg(); });

/* ── 刷新 ── */
function refreshBoth(){
  loadDir('A', state.path.A, {noHistory:true});
  loadDir('B', state.path.B, {noHistory:true});
}

/* ── 排序按钮绑定 ── */
['A','B'].forEach(sd=>{
  const b=$('sortBtn'+sd);
  if(b) b.addEventListener('click', e=>{ e.stopPropagation(); openSortMenu(sd, b); });
});

/* ── 工具栏绑定 ── */
$('btnRefresh').addEventListener('click', ()=>loadDir(state.active, state.path[state.active], {noHistory:true}));
$('btnUp').addEventListener('click', ()=>{
  const p = state.path[state.active];
  if(p==='/') return;
  const parent = p.replace(/\/[^/]+\/?$/, '') || '/';
  loadDir(state.active, parent);
});
$('btnBack').addEventListener('click', ()=>{
  const h = state.history[state.active];
  if(h.length>1){ h.pop(); loadDir(state.active, h[h.length-1], {noHistory:true}); }
});
$('btnSync').addEventListener('click', ()=>{
  const o = otherSide(state.active);
  // 把当前栏路径同步到对栏；手机单栏模式下自动切过去，让用户看到结果
  loadDir(o, state.path[state.active]).then(()=>{
    if(window.matchMedia && window.matchMedia('(max-width:900px)').matches){
      setActive(o);
      toast('已同步并切到' + (o==='A'?'左栏':'右栏'), 'ok');
    } else {
      toast('已同步到' + (o==='A'?'左栏':'右栏'), 'ok');
    }
  }).catch(e=>{ try{ toast('同步失败: '+(e&&e.message||e),'err'); }catch(_){} });
});
$('btnEditPath').addEventListener('click', ()=>{
  const inp = $('pathInput');
  inp.style.display='block'; inp.value = state.path[state.active];
  $('crumb').style.display='none';
  inp.focus();
});
$('pathInput').addEventListener('keydown', e=>{
  if(e.key==='Enter'){
    loadDir(state.active, $('pathInput').value.trim() || '/');
    $('pathInput').style.display='none'; $('crumb').style.display='flex';
  } else if(e.key==='Escape'){
    $('pathInput').style.display='none'; $('crumb').style.display='flex';
  }
});
$('btnNew').addEventListener('click', ()=>{
  $('dlgMark').textContent='＋'; $('dlgTitle').textContent='新建';
  $('dlgMsg').textContent='输入名称。以 / 结尾创建文件夹。';
  const inp=$('dlgInput'); inp.style.display='block'; inp.value='';
  $('dlgCheckWrap').style.display='flex'; $('dlgCheck').checked=false;
  $('dlgCheckTxt').textContent='这是文件夹';
  $('dlgCancel').style.display=''; $('dlgOk').textContent='创建'; $('dlgOk').className='primary';
  showDlg(async ()=>{
    const name = inp.value.trim(); if(!name) return;
    const p = state.path[state.active] + '/' + name;
    const isDir = $('dlgCheck').checked;
    const r = await ctl(isDir?'mkdir':'touch',[p]);
    if(r.ok){ toast('已创建','ok'); loadDir(state.active, state.path[state.active], {noHistory:true}); }
    else toast(r.error,'err');
  });
  setTimeout(()=>inp.focus(),50);
});
$('btnSearch').addEventListener('click', ()=>{
  inputDlg('搜索', '在当前目录搜索文件名关键字', '', async kw=>{
    if(!kw) return;
    busy(true);
    const r = await ctl('exec', [btoa(`find '${state.path[state.active]}' -iname '*${kw.replace(/'/g,"'\\''")}*' 2>/dev/null | head -100`)]);
    busy(false);
    if(r.ok){ showResult('搜索结果', r.output||'（无结果）'); } else toast(r.error,'err');
  });
});
$('btnCopyAct').addEventListener('click', ()=>{
  const n = state.selected[state.active]; if(!n) return toast('请先选择文件');
  opCopy(state.active, n);
});
$('btnMoveAct').addEventListener('click', ()=>{
  const n = state.selected[state.active]; if(!n) return toast('请先选择文件');
  opMove(state.active, n);
});
$('btnDelAct').addEventListener('click', ()=>{
  const n = state.selected[state.active]; if(!n) return toast('请先选择文件');
  opDelete(state.active, n);
});

function showResult(title, text){
  $('dlgMark').textContent='🔍'; $('dlgTitle').textContent=title;
  $('dlgMsg').innerHTML = `<pre style="font:12px/1.6 var(--mono);white-space:pre-wrap;word-break:break-all;margin:0">${esc(text)}</pre>`;
  $('dlgInput').style.display='none'; $('dlgCheckWrap').style.display='none';
  $('dlgCancel').style.display='none'; $('dlgOk').textContent='关闭';
  showDlg(()=>{});
}

/* ══════════════════════════════════════════════
   点击运行脚本 / 可执行文件（MT 管理器式）
   ══════════════════════════════════════════════ */

/* 结果弹窗（可滚动，带「复制」按钮） */
function showRunResult(title, text, ok){
  $('dlgMark').textContent = ok ? '✅' : '❌';
  $('dlgTitle').textContent = title;
  $('dlgMsg').innerHTML =
    `<pre id="runOut" style="font:12px/1.55 var(--mono);white-space:pre-wrap;word-break:break-all;`+
    `margin:0;max-height:46vh;overflow:auto;background:#0b0e14;color:#c9d1d9;padding:10px;border-radius:8px">${esc(text||'(无输出)')}</pre>`;
  $('dlgInput').style.display='none'; $('dlgCheckWrap').style.display='none';
  $('dlgCancel').style.display='none'; $('dlgOk').textContent='关闭';
  showDlg(()=>{});
}

/* 执行一个文件并展示输出
   filePath: 绝对路径  args: 附加参数(可选) */
async function runFile(filePath, args=''){
  // 交互式脚本（含 read 等）在无 stdin 环境会瞬间 EOF 退出 → 自动改走终端
  if(!args && await looksInteractive(filePath)){
    toast('该脚本需要交互输入，已切到终端运行');
    return openInTerminal(filePath);
  }
  const wd = filePath.replace(/\/[^/]*$/, '') || '/';
  busy(true);
  toast('正在运行…');
  let r;
  try{
    const b64args = args ? btoa(unescape(encodeURIComponent(args))) : '';
    r = await ctl('run', [filePath, wd, b64args]);
  }catch(e){
    busy(false); showRunResult('运行失败', String(e), false); return;
  }
  busy(false);
  if(r && r.ok){
    const out = (r.output||'');
    const code = (r.code!=null ? r.code : '?');
    showRunResult('运行完成 (exit ' + code + ')', out + (out && !out.endsWith('\n')?'\n':'') , code=='0');
  } else {
    showRunResult('运行失败', (r && (r.error || r.output)) || '后端无响应', false);
  }
}

/* 判断脚本是否需要交互（含 read 从 stdin 读取、或明显的菜单提示） */
async function looksInteractive(filePath){
  if(!/\.(sh|bash|zsh)$/i.test(filePath)) return false;
  try{
    const b64p = btoa(unescape(encodeURIComponent(filePath)));
    const r = await ctl('exec',[btoa(
      `p=$(echo '${b64p}' | base64 -d); ` +
      `head -c 20000 "$p" 2>/dev/null | ` +
      `grep -qE '(^|[^[:alnum:]_])(read|select)[[:space:]]' && echo INTERACTIVE || echo PLAIN`
    )]);
    return ((r.output||'') + (r.error||'')).includes('INTERACTIVE');
  }catch(e){ return false; }
}

/* 弹出运行方式选择：终端中运行 / 直接运行(root) */
function runDlg(filePath){
  const name = filePath.replace(/^.*\//,'');
  const groups = [
    ['运行方式', [
      ['🚀','直接运行 (Root)','green', ()=>runFile(filePath)],
      ['⌨️','在终端中运行','blue', ()=>{ closeSheet(); openInTerminal(filePath); }],
      ['▶️','运行（带参数）','amber', ()=>{ closeSheet(); inputDlg('运行参数','为「'+name+'」输入命令行参数（可留空）','',(v)=>runFile(filePath, v)); }],
    ]],
    ['其他', [
      ['📝','编辑','blue', ()=>openEditor(filePath)],
      ['👁','属性','green', ()=>showProps(filePath)],
    ]],
  ];
  $('sheetTitle').firstChild.textContent = name;
  $('sheetSub').textContent = filePath;
  $('sheetActs').innerHTML = groups.map(([gname, items])=>
    `<div class="grp"><div class="grp-name">${gname}</div><div class="acts">` +
    items.map((it,i)=>`<button class="act ${it[2]}" data-g="${esc(gname)}" data-i="${i}">
      <span class="ai">${it[0]}</span>${esc(it[1])}</button>`).join('') +
    `</div></div>`
  ).join('');
  const flat = {};
  groups.forEach(([g,items])=>items.forEach((it,i)=>flat[g+'_'+i]=it[3]));
  $('sheetActs').querySelectorAll('.act').forEach(btn=>{
    btn.addEventListener('click',()=>{ const fn=flat[btn.dataset.g+'_'+btn.dataset.i]; closeSheet(); if(fn){ try{ Promise.resolve(fn()).catch(e=>{ try{ console.error('sheet action',e); toast('操作失败: '+(e&&e.message||e),'err'); }catch(_){} }); }catch(e){ try{ toast('操作失败: '+(e&&e.message||e),'err'); }catch(_){} } } });
  });
  $('sheetBk').classList.add('on');
}

/* 在终端页里运行文件（JieMoSi 式：把目标作为 ttyd shell 参数，重启终端直接跑） */
async function openInTerminal(filePath){
  try{
    switchPage('term');
    toast('正在启动终端并运行…');
    await startTerminal(filePath);
  }catch(e){
    try{ console.error('openInTerminal', e); toast('终端启动失败: ' + (e && e.message || e), 'err'); }catch(_){}
  }
}
