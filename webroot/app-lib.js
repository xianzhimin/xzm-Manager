/* ══════════════════════════════════════════════
   xzm 管理器 · 文本编辑器 / 书签 / 设置 / 终端
   ══════════════════════════════════════════════ */

/* ── 文本编辑器 ── */
async function openEditor(path){
  busy(true);
  const r = await ctl('read', [path]);
  busy(false);
  if(!r.ok){ toast(r.error,'err'); return; }
  let text = '';
  try{ text = decodeURIComponent(escape(atob(r.base64))); }
  catch(e){ text = atob(r.base64||''); }
  state.editorPath = path;
  $('edName').firstChild.textContent = path.split('/').pop() || path;
  $('edPath').textContent = path;
  $('edArea').value = text;
  updateGutter();
  $('edMeta').textContent = `${text.split('\n').length} 行 · ${r.size} 字节`;
  $('editor').classList.add('on');
  $('edArea').focus();
}
function closeEditor(){ $('editor').classList.remove('on'); state.editorPath=null; }
function updateGutter(){
  const lines = $('edArea').value.split('\n').length;
  $('edGutter').textContent = Array.from({length:lines},(_,i)=>i+1).join('\n');
}
$('edArea').addEventListener('input', updateGutter);
$('edArea').addEventListener('scroll', ()=>{
  $('edGutter').style.transform = `translateY(-${$('edArea').scrollTop}px)`;
});
$('edClose').addEventListener('click', closeEditor);
$('edSave').addEventListener('click', async ()=>{
  if(!state.editorPath) return;
  busy(true);
  let b64='';
  try{ b64 = btoa(unescape(encodeURIComponent($('edArea').value))); }
  catch(e){ b64 = btoa($('edArea').value); }
  const r = await ctl('write', [state.editorPath, b64]);
  busy(false);
  if(r.ok){ toast('已保存','ok'); }
  else toast(r.error,'err');
});
$('edSearchBtn').addEventListener('click', ()=>{
  inputDlg('查找', '输入要查找的文本', '', kw=>{
    if(!kw) return;
    const ta = $('edArea');
    const idx = ta.value.indexOf(kw);
    if(idx<0) return toast('未找到','err');
    ta.focus(); ta.setSelectionRange(idx, idx+kw.length);
    toast('已定位','ok');
  });
});

/* ── 书签 ── */
function bookmarkKey(){ return 'bookmarks'; }
async function loadBookmarks(){
  const r = await ctl('pref-get', [bookmarkKey()]);
  if(r.ok && r.value){
    try{ state.bookmarks = JSON.parse(r.value); }catch(e){ state.bookmarks=[]; }
  } else state.bookmarks = [];
}
async function saveBookmarks(){
  await ctl('pref-set', [bookmarkKey(), JSON.stringify(state.bookmarks)]);
  renderBookmarks();
}
function addBookmark(path){
  if(state.bookmarks.includes(path)) return toast('已存在书签');
  state.bookmarks.push(path);
  saveBookmarks().then(()=>toast('已添加书签','ok')).catch(e=>{ try{ toast('书签保存失败: '+(e&&e.message||e),'err'); }catch(_){} });
}
function renderBookmarks(){
  const el = $('bookList');
  if(!state.bookmarks.length){ el.innerHTML='<div class="hintbox">暂无书签</div>'; return; }
  el.innerHTML = state.bookmarks.map((p,i)=>
    `<div class="list-row-mini">
      <div style="min-width:0"><div class="mini-t">${esc(p.split('/').pop()||p)}</div><div class="mini-p">${esc(p)}</div></div>
      <div style="display:flex;gap:6px">
        <button class="ghost" data-open="${i}">打开</button>
        <button class="danger" data-del="${i}">删</button>
      </div>
    </div>`).join('');
  el.querySelectorAll('[data-open]').forEach(b=>b.addEventListener('click',()=>{
    loadDir(state.active, state.bookmarks[+b.dataset.open]);
  }));
  el.querySelectorAll('[data-del]').forEach(b=>b.addEventListener('click',()=>{
    state.bookmarks.splice(+b.dataset.del,1); saveBookmarks();
  }));
}
$('btnAddBook').addEventListener('click', ()=>addBookmark(state.path.A));
$('btnAddBookR').addEventListener('click', ()=>addBookmark(state.path.B));

/* ── 设置 ── */
async function refreshSetInfo(){
  const el = $('setInfo');
  const rootTest = await sh('id');
  el.innerHTML = `<b>环境</b><br>
    引擎：${envName}<br>
    Root：${rootTest.out.trim()||'未知'}<br>
    模块目录：${moduleDir}<br>
    数据目录：${MODDATA}`;
}
$('btnTestRoot').addEventListener('click', async ()=>{
  const r = await sh('id; echo ---; getprop ro.build.version.release');
  showResult('Root 检测', r.out || r.err || '无输出');
});
$('btnDiag').addEventListener('click', async ()=>{
  busy(true);
  const info = [];
  info.push('bridge = ' + bridgeKind);
  info.push('moduleDir = ' + moduleDir);
  info.push('MODDATA = ' + MODDATA);
  var ksuLen = (window.ksu && window.ksu.exec) ? window.ksu.exec.length : '?';
  info.push('window.ksu = ' + (window.ksu ? ('存在, exec.length=' + ksuLen) : '不存在'));
  if(window.ksu){
    info.push('ksu 上方法: ' + Object.getOwnPropertyNames(window.ksu).slice(0,20).join(','));
  }
  // 探测模块脚本
  const p1 = await sh(`[ -f ${moduleDir}/bin/xzmctl.sh ] && echo EXISTS || echo MISSING`);
  info.push('xzmctl.sh: [' + p1.out.trim() + '] err=' + p1.err.trim() + ' code=' + p1.code);
  // /sdcard 链接情况
  const lk = await sh(`ls -ld /sdcard; readlink -f /sdcard; echo "---"; ls -A /sdcard 2>&1 | head -5`);
  info.push('--- /sdcard 检查 ---\n' + (lk.out || '(空)').trim());
  // 直接跑 list
  const raw = await sh(`XZM_DATA_DIR=${MODDATA} sh ${moduleDir}/bin/xzmctl.sh list /sdcard 2>&1`);
  info.push('--- 原始响应 (code=' + raw.code + ') ---');
  info.push((raw.out || '(空)').slice(0, 600));
  if(raw.err) info.push('--- stderr ---\n' + raw.err.slice(0,300));
  const json = await ctl('list', ['/sdcard']);
  info.push('--- ctl() 解析结果 ---');
  info.push(JSON.stringify(json, null, 2).slice(0, 500));
  busy(false);
  showResult('环境诊断', info.join('\n'));
});
$('btnViewLog').addEventListener('click', async ()=>{
  const r = await sh(`tail -n 100 ${MODDATA}/logs/module.log 2>/dev/null`);
  showResult('运行日志', r.out || '（无日志）');
});
$('btnClearPref').addEventListener('click', ()=>{
  confirmDlg('清空偏好', '将删除所有书签与偏好设置，确定？', async ()=>{
    await ctl('exec',[btoa(`rm -f ${MODDATA}/prefs/*`)]);
    state.bookmarks=[]; renderBookmarks(); toast('已清空','ok');
  });
});

/* ── 终端 ── */
const TERM_PORT = 7681;
/* 终端(ttyd)所在主机：用当前页面 host（设备IP），回环在应用WebView里不可达 */
function termHost(){
  const h = location.hostname;
  if(!h || h==='localhost' || h==='127.0.0.1') {
    // 页面本身走 http 时，借用页面 host；否则回退
    return (location.protocol.startsWith('http') ? location.hostname : '127.0.0.1');
  }
  return h;
}
function termCmdB64(cmd){ return btoa(unescape(encodeURIComponent(cmd))); }
// 确保 ttyd / shell 就位：缺失则从模块目录复制（自愈）
async function termPrepare(){
  const r = await ctl('exec',[termCmdB64(
    `set -e; ` +
    `mkdir -p ${MODDATA}/bin ${MODDATA}/logs; ` +
    `BIN=${MODDATA}/bin/ttyd; SH=${MODDATA}/bin/xzm-shell.sh; ` +
    `SRCBIN=${moduleDir}/bin/ttyd; SRCSH=${moduleDir}/bin/xzm-shell.sh; ` +
    `echo "src bin exists:"; [ -f "$SRCBIN" ] && echo YES_BIN || echo NO_BIN; ` +
    `echo "src sh exists:"; [ -f "$SRCSH" ] && echo YES_SH || echo NO_SH; ` +
    `if [ ! -x "$BIN" ] && [ -f "$SRCBIN" ]; then cp -f "$SRCBIN" "$BIN" && chmod 0755 "$BIN"; fi; ` +
    `if [ ! -x "$SH" ] && [ -f "$SRCSH" ]; then cp -f "$SRCSH" "$SH" && chmod 0755 "$SH"; fi; ` +
    `if [ -x "$BIN" ]; then echo BIN_OK; else echo BIN_MISSING; fi; ` +
    `if [ -x "$SH" ]; then echo SH_OK; else echo SH_MISSING; fi`
  )]);
  return (r.output || r.error || '').trim();
}
async function startTerminal(target /* 可选：要运行的文件 */){
  busy(true);
  let chk = '';
  try{ chk = await termPrepare(); }catch(e){ busy(false); showResult('终端启动失败','检查阶段异常：'+e.message); return; }
  if(chk.includes('BIN_MISSING')){ busy(false); showResult('终端启动失败','缺少 ttyd 二进制。\n'+chk); return; }
  if(chk.includes('SH_MISSING')){ busy(false); showResult('终端启动失败','缺少 xzm-shell.sh。\n'+chk); return; }
  // JieMoSi 式：把目标文件作为 ttyd shell 的参数传入（运行完进入 root shell）
  const esc = (target||'').replace(/'/g, "'\\''");
  const launch =
    `mkdir -p ${MODDATA}/logs /data/local/tmp 2>/dev/null; ` +
    `echo "=== launch $(date) target='${esc}' ===" >> /data/local/tmp/xzm-ttyd.log 2>&1; ` +
    `pgrep -x ttyd >/dev/null 2>&1 && killall ttyd 2>/dev/null; ` +
    `sleep 0.3; ` +
    `cd ${MODDATA}; ` +
    `( setsid ${MODDATA}/bin/ttyd -p ${TERM_PORT} -i 0.0.0.0 -W -w /data/adb ` +
    `${MODDATA}/bin/xzm-shell.sh ${target ? "'"+esc+"'" : "''"} ` +
    `</dev/null >>${MODDATA}/logs/ttyd.log 2>>/data/local/tmp/xzm-ttyd.log & ) ; ` +
    `sleep 0.5; ` +
    `echo "after-launch pgrep:"; pgrep -x ttyd || echo none; ` +
    `echo DONE`;
  // 不 await 这条（可能因后台任务不返回），用竞速超时
  try{
    await Promise.race([
      ctl('exec',[termCmdB64(launch)]),
      new Promise(res=>setTimeout(()=>res({output:'TIMEOUT'}), 4000))
    ]);
  }catch(e){}
  busy(false);
  toast('终端已启动，正在探测…','ok');
  // 稍后探测是否真的起来了
  setTimeout(async ()=>{
    let st='';
    try{ st = await ctl('exec',[termCmdB64(
      `echo HAVE_CURL:; command -v curl || echo "(no curl)"; ` +
      `echo PROCESS:; pgrep -x ttyd && echo "(running)" || echo "(none)"; ` +
      `echo PORT_NETSTAT:; (netstat -ltn 2>/dev/null | grep ':'${TERM_PORT}) || echo "(netstat 无输出)"; ` +
      `echo PORT_PROC:; (cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -i '1E01') && echo "(端口存在)" || echo "(端口不存在)"; ` +
      `echo TRY_CURL:; (curl -s -m 3 -o /dev/null -w "http=%{http_code}" http://127.0.0.1:${TERM_PORT}/ 2>&1); echo; ` +
      `echo LOG1:; tail -n 15 ${MODDATA}/logs/ttyd.log 2>&1; echo LOG2:; tail -n 15 /data/local/tmp/xzm-ttyd.log 2>&1`
    )]).then(r=>r.output||r.error||''); }catch(e){ st = '探测失败:'+e.message; }
    const portOpen = st.includes('http=200') || st.includes('(端口存在)');
    const running = st.includes('(running)');
    if(portOpen){
      $('termFrame').src = `http://${termHost()}:${TERM_PORT}/?_=${Date.now()}`;
      showResult('终端已就绪 ✓', 'ttyd 正常监听。若下方空白，是 WebView 拦截，请点「新窗口打开」。\n\n' + st);
    } else if(running){
      showResult('ttyd 在跑但端口没通', '进程在，但端口未监听：\n\n' + st);
    } else {
      showResult('终端未启动', 'ttyd 没起来：\n\n' + st);
    }
  }, 2000);
}
$('btnTermStart').addEventListener('click', startTerminal);
$('btnTermStop').addEventListener('click', async ()=>{
  await ctl('exec',[btoa(`pkill -f 'ttyd.*xzm' 2>/dev/null; echo done`)]);
  $('termFrame').src='about:blank';
  toast('终端已停止');
});
$('btnTermOpen').addEventListener('click', ()=>{
  window.open(`http://${termHost()}:${TERM_PORT}/`, '_blank');
});
$('btnTermLog').addEventListener('click', async ()=>{
  busy(true);
  let txt='';
  try{
    const r = await ctl('exec',[termCmdB64(
      `echo '=== ttyd 进程 ==='; pgrep -x ttyd || echo '(无)'; ` +
      `echo '=== 端口 ${TERM_PORT} ==='; (netstat -ltn 2>/dev/null | grep ':'${TERM_PORT}) || echo '(未监听)'; ` +
      `echo '=== curl 测试 ==='; curl -s -o /dev/null -w "http=%{http_code}\n" http://127.0.0.1:${TERM_PORT}/ 2>&1 || echo '(curl 失败)'; ` +
      `echo '=== 日志(${MODDATA}) ==='; tail -n 30 ${MODDATA}/logs/ttyd.log 2>&1; echo '=== 日志(/data/local/tmp) ==='; tail -n 30 /data/local/tmp/xzm-ttyd.log 2>&1`)]);
    txt = r.output || r.error || '（空）';
  }catch(e){ txt = '读取失败: ' + e.message; }
  busy(false);
  showResult('ttyd 日志', txt);
});

/* ══ 初始化 ══ */
let envName = '检测中';
(function init(){
  var step = window.__xzmStep || function(){};
  step('init-start');
  // 1) 先立即绑定所有 UI 交互 —— 保证无论后端如何，按钮都能点
  try{
    bindPane('A'); bindPane('B');
    step('panes-bound');
    if(typeof bindToolbar==='function') bindToolbar();
    if(typeof bindEditor==='function') bindEditor();
    if(typeof bindTerminal==='function') bindTerminal();
  }catch(e){ console.error('绑定 UI 失败', e); step('bind-ERR:'+e.message); }

  // 2) 全局错误兜底，直接显示在界面上，方便排查
  window.addEventListener('error', ev=>{
    try{
      var m = '脚本错误: ' + (ev.message||ev.error);
      window.__xzmLastErr = m + ' @' + (ev.filename||'') + ':' + (ev.lineno||'');
      toast(m, 'err');
    }catch(_){}
  });
  window.addEventListener('unhandledrejection', ev=>{
    try{
      var r = ev.reason;
      var msg = (r && (r.message || r.stack)) || String(r);
      window.__xzmLastErr = '异步错误: ' + msg;
      toast('异步错误: ' + (r && r.message || r), 'err');
      // 写诊断日志（走 cgi，失败静默），便于下次真机排查
      try{ if(typeof sh==='function') sh('echo "[xzm-js-err $(date)] "+"'+String(msg).replace(/['"\\\n\r]/g,' ').slice(0,300)+'" >> /data/local/tmp/xzm-js-err.log 2>&1'); }catch(_){}
    }catch(_){}
  });
  step('handlers-ok');

  // 3) 再做异步的后端探测/加载（失败不影响按钮可点）
  (async ()=>{
    try{
      await detectModuleDir();
      step('moddir=' + moduleDir.split('/').pop());
    }catch(e){ console.error('detectModuleDir', e); step('moddir-ERR'); }
    let env='fallback';
    try{
      env = await initBridge();
      step('bridge=' + env);
    }catch(e){ console.error('initBridge', e); step('bridge-ERR:'+e.message); }
    envName = (env==='kernelsu') ? 'KernelSU WebUI'
            : (env==='httpcgi') ? '本地服务' : '浏览器降级';
    const chip = $('chipEnv');
    if(chip){
      chip.textContent = (env==='kernelsu') ? 'KernelSU ✓'
                       : (env==='httpcgi') ? '本地服务 ✓' : '调试模式';
      if(env==='kernelsu' || env==='httpcgi') chip.classList.add('root');
    }
    const sub = $('brandSub');
    if(sub) sub.textContent = '文件管理 · Root 终端 · ' + envName;

    try{ await loadBookmarks(); }catch(e){ console.error('loadBookmarks', e); }
    try{
      await loadDir('A','/sdcard', {noHistory:true});
      step('listA=' + (state.entries.A?state.entries.A.length:'?'));
    }catch(e){ console.error('loadA', e); step('listA-ERR:'+e.message); toast('左栏加载失败: '+e.message,'err'); }
    try{ await loadDir('B','/sdcard/Download', {noHistory:true}); }catch(e){ console.error('loadB', e); }
    state.history.A = [state.path.A];
    state.history.B = [state.path.B];
    step('done');
    // 全部成功 → 3 秒后隐藏探针
    setTimeout(()=>{ var el=document.getElementById('bootProbe'); if(el && !el.textContent.match(/ERR|错误/)) el.style.display='none'; }, 3000);
  })();
})();
