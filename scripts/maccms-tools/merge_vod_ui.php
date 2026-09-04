<?php
/**
 * 影视合并可视化台
 *
 * 打开：
 *   /maccms-tools/merge_vod_ui.php?key=huihuo_merge_2026
 *
 * 功能：封面对比表格、待合并队列增删、服务器+本地双备份、确认后执行合并
 */
declare(strict_types=1);

@ini_set('memory_limit', '512M');
@set_time_limit(0);

require __DIR__ . '/merge_lib.php';

$key = isset($_GET['key']) ? (string)$_GET['key'] : (isset($_POST['key']) ? (string)$_POST['key'] : '');
$api = isset($_GET['api']) ? (string)$_GET['api'] : (isset($_POST['api']) ? (string)$_POST['api'] : '');

if (!mergeKeyAllowed($key)) {
    http_response_code(403);
    header('Content-Type: text/plain; charset=utf-8');
    echo "forbidden: key 不对\n请用 ?key=huihuo_merge_2026\n";
    exit(1);
}

if ($api !== '') {
    header('Content-Type: application/json; charset=utf-8');
    try {
        list($pdo, $root, $table) = mergeConnect(__DIR__);
        $table = str_replace('`', '', $table);
        list($metaCols, $metaSql, $cols) = mergeMetaSql($pdo, $table);
        $queueFile = mergeQueuePath(__DIR__);

        if ($api === 'queue_load') {
            $data = ['updated_at' => '', 'queue' => [], 'level' => 'safe'];
            if (is_file($queueFile)) {
                $raw = json_decode((string)file_get_contents($queueFile), true);
                if (is_array($raw)) {
                    $data = array_merge($data, $raw);
                }
            }
            echo json_encode(['ok' => true, 'data' => $data], JSON_UNESCAPED_UNICODE);
            exit;
        }

        if ($api === 'queue_save') {
            $body = json_decode((string)file_get_contents('php://input'), true);
            if (!is_array($body)) {
                throw new RuntimeException('JSON 无效');
            }
            $payload = [
                'updated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'level' => isset($body['level']) ? $body['level'] : 'safe',
                'queue' => isset($body['queue']) && is_array($body['queue']) ? $body['queue'] : [],
            ];
            file_put_contents($queueFile, json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
            echo json_encode(['ok' => true, 'updated_at' => $payload['updated_at'], 'count' => count($payload['queue'])], JSON_UNESCAPED_UNICODE);
            exit;
        }

        if ($api === 'suggest') {
            $level = isset($_GET['level']) ? (string)$_GET['level'] : 'safe';
            $limit = isset($_GET['limit']) ? (int)$_GET['limit'] : 200;
            $limit = max(10, min(500, $limit));
            $cfg = mergeLevelCfg($level);
            mergeTypeMapStore(mergeLoadTypeMap($pdo, $table));
            $excludeIds = [];
            if (!empty($_GET['exclude'])) {
                foreach (explode(',', (string)$_GET['exclude']) as $x) {
                    $id = (int)trim($x);
                    if ($id > 0) {
                        $excludeIds[$id] = true;
                    }
                }
            }
            $res = mergeScanSuggest($pdo, $table, $metaSql, $cfg, $level, $limit, '', $excludeIds);
            echo json_encode(['ok' => true] + $res, JSON_UNESCAPED_UNICODE);
            exit;
        }

        if ($api === 'search') {
            $name = isset($_GET['name']) ? (string)$_GET['name'] : '';
            $level = isset($_GET['level']) ? (string)$_GET['level'] : 'safe';
            mergeTypeMapStore(mergeLoadTypeMap($pdo, $table));
            $groups = mergeSearchName($pdo, $table, $metaSql, $name, 50);
            // 给每组附上两两判定，方便手动勾选
            $cfg = mergeLevelCfg($level);
            foreach ($groups as &$g) {
                $ids = array_map(function ($m) {
                    return $m['vod_id'];
                }, $g['members']);
                $rows = mergeLoadByIds($pdo, $table, $metaSql, $ids);
                $hints = [];
                for ($i = 0; $i < count($rows); $i++) {
                    for ($j = $i + 1; $j < count($rows); $j++) {
                        $jdg = mergeJudgePair($rows[$i], $rows[$j], $cfg);
                        $hints[] = [
                            'a' => (int)$rows[$i]['vod_id'],
                            'b' => (int)$rows[$j]['vod_id'],
                            'verdict' => $jdg['verdict'],
                            'score' => $jdg['score'],
                            'why' => $jdg['why'],
                        ];
                    }
                }
                $g['pair_hints'] = $hints;
            }
            unset($g);
            echo json_encode(['ok' => true, 'groups' => $groups], JSON_UNESCAPED_UNICODE);
            exit;
        }

        if ($api === 'execute') {
            $confirm = isset($_GET['confirm']) ? (string)$_GET['confirm'] : '';
            if ($confirm !== 'YES') {
                throw new RuntimeException('需要 confirm=YES');
            }
            $body = json_decode((string)file_get_contents('php://input'), true);
            $queue = isset($body['queue']) && is_array($body['queue']) ? $body['queue'] : [];
            if ($queue === []) {
                throw new RuntimeException('待合并列表为空');
            }
            $results = [];
            $pdo->beginTransaction();
            try {
                foreach ($queue as $g) {
                    $results[] = mergeApplyGroup($pdo, $table, $cols, $g);
                }
                $pdo->commit();
            } catch (Throwable $e) {
                $pdo->rollBack();
                throw $e;
            }
            // 清空队列文件
            file_put_contents($queueFile, json_encode([
                'updated_at' => gmdate('Y-m-d\TH:i:s\Z'),
                'level' => 'safe',
                'queue' => [],
                'last_execute' => $results,
            ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
            echo json_encode(['ok' => true, 'results' => $results], JSON_UNESCAPED_UNICODE);
            exit;
        }

        throw new RuntimeException('未知 api');
    } catch (Throwable $e) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
        exit;
    }
}

// -------- HTML UI --------
$keyJs = htmlspecialchars($key, ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>影视合并台</title>
<style>
:root {
  --bg:#0f1419; --panel:#161d26; --line:#2a3542; --text:#e8eef4; --muted:#8b9aab;
  --accent:#3ddc97; --warn:#f0b429; --danger:#ff6b6b; --head:48px; --foot:150px;
}
*{box-sizing:border-box}
html,body{height:100%;margin:0}
body{
  font-family:"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;
  background:var(--bg);color:var(--text);font-size:14px;line-height:1.4;
  display:flex;flex-direction:column;overflow:hidden;
}
header{
  height:auto;min-height:var(--head);flex:0 0 auto;display:flex;align-items:center;gap:10px;flex-wrap:wrap;
  padding:8px 12px;border-bottom:1px solid var(--line);background:#121820;
}
header h1{font-size:16px;margin:0;font-weight:600}
.btn{border:1px solid var(--line);background:var(--panel);color:var(--text);border-radius:6px;padding:6px 12px;cursor:pointer;font-size:13px}
.btn.primary{background:#1f6f54;border-color:#2a9b74}
.btn.danger{background:#5a2424;border-color:#8a3333}
.btn:disabled{opacity:.45}
select,input[type=text]{background:var(--panel);border:1px solid var(--line);color:var(--text);border-radius:6px;padding:6px 10px;font-size:13px}
.badge{display:inline-block;min-width:18px;padding:1px 7px;border-radius:999px;background:#314155;font-size:12px;margin-left:4px}
.workspace{flex:1;min-height:0;display:grid;grid-template-columns:1fr 1fr;gap:0}
.col{min-width:0;min-height:0;display:flex;flex-direction:column;border-right:1px solid var(--line)}
.col:last-child{border-right:0}
.col-hd{
  flex:0 0 auto;display:flex;align-items:center;gap:8px;flex-wrap:wrap;
  padding:8px 10px;background:#121820;border-bottom:1px solid var(--line);position:sticky;top:0;z-index:2;
}
.col-hd .tt{font-weight:600;font-size:14px}
.col-hd.ok .tt{color:var(--accent)}
.col-hd.warn .tt{color:var(--warn)}
.col-bd{flex:1;overflow:auto;padding:8px 10px 12px}
.row{
  display:grid;grid-template-columns:22px 72px 72px 1fr auto;gap:10px;align-items:start;
  border:1px solid var(--line);border-radius:8px;padding:10px;margin-bottom:8px;background:var(--panel);
}
.row.in-queue{border-color:#2a9b74;background:#14241d}
.row > input{margin-top:28px}
.row img.cover{width:72px;height:100px;object-fit:cover;border-radius:5px;background:#0b1015;border:1px solid var(--line)}
.row .info{min-width:0}
.row .title{font-weight:700;font-size:15px;margin-bottom:4px}
.row .ids{color:var(--muted);font-size:12px;margin-bottom:6px}
.compare{display:flex;flex-direction:column;gap:4px}
.cmp-line{font-size:12px;line-height:1.45}
.cmp-line .lab{font-weight:600;margin-right:4px}
.cmp-line.same .lab{color:var(--accent)}
.cmp-line.diff .lab{color:var(--danger)}
.cmp-line.note .lab{color:var(--muted)}
.tag{display:inline-block;font-size:11px;padding:2px 7px;border-radius:999px;background:#243041;color:var(--muted);white-space:nowrap;margin-right:4px}
.tag.ok{background:#1d3d32;color:var(--accent)}
.tag.warn{background:#3d3218;color:var(--warn)}
.tag.score{background:#243a55;color:#9ec5ff}
.empty{padding:24px;text-align:center;color:var(--muted);font-size:13px}
.queue-bar{
  flex:0 0 auto;height:var(--foot);border-top:1px solid var(--line);background:#121820;
  display:grid;grid-template-rows:36px 1fr;min-height:0;
}
.queue-hd{display:flex;align-items:center;gap:10px;padding:0 12px;border-bottom:1px solid var(--line);font-size:13px}
.queue-bd{overflow:auto;padding:8px 10px;display:flex;flex-wrap:wrap;gap:8px;align-content:flex-start}
.qchip{
  display:flex;align-items:center;gap:6px;border:1px solid var(--line);border-radius:6px;
  padding:4px 8px 4px 4px;background:var(--panel);max-width:280px;
}
.qchip img{width:32px;height:44px;object-fit:cover;border-radius:4px}
.qchip .t{font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:150px}
.qchip button{border:0;background:transparent;color:var(--danger);cursor:pointer;font-size:18px;padding:0 4px}
.search-pop{
  display:none;position:fixed;inset:56px 8% 160px;background:#121820;border:1px solid var(--line);
  border-radius:8px;z-index:40;padding:12px;overflow:auto;
}
.search-pop.on{display:block}
.status{position:fixed;right:10px;bottom:158px;background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:6px 10px;color:var(--muted);font-size:12px;z-index:30;max-width:40vw}
.member-pick{display:flex;flex-wrap:wrap;gap:8px}
.pick{width:90px;border:1px solid var(--line);border-radius:6px;padding:4px;cursor:pointer;background:var(--panel)}
.pick.on{border-color:var(--accent)}
.pick img{width:100%;height:110px;object-fit:cover;border-radius:4px}
.pick .meta{font-size:11px;color:var(--muted)}
@media (max-width:900px){
  .workspace{grid-template-columns:1fr}
  body{overflow:auto}
  .workspace{min-height:70vh}
  .row{grid-template-columns:22px 60px 60px 1fr}
  .row img.cover{width:60px;height:84px}
}
</style>
</head>
<body>
<header>
  <h1>影视合并台</h1>
  <label>规则
    <select id="level">
      <option value="safe" selected>safe</option>
      <option value="strict">strict</option>
      <option value="normal">normal</option>
    </select>
  </label>
  <button class="btn" id="btnScan">扫描两侧列表</button>
  <button class="btn" id="btnReload">加载队列</button>
  <button class="btn" id="btnSave">保存</button>
  <button class="btn" id="btnSearchOpen">手动搜索</button>
  <span style="margin-left:auto;color:var(--muted);font-size:12px">短剧整类跳过 · 左=强匹配 · 右=待确认 · 加入后自动刷新</span>
</header>

<div class="workspace">
  <section class="col" id="colSuggest">
    <div class="col-hd ok">
      <span class="tt">确定可合并（最匹配优先）</span>
      <span class="badge" id="bs">0</span>
      <label style="margin-left:6px"><input type="checkbox" id="chkAllL"> 全选</label>
      <button class="btn primary" id="btnAddL">加入底部待执行</button>
    </div>
    <div class="col-bd" id="panel-suggest"><div class="empty">点「扫描两侧列表」加载</div></div>
  </section>
  <section class="col" id="colUnsure">
    <div class="col-hd warn">
      <span class="tt">待确认（封面不同/存疑）</span>
      <span class="badge" id="bu">0</span>
      <label style="margin-left:6px"><input type="checkbox" id="chkAllR"> 全选</label>
      <button class="btn primary" id="btnAddR">加入底部待执行</button>
    </div>
    <div class="col-bd" id="panel-unsure"><div class="empty">点「扫描两侧列表」加载</div></div>
  </section>
</div>

<div class="queue-bar">
  <div class="queue-hd">
    <b>待执行合并</b>
    <span class="badge" id="bq">0</span>
    <span style="color:var(--muted);font-size:11px" id="queueHint">勾选左右条目加入此处</span>
    <span style="margin-left:auto"></span>
    <button class="btn danger" id="btnClear">清空</button>
    <button class="btn primary" id="btnExec">确认执行合并</button>
  </div>
  <div class="queue-bd" id="panel-queue"></div>
</div>

<div class="search-pop" id="searchPop">
  <div class="search-bar" style="display:flex;gap:6px;margin-bottom:8px">
    <input type="text" id="qname" placeholder="片名搜索" style="flex:1">
    <button class="btn primary" id="btnSearch">搜索</button>
    <button class="btn" id="btnSearchClose">关闭</button>
  </div>
  <div id="searchResult"></div>
</div>
<div class="status" id="status">就绪</div>

<script>
const KEY = <?= json_encode($key, JSON_UNESCAPED_UNICODE) ?>;
const LS_KEY = 'maccms_merge_queue_v1';
const state = {
  level: 'safe',
  queue: [],
  suggest: [],
  unsure: [],
  updated_at: '',
  saving: false,
  scanning: false,
};

const $ = (id) => document.getElementById(id);
const statusEl = $('status');
function setStatus(msg) { statusEl.textContent = msg; }

function apiUrl(api, extra = {}) {
  const u = new URL(location.href);
  u.searchParams.set('key', KEY);
  u.searchParams.set('api', api);
  Object.entries(extra).forEach(([k,v]) => {
    if (v === undefined || v === null || v === '') return;
    u.searchParams.set(k, v);
  });
  return u.toString();
}
async function apiGet(api, extra = {}) {
  const r = await fetch(apiUrl(api, extra), { credentials: 'same-origin' });
  const j = await r.json();
  if (!j.ok) throw new Error(j.error || '请求失败');
  return j;
}
async function apiPost(api, body, extra = {}) {
  const r = await fetch(apiUrl(api, extra), {
    method: 'POST', credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const j = await r.json();
  if (!j.ok) throw new Error(j.error || '请求失败');
  return j;
}
function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
function pic(url) {
  const u = String(url || '');
  if (!u) return 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="72" height="100"><rect fill="#1a222c" width="100%" height="100%"/><text x="50%" y="54%" fill="#8b9aab" font-size="12" text-anchor="middle">无图</text></svg>');
  return u;
}
function inQueue(gid) { return state.queue.some(x => x.gid === gid); }

function queuedIdSet() {
  const s = new Set();
  state.queue.forEach(g => {
    s.add(Number(g.keep_id));
    (g.remove_ids || []).forEach(id => s.add(Number(id)));
  });
  return s;
}

function groupTouchesQueue(g) {
  const ids = queuedIdSet();
  if (ids.has(Number(g.keep_id))) return true;
  return (g.remove_ids || []).some(id => ids.has(Number(id)));
}

function stripQueuedFromLists() {
  state.suggest = state.suggest.filter(g => !groupTouchesQueue(g));
  state.unsure = state.unsure.filter(g => !groupTouchesQueue(g));
}

function cmpHtml(g) {
  const c = g.compare || {};
  const same = (c.same || []).map(esc);
  const diff = (c.diff || []).map(esc);
  const note = (c.note || []).map(esc);
  const lines = [];
  if (same.length) lines.push(`<div class="cmp-line same"><span class="lab">相同：</span>${same.join('；')}</div>`);
  if (diff.length) lines.push(`<div class="cmp-line diff"><span class="lab">不同：</span>${diff.join('；')}</div>`);
  if (note.length) lines.push(`<div class="cmp-line note"><span class="lab">缺字段：</span>${note.join('；')}</div>`);
  if (!lines.length) lines.push(`<div class="cmp-line note"><span class="lab">说明：</span>${esc(g.reason || '')}</div>`);
  return `<div class="compare">${lines.join('')}</div>`;
}

function groupRow(g, mode) {
  const members = g.members || [];
  const queued = inQueue(g.gid);
  const a = members[0] || {};
  const b = members[1] || members[0] || {};
  const score = g.score != null ? `<span class="tag score">分${g.score}</span>` : '';
  const coverTag = (g.compare && g.compare.cover === 'diff')
    ? '<span class="tag warn">封面不同</span>'
    : (g.compare && g.compare.cover === 'same' ? '<span class="tag ok">封面相同</span>' : '');
  return `<div class="row ${queued?'in-queue':''}" data-gid="${esc(g.gid)}">
    <input type="checkbox" class="gchk" data-gid="${esc(g.gid)}" data-mode="${esc(mode)}" ${queued?'disabled':''}>
    <img class="cover" src="${esc(pic(a.vod_pic))}" loading="lazy" onerror="this.src='${pic('')}'" title="保留 #${a.vod_id}">
    <img class="cover" src="${esc(pic(b.vod_pic))}" loading="lazy" onerror="this.src='${pic('')}'" title="合并 #${b.vod_id||''}">
    <div class="info">
      <div class="title">${esc(g.title)} ${score} ${coverTag} ${queued?'<span class="tag ok">已选</span>':''}</div>
      <div class="ids">保留 #${g.keep_id} ← 删除 ${(g.remove_ids||[]).map(id=>'#'+id).join(' ')} · ${esc(a.kind_label||'?')}/${esc(b.kind_label||'?')} · ${esc(a.type_root||a.type_name||'')} / ${esc(b.type_root||b.type_name||'')} · 集数 ${a.vod_total||0}/${b.vod_total||0}</div>
      ${cmpHtml(g)}
    </div>
    <div>
      ${queued
        ? `<button class="btn danger" type="button" data-act="remove" data-gid="${esc(g.gid)}">移出</button>`
        : `<button class="btn primary" type="button" data-act="add" data-gid="${esc(g.gid)}" data-mode="${esc(mode)}">加入</button>`}
    </div>
  </div>`;
}

function renderList(el, list, mode) {
  const visible = list.filter(g => !groupTouchesQueue(g));
  if (!visible.length) {
    el.innerHTML = `<div class="empty">${mode==='suggest'?'暂无「确定可合并」':'暂无「待确认」'}，点扫描或等待刷新</div>`;
    return;
  }
  el.innerHTML = visible.map(g => groupRow(g, mode)).join('');
}

function queueChips() {
  const el = $('panel-queue');
  if (!state.queue.length) {
    el.innerHTML = '<div class="empty" style="padding:8px">左右勾选后点「加入底部待执行」</div>';
    return;
  }
  el.innerHTML = state.queue.map(g => {
    const m = (g.members && g.members[0]) || {};
    return `<div class="qchip" title="${esc(g.reason||'')}">
      <img src="${esc(pic(m.vod_pic))}" onerror="this.src='${pic('')}'">
      <span class="t">${esc(g.title)}</span>
      <span class="tag">保留#${g.keep_id}</span>
      <button type="button" data-act="remove" data-gid="${esc(g.gid)}" title="移除">×</button>
    </div>`;
  }).join('');
}

function render() {
  const vs = state.suggest.filter(g => !groupTouchesQueue(g)).length;
  const vu = state.unsure.filter(g => !groupTouchesQueue(g)).length;
  $('bs').textContent = vs;
  $('bu').textContent = vu;
  $('bq').textContent = state.queue.length;
  $('queueHint').textContent = `已选 ${state.queue.length} 组 · ${state.updated_at || '未同步'}`;
  renderList($('panel-suggest'), state.suggest, 'suggest');
  renderList($('panel-unsure'), state.unsure, 'unsure');
  queueChips();
  $('chkAllL').checked = false;
  $('chkAllR').checked = false;
}

async function refreshLists(msg) {
  if (state.scanning) return;
  state.scanning = true;
  state.level = $('level').value;
  const exclude = [...queuedIdSet()].join(',');
  if (msg) setStatus(msg);
  $('btnScan').disabled = true;
  try {
    const j = await apiGet('suggest', { level: state.level, limit: '200', exclude });
    state.suggest = j.suggest || [];
    state.unsure = j.unsure || [];
    setStatus(`左确定 ${state.suggest.length} · 右待确认 ${state.unsure.length} · 底待执行 ${state.queue.length}` +
      (j.stats && j.stats.skipped_short ? ` · 已跳过短剧 ${j.stats.skipped_short}` : ''));
    render();
  } catch (e) {
    setStatus('刷新列表失败: ' + e.message);
  } finally {
    state.scanning = false;
    $('btnScan').disabled = false;
  }
}

async function afterAdd(n) {
  stripQueuedFromLists();
  scheduleSave();
  render();
  setStatus(`已加入 ${n} 组，正在加载新列表…`);
  await refreshLists();
}

function persistLocal() {
  try {
    localStorage.setItem(LS_KEY, JSON.stringify({
      updated_at: state.updated_at || new Date().toISOString(),
      level: state.level,
      queue: state.queue,
    }));
  } catch (e) {}
}
let saveTimer = null;
function scheduleSave() {
  persistLocal();
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveServer, 500);
}
async function saveServer() {
  if (state.saving) return;
  state.saving = true;
  try {
    const j = await apiPost('queue_save', { level: state.level, queue: state.queue });
    state.updated_at = j.updated_at;
    persistLocal();
    setStatus(`已保存 ${j.count} 组`);
    render();
  } catch (e) {
    setStatus('保存失败: ' + e.message);
  } finally {
    state.saving = false;
  }
}

function findGroup(gid, mode) {
  if (mode === 'suggest') return state.suggest.find(x => x.gid === gid);
  if (mode === 'unsure') return state.unsure.find(x => x.gid === gid);
  return state.queue.find(x => x.gid === gid) || state.suggest.find(x => x.gid === gid) || state.unsure.find(x => x.gid === gid);
}

function addToQueue(g, { silent = false } = {}) {
  if (!g) return false;
  if (state.queue.some(x => x.gid === g.gid)) {
    if (!silent) setStatus('已在待执行: ' + g.title);
    return false;
  }
  const ids = new Set([g.keep_id, ...(g.remove_ids || [])]);
  for (const q of state.queue) {
    const qids = [q.keep_id, ...(q.remove_ids || [])];
    if (qids.some(id => ids.has(id))) {
      if (silent) return false;
      if (!confirm(`与「${q.title}」ID 冲突，仍加入？`)) return false;
      break;
    }
  }
  state.queue.unshift(JSON.parse(JSON.stringify(g)));
  if (!silent) setStatus('已加入: ' + g.title);
  return true;
}

function addChecked(side) {
  const root = side === 'L' ? $('panel-suggest') : $('panel-unsure');
  const boxes = [...root.querySelectorAll('.gchk:checked:not(:disabled)')];
  if (!boxes.length) { alert('请先勾选'); return; }
  let n = 0;
  boxes.forEach(b => {
    if (addToQueue(findGroup(b.dataset.gid, b.dataset.mode), { silent: true })) n++;
  });
  if (n > 0) afterAdd(n);
  else setStatus('没有新加入的组');
}

function removeFromQueue(gid) {
  state.queue = state.queue.filter(g => g.gid !== gid);
  scheduleSave();
  render();
}

document.body.addEventListener('click', (e) => {
  const btn = e.target.closest('[data-act]');
  if (!btn) return;
  if (btn.dataset.act === 'remove') removeFromQueue(btn.dataset.gid);
  if (btn.dataset.act === 'add') {
    if (addToQueue(findGroup(btn.dataset.gid, btn.dataset.mode))) {
      afterAdd(1);
    }
  }
});

$('btnAddL').addEventListener('click', () => addChecked('L'));
$('btnAddR').addEventListener('click', () => addChecked('R'));
$('chkAllL').addEventListener('change', e => {
  $('panel-suggest').querySelectorAll('.gchk:not(:disabled)').forEach(c => c.checked = e.target.checked);
});
$('chkAllR').addEventListener('change', e => {
  $('panel-unsure').querySelectorAll('.gchk:not(:disabled)').forEach(c => c.checked = e.target.checked);
});

$('level').addEventListener('change', e => { state.level = e.target.value; scheduleSave(); });
$('btnSave').addEventListener('click', () => saveServer());
$('btnClear').addEventListener('click', () => {
  if (!state.queue.length) return;
  if (!confirm('清空待执行？')) return;
  state.queue = [];
  scheduleSave();
  render();
});
$('btnReload').addEventListener('click', async () => {
  try {
    const j = await apiGet('queue_load');
    const server = j.data || {};
    let local = null;
    try { local = JSON.parse(localStorage.getItem(LS_KEY) || 'null'); } catch (e) {}
    const sAt = server.updated_at || '';
    const lAt = local && local.updated_at ? local.updated_at : '';
    if (lAt && (!sAt || lAt > sAt) && local.queue?.length && confirm('本机队列更新，用本机？')) {
      state.queue = local.queue; state.level = local.level || 'safe'; state.updated_at = local.updated_at;
    } else {
      state.queue = server.queue || []; state.level = server.level || 'safe'; state.updated_at = server.updated_at || '';
    }
    $('level').value = state.level;
    persistLocal();
    setStatus(`队列 ${state.queue.length} 组`);
    render();
  } catch (e) { setStatus('加载失败: ' + e.message); }
});

$('btnScan').addEventListener('click', () => {
  refreshLists('扫描中（跳过短剧 + 已在待执行的 ID）…');
});

$('btnSearchOpen').addEventListener('click', () => $('searchPop').classList.add('on'));
$('btnSearchClose').addEventListener('click', () => $('searchPop').classList.remove('on'));
$('btnSearch').addEventListener('click', async () => {
  const name = $('qname').value.trim();
  if (!name) return;
  setStatus('搜索中…');
  try {
    const j = await apiGet('search', { name, level: $('level').value });
    const box = $('searchResult');
    if (!j.groups.length) { box.innerHTML = '<div class="empty">无结果</div>'; return; }
    box.innerHTML = j.groups.map((g, gi) => {
      const picks = g.members.map(m => `
        <div class="pick" data-gi="${gi}" data-id="${m.vod_id}" onclick="this.classList.toggle('on')">
          <img src="${esc(pic(m.vod_pic))}" onerror="this.src='${pic('')}'">
          <div class="meta">#${m.vod_id} ${esc(m.vod_year||'')}</div>
        </div>`).join('');
      return `<div style="border:1px solid var(--line);border-radius:6px;padding:6px;margin-bottom:6px" id="sg_${gi}">
        <div style="display:flex;gap:6px;align-items:center;margin-bottom:4px">
          <b>${esc(g.title)}</b><span class="tag">${g.count}</span>
          <button class="btn primary" style="margin-left:auto" onclick="addPicked(${gi})">勾选加入待执行</button>
        </div>
        <div class="member-pick">${picks}</div>
      </div>`;
    }).join('');
    window.__searchGroups = j.groups;
    setStatus(`找到 ${j.groups.length} 组`);
  } catch (e) { setStatus('搜索失败: ' + e.message); }
});

window.addPicked = (gi) => {
  const g = window.__searchGroups[gi];
  const root = document.getElementById('sg_' + gi);
  const ids = [...root.querySelectorAll('.pick.on')].map(el => Number(el.dataset.id));
  if (ids.length < 2) { alert('至少勾选 2 条'); return; }
  const members = g.members.filter(m => ids.includes(m.vod_id));
  const keep_id = members[0].vod_id;
  const ok = addToQueue({
    gid: 'manual_' + ids.slice().sort((a,b)=>a-b).join('_'),
    title: g.title, keep_id,
    remove_ids: ids.filter(id => id !== keep_id),
    play_from: members.map(m => m.vod_play_from).filter(Boolean).join(' / '),
    reason: '手动添加', score: null, source: 'manual', members,
  });
  if (ok) {
    $('searchPop').classList.remove('on');
    afterAdd(1);
  }
};

$('btnExec').addEventListener('click', async () => {
  if (!state.queue.length) return;
  if (!confirm(`确认合并 ${state.queue.length} 组？`)) return;
  if (!confirm('再次确认已核对？')) return;
  setStatus('执行中…');
  $('btnExec').disabled = true;
  try {
    const j = await apiPost('execute', { queue: state.queue }, { confirm: 'YES' });
    state.queue = [];
    persistLocal();
    setStatus(`完成 ${j.results.length} 组，请清 CMS 缓存`);
    render();
    alert('合并完成 ' + j.results.length + ' 组');
  } catch (e) {
    setStatus('失败: ' + e.message);
    alert(e.message);
  } finally {
    $('btnExec').disabled = false;
  }
});

(async function init() {
  try {
    const local = JSON.parse(localStorage.getItem(LS_KEY) || 'null');
    if (local?.queue) {
      state.queue = local.queue;
      state.level = local.level || 'safe';
      state.updated_at = local.updated_at || '';
    }
  } catch (e) {}
  $('level').value = state.level;
  render();
  try {
    const j = await apiGet('queue_load');
    const server = j.data || {};
    if ((server.queue || []).length) {
      if (!state.queue.length || (server.updated_at && server.updated_at >= (state.updated_at || ''))) {
        state.queue = server.queue;
        state.updated_at = server.updated_at;
        state.level = server.level || state.level;
        $('level').value = state.level;
        persistLocal();
      }
    } else if (state.queue.length) {
      await saveServer();
    }
    setStatus(`待执行 ${state.queue.length} 组 · 点扫描加载左右列表`);
    render();
  } catch (e) {
    setStatus('队列读取失败，用本机备份');
  }
})();
</script>
</body>
</html>
