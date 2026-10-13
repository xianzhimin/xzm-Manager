/* ══════════════════════════════════════════════
   xzm 管理器 · 文件浏览与操作
   ══════════════════════════════════════════════ */

/* ── 列目录 ── */
async function loadDir(side, path, opts={}){
  const list = $('list'+side);
  list.classList.add('loading');
  const r = await ctl('list', [path]);
  list.classList.remove('loading');
  if(!r.ok){ toast(r.error||'读取失败','err'); return; }
  state.path[side] = r.path;
  if(!opts.noHistory){
    const h = state.history[side];
    if(h[h.length-1] !== r.path) h.push(r.path);
  }
  state.entries[side] = sortEntries(r.entries || [], state.sortBy, state.sortDir);
  state.selected[side] = null;
  renderPane(side);
}

/* ── 排序：文件夹优先，其次按所选键（名称用自然排序，file2 < file10）── */
function naturalCmp(a, b){
  const re=/(\d+)|(\D+)/g;
  const ax=String(a).toLowerCase().match(re)||[];
  const bx=String(b).toLowerCase().match(re)||[];
  const n=Math.max(ax.length,bx.length);
  for(let i=0;i<n;i++){
    const x=ax[i]||'', y=bx[i]||'';
    if(x===y) continue;
    const xn=/^\d+$/.test(x), yn=/^\d+$/.test(y);
    if(xn&&yn){ const d=parseInt(x,10)-parseInt(y,10); if(d) return d; }
    else return x<y?-1:1;
  }
  return 0;
}
const DIRTY={dir:0,link:0,archive:1,exec:2,script:3,image:4,video:5,audio:6,text:7,file:8};
function sortEntries(list, by, dir){
  const sign = dir==='desc' ? -1 : 1;
  return list.slice().sort((a,b)=>{
    // 文件夹永远在前（不受方向影响）
    const ad=a.type==='dir'?0:1, bd=b.type==='dir'?0:1;
    if(ad!==bd) return ad-bd;
    let c;
    if(by==='size') c=(a.size||0)-(b.size||0);
    else if(by==='time') c=String(a.mtime||'').localeCompare(String(b.mtime||''));
    else if(by==='type') c=(DIRTY[a.type]??9)-(DIRTY[b.type]??9) || naturalCmp(a.name,b.name);
    else c=naturalCmp(a.name,b.name);
    if(!c) c=naturalCmp(a.name,b.name);
    return c*sign;
  });
}

/* ── 渲染一栏 ── */
function renderPane(side){
  const list = $('list'+side);
  const entries = state.entries[side];
  $('path'+side).textContent = state.path[side];
  $('count'+side).textContent = entries.length + ' 项';

  if(!entries.length){
    list.innerHTML = '<div class="empty">（空目录）</div>';
    return;
  }
  list.innerHTML = entries.map(it=>{
    const multi = state.multiMode && state.multi.has(state.path[side]+'/'+it.name);
    const sel = state.selected[side]===it.name ? ' sel' : '';
    return `<div class="row${sel}${multi?' multi':''}" data-name="${esc(it.name)}" data-type="${it.type}">
      <div class="${iconClass(it.type)}">${iconGlyph(it.type)}</div>
      <div class="row-body">
        <div class="name">${esc(it.name)}</div>
        <div class="meta">${it.type==='dir'?'':(esc(it.sizeText)+' · ')}${esc(it.mtime)}</div>
      </div>
      <button class="more ghost icon-btn" data-more="${esc(it.name)}">⋯</button>
    </div>`;
  }).join('');
  updateCrumb();
}

function esc(s){ return String(s==null?'':s).replace(/[&<>"']/g, c=>
  ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

/* ── 面包屑 ── */
function updateCrumb(){
  const p = state.path[state.active];
  const parts = p.split('/').filter(Boolean);
  let acc = '';
  let html = `<b data-go="/">/</b>`;
  parts.forEach(part=>{
    acc += '/' + part;
    html += `<span class="slash">›</span><b data-go="${esc(acc)}">${esc(part)}</b>`;
  });
  const c = $('crumb'); c.innerHTML = html;
  c.querySelectorAll('b').forEach(b=>b.addEventListener('click',()=>loadDir(state.active, b.dataset.go)));
}

/* ── 点击 / 长按绑定 ── */
function bindPane(side){
  const list = $('list'+side);
  const pane = $('pane'+side);

  list.addEventListener('click', e=>{
    setActive(side);
    const row = e.target.closest('.row');
    if(!row) return;
    const name = row.dataset.name;
    // 点右侧 ⋯ → 打开菜单
    if(e.target.closest('.more')){ openSheet(side, name); return; }
    // 多选模式 → 勾选
    if(state.multiMode){ toggleMulti(side, name); return; }
    // 先选中
    list.querySelectorAll('.row').forEach(r=>r.classList.remove('sel'));
    row.classList.add('sel');
    state.selected[side] = name;
    // 单击直接进入目录 / 打开文件（MT 式）
    openEntry(side, name, row.dataset.type);
  });

  // 长按（触屏）→ 菜单；避免长按后再触发 click 打开
  let timer=null, moved=false, longPressed=false;
  list.addEventListener('touchstart', e=>{
    const row = e.target.closest('.row'); if(!row) return;
    moved=false; longPressed=false;
    timer = setTimeout(()=>{ if(!moved){ longPressed=true; openSheet(side, row.dataset.name); } }, 480);
  }, {passive:true});
  list.addEventListener('touchmove', ()=>{ moved=true; clearTimeout(timer); }, {passive:true});
  ['touchend','touchcancel'].forEach(ev=>list.addEventListener(ev,()=>clearTimeout(timer),{passive:true}));
  // 捕获阶段拦截：长按已弹菜单时吞掉这次 click
  list.addEventListener('click', e=>{
    if(longPressed){ longPressed=false; e.stopPropagation(); e.preventDefault(); }
  }, true);

  pane.querySelector('.pane-tag').addEventListener('click',()=>setActive(side));
  bindSwitch(side);
}

function setActive(side){
  state.active = side;
  document.querySelectorAll('.pane').forEach(p=>p.classList.toggle('active', p.dataset.side===side));
}

/* ── 手机：切到另一栏 ── */
function bindSwitch(side){
  const btn = $('switch'+side);
  if(!btn) return;
  btn.addEventListener('click', e=>{
    e.stopPropagation();
    const other = otherSide(side);
    setActive(other);
    // 切栏后刷新，保证内容最新
    loadDir(other, state.path[other], {noHistory:true});
  });
}

/* ── 打开条目 ── */
async function openEntry(side, name, type){
  const p = state.path[side] + '/' + name;
  if(type === 'dir'){ loadDir(side, p); return; }
  if(type === 'exec'){
    // 可执行文件：直接弹出运行方式（MT 式）
    runDlg(p); return;
  }
  if(type === 'script'){
    // 脚本：默认进编辑器，但长按/⋯可运行；这里也给运行选择
    runDlg(p); return;
  }
  if(type === 'archive'){
    // APK：点击优先询问安装；其余压缩包进入浏览
    if(/\.(apk|xapk|apks)$/i.test(name)){
      installApkConfirm(side, name, {replace:true});
      return;
    }
    openArchive(side, name); return;
  }
  // 其他：查看属性
  showProps(p);
}

/* ── 多选 ── */
function toggleMulti(side, name){
  const key = state.path[side] + '/' + name;
  if(state.multi.has(key)) state.multi.delete(key); else state.multi.add(key);
  renderPane(side);
}

/* ── 面板切换 ── */
function switchPage(page){
  const tabs = document.querySelectorAll('.tab');
  tabs.forEach(t=>t.classList.toggle('on', t.dataset.page===page));
  document.querySelectorAll('.page').forEach(p=>p.classList.remove('on'));
  const map = {file:'-file',term:'-term',book:'-book',set:'-set',arc:'-arc',apps:'-apps'};
  const el = $('page'+map[page]);
  if(el) el.classList.add('on');
  if(page==='book') renderBookmarks();
  if(page==='set') refreshSetInfo();
  if(page==='apps') loadApps();
}
document.querySelectorAll('.tab').forEach(tab=>{
  tab.addEventListener('click',()=>switchPage(tab.dataset.page));
});

/* ── 支持 URL hash 直达页面，如 #term (#终端) ── */
/* ── 也支持开机/通知栏传入的标记文件 /data/local/tmp/.xzm_open_page ── */
(function initHashPage(){
  const alias = {term:'term','终端':'term',terminal:'term',
                 file:'file','文件':'file',
                 book:'book','书签':'book',
                 set:'set','设置':'set'};
  function normalize(s){
    s = (s||'').replace(/^#/,'').trim().toLowerCase();
    return alias[decodeURIComponent(s)] || null;
  }
  function go(page){
    try{ switchPage(page); }catch(e){}
    // 终端页：#term 直达时自动拉起终端（ttyd）
    if(page==='term' && typeof startTerminal==='function'){
      setTimeout(()=>{ Promise.resolve().then(()=>startTerminal()).catch(e=>{ try{ console.error('startTerminal',e); toast('终端启动失败: '+(e&&e.message||e),'err'); }catch(_){} }); }, 400);
    }
  }
  function applyHash(){
    const page = normalize(location.hash);
    if(page){
      if(document.readyState==='complete') setTimeout(()=>go(page),0);
      else window.addEventListener('load',()=>go(page));
    }
  }
  // 读取标记文件（通知栏「终端」按钮写入 App 私有目录），有则跳转并清除
  async function applyMarker(){
    try{
      if(typeof sh!=='function') return false;
      const paths = [
        '/data/data/com.xzm.launcher/files/xzm_open_page',
        '/data/user/0/com.xzm.launcher/files/xzm_open_page',
        '/data/local/tmp/.xzm_open_page'
      ];
      for(const p of paths){
        const r = await sh('cat ' + p + ' 2>/dev/null');
        const page = normalize((r && r.out || '').trim());
        if(page){
          sh('rm -f ' + p + ' >/dev/null 2>&1');
          const doGo=()=>{
            go(page);
            if(page==='term' && typeof startTerminal==='function'){
              setTimeout(()=>{ Promise.resolve().then(()=>startTerminal()).catch(e=>{ try{ console.error('startTerminal',e); }catch(_){} }); }, 300);
            }
          };
          if(document.readyState==='complete') setTimeout(doGo,50); else window.addEventListener('load',doGo);
          return true;
        }
      }
    }catch(e){}
    return false;
  }
  applyHash();
  window.addEventListener('hashchange', applyHash);

  // 标记文件轮询：覆盖「WebUI 已在前台/存活时再次点击通知」的场景
  // （SukiSU 复用 WebUIActivity，onNewIntent 不 reload，只能靠 JS 主动轮询）
  setInterval(()=>{ if(document.visibilityState==='visible') applyMarker(); }, 1500);
  // 从后台切回前台时立即检查一次
  document.addEventListener('visibilitychange', ()=>{
    if(document.visibilityState==='visible') applyMarker();
  });
  // ksu 桥接就绪后首次读取
  setTimeout(applyMarker, 400);
})();

/* ── 排序菜单 ── */
const SORT_LABEL = { name:'名称', size:'大小', time:'修改时间', type:'类型' };
let _sortMenuEl = null;
function closeSortMenu(){ if(_sortMenuEl){ _sortMenuEl.remove(); _sortMenuEl=null; } }
function openSortMenu(side, btn){
  closeSortMenu();
  const cur = { by: state.sortBy, dir: state.sortDir };
  const el = document.createElement('div');
  el.className = 'sort-menu';
  const mkItem = (by)=>{
    const on = cur.by===by;
    const d = document.createElement('div');
    d.className = 'si'+(on?' on':'');
    d.innerHTML = `<span>${SORT_LABEL[by]}</span>` + (on?`<span class="arw">${cur.dir==='asc'?'↑ 升序':'↓ 降序'}</span>`:'');
    d.onclick = ()=>{
      if(state.sortBy===by){ state.sortDir = state.sortDir==='asc'?'desc':'asc'; }
      else { state.sortBy = by; state.sortDir = 'asc'; }
      applySort(side); closeSortMenu();
    };
    return d;
  };
  ['name','size','time','type'].forEach(by=> el.appendChild(mkItem(by)));
  const sep = document.createElement('div'); sep.className='sep2'; el.appendChild(sep);
  const flip = document.createElement('div');
  flip.className='si';
  flip.innerHTML = `<span>${cur.dir==='asc'?'改为降序 ↓':'改为升序 ↑'}</span>`;
  flip.onclick = ()=>{ state.sortDir = state.sortDir==='asc'?'desc':'asc'; applySort(side); closeSortMenu(); };
  el.appendChild(flip);

  document.body.appendChild(el);
  const r = btn.getBoundingClientRect();
  const w = el.offsetWidth, h = el.offsetHeight;
  let left = Math.min(r.right - w, window.innerWidth - w - 8);
  let top = r.bottom + 6;
  if(top + h > window.innerHeight - 8) top = r.top - h - 6;
  el.style.left = Math.max(8,left)+'px';
  el.style.top = Math.max(8,top)+'px';
  _sortMenuEl = el;
  setTimeout(()=>document.addEventListener('click', onDocCloseSort, {once:true}),0);
}
function onDocCloseSort(e){ if(_sortMenuEl && !_sortMenuEl.contains(e.target)) closeSortMenu(); }

/* 重新排序某一栏（或两栏），不重新请求 */
function applySort(side){
  const sides = side ? [side] : ['A','B'];
  sides.forEach(sd=>{
    if(!state.entries[sd]) return;
    // 保留原始顺序用于排序基准？直接对当前 entries 排序即可（已含全部）
    state.entries[sd] = sortEntries(state.entries[sd], state.sortBy, state.sortDir);
    renderPane(sd);
  });
  const b = $('sortBtn'+ (side||'A'));
  if(b) b.classList.add('on');
}
