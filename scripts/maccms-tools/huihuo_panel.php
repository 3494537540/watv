<?php
/**
 * 灰火 / 哇TV · CMS 扩展控制台
 *
 * 上传到站点：/maccms-tools/huihuo_panel.php（需与 mac_bootstrap.php 同目录）
 * 后台自定义菜单：
 *   /maccms-tools/huihuo_panel.php?key=huihuo_panel_2026
 *
 * App 公开接口（无需 key）：
 *   ?api=notify_list
 *   ?api=app_update&platform=android|ios
 *   ?api=website                     （官网：双端安装包 + 更新日志）
 *   ?api=app_config
 *   ?api=update_report  (POST JSON)
 *   ?api=img_proxy&u=https%3A%2F%2F...   （封面反代，解决部分 CDN 客户端不可达）
 *   ?api=cms_proxy&target=vod|art|website&...  （H5 跨域：转发 provide JSON）
 *   ?api=redeem  (POST JSON: code,user_id,user_name) 兑换码
 *   ?api=vod_collect_sync  扫描 mac_vod 新增片源并写入公告
 *   ?api=user_vip&user_id=  查询会员组/到期时间（对接 App 个人页）
 *   ?api=checkin  (POST JSON: user_id) 每日打卡加积分
 *   ?api=checkin_status&user_id=  打卡状态
 *   ?api=art_detail&id=  文章详情（DB 正文）
 *   ?api=qq_oauth  (POST JSON: openid,access_token,nickname?) QQ 授权登录
 *
 * 密钥：huihuo_panel_2026
 */
declare(strict_types=1);

require_once __DIR__ . '/mac_bootstrap.php';

const HUIHUO_PANEL_KEY = 'huihuo_panel_2026';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$root = macFindRoot(__DIR__);
if ($root === null) {
    http_response_code(500);
    echo '找不到 MacCMS 根目录（application/database.php）';
    exit;
}

try {
    $pdo = macPdo($root);
} catch (Throwable $e) {
    http_response_code(500);
    echo '数据库连接失败：' . htmlspecialchars($e->getMessage());
    exit;
}

$dbCfg = macLoadDbConfig($root);
$prefix = $dbCfg && !empty($dbCfg['prefix']) ? $dbCfg['prefix'] : 'mac_';
$tNotify = $prefix . 'huihuo_notify';
$tUpdate = $prefix . 'huihuo_app_update';
$tConfig = $prefix . 'huihuo_kv';
$tLog = $prefix . 'huihuo_update_log';
$tRedeem = $prefix . 'huihuo_redeem';
$tChangelog = $prefix . 'huihuo_changelog';

huihuoEnsureTables($pdo, $tNotify, $tUpdate, $tConfig, $tLog, $tRedeem, $tChangelog);

$api = isset($_GET['api']) ? trim((string)$_GET['api']) : '';
if ($api === 'img_proxy') {
    huihuoServeImgProxy($root);
    exit;
}
if ($api === 'cms_proxy') {
    huihuoServeCmsProxy();
    exit;
}
if ($api !== '') {
    huihuoHandleApi($pdo, $api, $tNotify, $tUpdate, $tConfig, $tLog, $tRedeem, $root, $prefix, $tChangelog);
    exit;
}

$key = isset($_GET['key']) ? (string)$_GET['key'] : (isset($_POST['key']) ? (string)$_POST['key'] : '');
if ($key !== HUIHUO_PANEL_KEY) {
    http_response_code(403);
    echo '密钥错误。自定义菜单地址请带 ?key=' . HUIHUO_PANEL_KEY;
    exit;
}

$tab = isset($_GET['tab']) ? (string)$_GET['tab'] : 'notify';
$msg = '';
$err = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = isset($_POST['action']) ? (string)$_POST['action'] : '';
    try {
        if ($action === 'notify_add') {
            $title = trim((string)($_POST['title'] ?? ''));
            $body = trim((string)($_POST['body'] ?? ''));
            $link = trim((string)($_POST['link'] ?? ''));
            $tag = trim((string)($_POST['tag'] ?? ''));
            $subtitle = trim((string)($_POST['subtitle'] ?? ''));
            $accent = trim((string)($_POST['accent'] ?? ''));
            $style = trim((string)($_POST['style'] ?? 'normal'));
            $cover = trim((string)($_POST['cover_url'] ?? ''));
            if ($title === '' || $body === '') {
                throw new RuntimeException('标题和正文不能为空');
            }
            if (!in_array($style, ['normal', 'important', 'promo'], true)) {
                $style = 'normal';
            }
            if ($accent !== '' && !preg_match('/^#[0-9A-Fa-f]{6}$/', $accent)) {
                throw new RuntimeException('强调色请用 #RRGGBB，例如 #1ECAD3');
            }
            if (isset($_FILES['cover_file']) && (int)($_FILES['cover_file']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_NO_FILE) {
                if ((int)$_FILES['cover_file']['error'] !== UPLOAD_ERR_OK) {
                    throw new RuntimeException('封面：' . huihuoUploadErrorMessage((int)$_FILES['cover_file']['error']));
                }
                $cover = huihuoSaveAsset($root, 'notify_cover', $_FILES['cover_file']);
            }
            $st = $pdo->prepare(
                "INSERT INTO `{$tNotify}`
                (`title`,`body`,`link`,`tag`,`subtitle`,`cover_url`,`accent`,`style`,`status`,`created_at`)
                VALUES (?,?,?,?,?,?,?,?,1,?)"
            );
            $st->execute([$title, $body, $link, $tag, $subtitle, $cover, $accent, $style, time()]);
            huihuoRefreshNotifyJson($pdo, $tNotify, $root);
            $msg = '通知已发布';
            $tab = 'notify';
        } elseif ($action === 'notify_del') {
            $id = (int)($_POST['id'] ?? 0);
            $pdo->prepare("DELETE FROM `{$tNotify}` WHERE `id`=?")->execute([$id]);
            huihuoRefreshNotifyJson($pdo, $tNotify, $root);
            $msg = '已删除通知';
            $tab = 'notify';
        } elseif ($action === 'update_save') {
            $platform = strtolower(trim((string)($_POST['platform'] ?? 'android')));
            if ($platform !== 'ios') {
                $platform = 'android';
            }
            $ver = trim((string)($_POST['version'] ?? ''));
            $code = (int)($_POST['version_code'] ?? 0);
            $url = trim((string)($_POST['download_url'] ?? $_POST['apk_url'] ?? ''));
            $log = trim((string)($_POST['changelog'] ?? ''));
            $force = !empty($_POST['force_update']) ? 1 : 0;
            $appName = trim((string)($_POST['app_name'] ?? ''));
            $iconUrl = trim((string)($_POST['icon_url'] ?? ''));
            $bgUrl = trim((string)($_POST['bg_url'] ?? ''));
            $websiteUrl = trim((string)($_POST['website_url'] ?? ''));
            if ($ver === '' || $code <= 0) {
                throw new RuntimeException('版本号 / versionCode 必填');
            }

            $stOld = $pdo->prepare(
                "SELECT * FROM `{$tUpdate}` WHERE `platform`=? ORDER BY `id` DESC LIMIT 1"
            );
            $stOld->execute([$platform]);
            $old = $stOld->fetch() ?: [];

            // 上传安装包
            $hasFileField = isset($_FILES['pkg']) && is_array($_FILES['pkg']);
            $fileErr = $hasFileField ? (int)($_FILES['pkg']['error'] ?? UPLOAD_ERR_NO_FILE) : UPLOAD_ERR_NO_FILE;
            if ($hasFileField && $fileErr !== UPLOAD_ERR_NO_FILE) {
                if ($fileErr !== UPLOAD_ERR_OK) {
                    throw new RuntimeException(huihuoUploadErrorMessage($fileErr));
                }
                $url = huihuoSavePackage($root, $platform, $code, $_FILES['pkg']);
            }
            if ($url === '') {
                $url = trim((string)($old['download_url'] ?? ''));
                if ($url === '') {
                    $url = trim((string)($old['apk_url'] ?? ''));
                }
            }
            if ($url === '') {
                $ini = ini_get('upload_max_filesize') ?: '?';
                $post = ini_get('post_max_size') ?: '?';
                throw new RuntimeException(
                    "请填写下载地址，或重新选择安装包上传（当前 PHP upload_max_filesize={$ini}，post_max_size={$post}；包过大时会被静默丢弃）"
                );
            }

            // 图标 / 背景图上传或沿用
            if (isset($_FILES['icon_file']) && (int)($_FILES['icon_file']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_NO_FILE) {
                if ((int)$_FILES['icon_file']['error'] !== UPLOAD_ERR_OK) {
                    throw new RuntimeException('图标：' . huihuoUploadErrorMessage((int)$_FILES['icon_file']['error']));
                }
                $iconUrl = huihuoSaveAsset($root, 'icon_' . $platform, $_FILES['icon_file']);
            } elseif ($iconUrl === '') {
                $iconUrl = trim((string)($old['icon_url'] ?? ''));
            }
            if (isset($_FILES['bg_file']) && (int)($_FILES['bg_file']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_NO_FILE) {
                if ((int)$_FILES['bg_file']['error'] !== UPLOAD_ERR_OK) {
                    throw new RuntimeException('背景图：' . huihuoUploadErrorMessage((int)$_FILES['bg_file']['error']));
                }
                $bgUrl = huihuoSaveAsset($root, 'bg_' . $platform, $_FILES['bg_file']);
            } elseif ($bgUrl === '') {
                $bgUrl = trim((string)($old['bg_url'] ?? ''));
            }
            if ($appName === '') {
                $appName = trim((string)($old['app_name'] ?? ''));
            }
            if ($appName === '') {
                $appName = '灰火';
            }
            if ($websiteUrl === '') {
                $websiteUrl = trim((string)($old['website_url'] ?? ''));
            }

            $pdo->prepare("DELETE FROM `{$tUpdate}` WHERE `platform`=?")->execute([$platform]);
            $st = $pdo->prepare(
                "INSERT INTO `{$tUpdate}`
                (`platform`,`version`,`version_code`,`apk_url`,`download_url`,`changelog`,`force_update`,
                 `app_name`,`icon_url`,`bg_url`,`website_url`,`updated_at`)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)"
            );
            $st->execute([
                $platform, $ver, $code, $url, $url, $log, $force,
                $appName, $iconUrl, $bgUrl, $websiteUrl, time(),
            ]);

            huihuoWriteAppUpdateJson($root, $platform, [
                'platform' => $platform,
                'version' => $ver,
                'version_code' => $code,
                'apk_url' => $url,
                'download_url' => $url,
                'changelog' => $log,
                'force_update' => (bool)$force,
                'app_name' => $appName,
                'icon_url' => $iconUrl,
                'bg_url' => $bgUrl,
                'website_url' => $websiteUrl,
                'updated_at' => time(),
            ]);
            // 归档到更新日志（官网展示）
            $pdo->prepare(
                "INSERT INTO `{$tChangelog}`
                (`platform`,`version`,`version_code`,`download_url`,`changelog`,`app_name`,`created_at`)
                VALUES (?,?,?,?,?,?,?)"
            )->execute([$platform, $ver, $code, $url, $log, $appName, time()]);
            $msg = strtoupper($platform) . ' 更新配置已保存';
            if ($hasFileField && $fileErr === UPLOAD_ERR_OK) {
                $msg .= ' · 安装包已上传';
            }
            $tab = 'update';
        } elseif ($action === 'config_save') {
            $json = trim((string)($_POST['config_json'] ?? ''));
            if ($json === '') {
                throw new RuntimeException('配置不能为空');
            }
            $decoded = json_decode($json, true);
            if (!is_array($decoded)) {
                throw new RuntimeException('JSON 格式无效');
            }
            $pretty = json_encode($decoded, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
            huihuoKvSet($pdo, $tConfig, 'app_config', $pretty);
            $dir = $root . '/static/app';
            if (!is_dir($dir)) {
                @mkdir($dir, 0755, true);
            }
            file_put_contents($dir . '/app_config.json', $pretty);
            $msg = '远程配置已保存并写入 /static/app/app_config.json';
            $tab = 'config';
        } elseif ($action === 'qq_login_save') {
            $json = huihuoKvGet($pdo, $tConfig, 'app_config');
            if ($json === null || $json === '') {
                $example = $root . '/static/app/app_config.json';
                $json = is_file($example) ? (string)file_get_contents($example) : '{}';
            }
            $decoded = json_decode((string)$json, true);
            if (!is_array($decoded)) {
                $decoded = [];
            }
            $enabled = isset($_POST['qq_enabled']) && (string)$_POST['qq_enabled'] === '1';
            $appId = trim((string)($_POST['qq_app_id'] ?? ''));
            $appKey = trim((string)($_POST['qq_app_key'] ?? ''));
            $ulink = trim((string)($_POST['qq_universal_link'] ?? ''));
            $decoded['qq_login'] = [
                'enabled' => $enabled,
                'app_id' => $appId,
                'app_key' => $appKey,
                'universal_link' => $ulink,
            ];
            $pretty = json_encode($decoded, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
            huihuoKvSet($pdo, $tConfig, 'app_config', $pretty);
            $dir = $root . '/static/app';
            if (!is_dir($dir)) {
                @mkdir($dir, 0755, true);
            }
            file_put_contents($dir . '/app_config.json', $pretty);
            $msg = 'QQ 登录参数已保存（app_config.qq_login）';
            $tab = 'config';
        } elseif ($action === 'log_clear') {
            $pdo->exec("TRUNCATE TABLE `{$tLog}`");
            $msg = '更新记录已清空';
            $tab = 'logs';
        } elseif ($action === 'redeem_add') {
            $code = strtoupper(trim((string)($_POST['code'] ?? '')));
            $rtype = trim((string)($_POST['reward_type'] ?? 'points'));
            $rval = (int)($_POST['reward_value'] ?? 0);
            $note = trim((string)($_POST['note'] ?? ''));
            if ($code === '' || !preg_match('/^[A-Z0-9_-]{4,32}$/', $code)) {
                throw new RuntimeException('兑换码 4–32 位，仅字母数字_-');
            }
            if (!in_array($rtype, ['points', 'vip_days'], true)) {
                $rtype = 'points';
            }
            if ($rval <= 0) {
                throw new RuntimeException('奖励数值须大于 0');
            }
            $st = $pdo->prepare(
                "INSERT INTO `{$tRedeem}` (`code`,`reward_type`,`reward_value`,`note`,`status`,`created_at`)
                 VALUES (?,?,?,?,1,?)"
            );
            try {
                $st->execute([$code, $rtype, $rval, $note, time()]);
            } catch (Throwable $e) {
                throw new RuntimeException('兑换码已存在或写入失败');
            }
            $msg = '兑换码已添加：' . $code;
            $tab = 'redeem';
        } elseif ($action === 'redeem_del') {
            $id = (int)($_POST['id'] ?? 0);
            $pdo->prepare("DELETE FROM `{$tRedeem}` WHERE `id`=?")->execute([$id]);
            $msg = '已删除兑换码';
            $tab = 'redeem';
        }
    } catch (Throwable $e) {
        $err = $e->getMessage();
        if ($action === 'update_save') {
            $tab = 'update';
        }
    }
}

$notifies = $pdo->query("SELECT * FROM `{$tNotify}` ORDER BY `id` DESC LIMIT 100")->fetchAll();
$updateAndroid = $pdo->query("SELECT * FROM `{$tUpdate}` WHERE `platform`='android' ORDER BY `id` DESC LIMIT 1")->fetch();
$updateIos = $pdo->query("SELECT * FROM `{$tUpdate}` WHERE `platform`='ios' ORDER BY `id` DESC LIMIT 1")->fetch();
// 兼容旧数据（无 platform）
if (!$updateAndroid) {
    $legacy = $pdo->query("SELECT * FROM `{$tUpdate}` ORDER BY `id` DESC LIMIT 1")->fetch();
    if ($legacy) {
        $updateAndroid = $legacy;
    }
}
$configJson = huihuoKvGet($pdo, $tConfig, 'app_config');
if ($configJson === null || $configJson === '') {
    $example = $root . '/static/app/app_config.json';
    if (is_file($example)) {
        $configJson = (string)file_get_contents($example);
    } else {
        $configJson = "{\n  \"tabs\": [],\n  \"nav\": [],\n  \"live_m3u_url\": \"\",\n  \"qq_login\": {\n    \"enabled\": false,\n    \"app_id\": \"\",\n    \"app_key\": \"\",\n    \"universal_link\": \"\"\n  }\n}\n";
    }
}
$qqCfg = ['enabled' => false, 'app_id' => '', 'app_key' => '', 'universal_link' => ''];
$cfgArr = json_decode((string)$configJson, true);
if (is_array($cfgArr) && isset($cfgArr['qq_login']) && is_array($cfgArr['qq_login'])) {
    $q = $cfgArr['qq_login'];
    $qqCfg['enabled'] = !empty($q['enabled']);
    $qqCfg['app_id'] = (string)($q['app_id'] ?? '');
    $qqCfg['app_key'] = (string)($q['app_key'] ?? '');
    $qqCfg['universal_link'] = (string)($q['universal_link'] ?? '');
}
$logs = $pdo->query(
    "SELECT * FROM `{$tLog}` ORDER BY `id` DESC LIMIT 200"
)->fetchAll();

$vodCount = 0;
$artCount = 0;
$userCount = 0;
try {
    $vodCount = (int)$pdo->query("SELECT COUNT(*) FROM `{$prefix}vod`")->fetchColumn();
    $artCount = (int)$pdo->query("SELECT COUNT(*) FROM `{$prefix}art`")->fetchColumn();
    $userCount = (int)$pdo->query("SELECT COUNT(*) FROM `{$prefix}user`")->fetchColumn();
} catch (Throwable $e) {
}

$self = htmlspecialchars($_SERVER['PHP_SELF'] ?? 'huihuo_panel.php', ENT_QUOTES, 'UTF-8');
$baseApi = $self . '?api=';
$siteBase = huihuoPublicBase();

?><!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>灰火扩展控制台</title>
<style>
:root{--brand:#1ECAD3;--ink:#1a1a1a;--muted:#6b7280;--line:#e5e7eb;--bg:#f5f7f9;--card:#fff;}
*{box-sizing:border-box}
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:var(--bg);color:var(--ink)}
.wrap{max-width:980px;margin:0 auto;padding:20px 16px 48px}
h1{font-size:22px;margin:0 0 6px}
.sub{color:var(--muted);font-size:13px;margin-bottom:18px}
.stats{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:16px}
.stat{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px 16px;min-width:120px}
.stat b{display:block;font-size:20px;color:var(--brand)}
.stat span{font-size:12px;color:var(--muted)}
.tabs{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px}
.tabs a{text-decoration:none;color:var(--ink);background:#fff;border:1px solid var(--line);padding:8px 14px;border-radius:999px;font-size:13px;font-weight:600}
.tabs a.on{background:var(--brand);border-color:var(--brand);color:#fff}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;margin-bottom:14px}
label{display:block;font-size:13px;font-weight:600;margin:10px 0 6px}
input[type=text],input[type=number],input[type=file],textarea,select{width:100%;padding:10px 12px;border:1px solid var(--line);border-radius:10px;font-size:14px}
textarea{min-height:110px;font-family:ui-monospace,Consolas,monospace}
.row{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-top:12px}
button,.btn{appearance:none;border:0;background:var(--brand);color:#fff;font-weight:700;padding:10px 16px;border-radius:999px;cursor:pointer;font-size:14px}
button.ghost{background:#eef1f4;color:var(--ink)}
.ok{background:#ecfdf5;color:#047857;border:1px solid #a7f3d0;padding:10px 12px;border-radius:10px;margin-bottom:12px}
.err{background:#fef2f2;color:#b91c1c;border:1px solid #fecaca;padding:10px 12px;border-radius:10px;margin-bottom:12px}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{border-bottom:1px solid var(--line);padding:10px 6px;text-align:left;vertical-align:top}
.muted{color:var(--muted);font-size:12px}
code{background:#f3f4f6;padding:2px 6px;border-radius:6px;font-size:12px}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:14px}
@media(max-width:800px){.grid2{grid-template-columns:1fr}}
.tip{background:#f0fdfa;border:1px solid #99f6e4;border-radius:10px;padding:10px 12px;font-size:12px;color:#0f766e;margin-bottom:12px}
</style>
</head>
<body>
<div class="wrap">
  <h1>灰火扩展控制台</h1>
  <div class="sub">通知 · Android/iOS 双端更新 · 安装包上传 · 更新记录 · 远程配置</div>

  <div class="stats">
    <div class="stat"><b><?= (int)$vodCount ?></b><span>影视</span></div>
    <div class="stat"><b><?= (int)$artCount ?></b><span>文章</span></div>
    <div class="stat"><b><?= (int)$userCount ?></b><span>会员</span></div>
    <div class="stat"><b><?= count($notifies) ?></b><span>通知</span></div>
    <div class="stat"><b><?= count($logs) ?></b><span>更新记录(近200)</span></div>
  </div>

  <?php if ($msg !== ''): ?><div class="ok"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
  <?php if ($err !== ''): ?><div class="err"><?= htmlspecialchars($err) ?></div><?php endif; ?>

  <div class="tabs">
    <a class="<?= $tab === 'notify' ? 'on' : '' ?>" href="<?= $self ?>?key=<?= urlencode(HUIHUO_PANEL_KEY) ?>&tab=notify">发通知</a>
    <a class="<?= $tab === 'update' ? 'on' : '' ?>" href="<?= $self ?>?key=<?= urlencode(HUIHUO_PANEL_KEY) ?>&tab=update">双端更新</a>
    <a class="<?= $tab === 'redeem' ? 'on' : '' ?>" href="<?= $self ?>?key=<?= urlencode(HUIHUO_PANEL_KEY) ?>&tab=redeem">兑换码</a>
    <a class="<?= $tab === 'logs' ? 'on' : '' ?>" href="<?= $self ?>?key=<?= urlencode(HUIHUO_PANEL_KEY) ?>&tab=logs">更新记录</a>
    <a class="<?= $tab === 'config' ? 'on' : '' ?>" href="<?= $self ?>?key=<?= urlencode(HUIHUO_PANEL_KEY) ?>&tab=config">远程配置</a>
    <a class="<?= $tab === 'api' ? 'on' : '' ?>" href="<?= $self ?>?key=<?= urlencode(HUIHUO_PANEL_KEY) ?>&tab=api">接口说明</a>
  </div>

<?php if ($tab === 'notify'): ?>
  <div class="card">
    <form method="post" enctype="multipart/form-data">
      <input type="hidden" name="key" value="<?= htmlspecialchars(HUIHUO_PANEL_KEY) ?>"/>
      <input type="hidden" name="action" value="notify_add"/>
      <label>标题</label>
      <input type="text" name="title" placeholder="例如：系统维护通知" required/>
      <label>副标题（可选，列表副文案）</label>
      <input type="text" name="subtitle" placeholder="例如：今晚 23:00 起短暂维护"/>
      <label>正文</label>
      <textarea name="body" placeholder="通知内容…" required></textarea>
      <label>标签（可选，如：公告 / 活动 / 福利）</label>
      <input type="text" name="tag" placeholder="公告"/>
      <label>样式</label>
      <select name="style">
        <option value="normal">普通</option>
        <option value="important">重要（左侧强调条）</option>
        <option value="promo">活动（标签高亮）</option>
      </select>
      <label>强调色（可选，#RRGGBB，默认品牌青）</label>
      <input type="text" name="accent" placeholder="#1ECAD3"/>
      <label>封面图 URL（或下方上传，可选）</label>
      <input type="text" name="cover_url" placeholder="https://…/cover.jpg"/>
      <input type="file" name="cover_file" accept="image/png,image/jpeg,image/webp,.png,.jpg,.jpeg,.webp"/>
      <label>可选跳转（App 内链或 https）</label>
      <input type="text" name="link" placeholder="vod:123 或 https://…"/>
      <div class="row"><button type="submit">发布通知</button></div>
    </form>
  </div>
  <div class="card">
    <table>
      <thead><tr><th>ID</th><th>标题</th><th>标签/样式</th><th>时间</th><th></th></tr></thead>
      <tbody>
      <?php foreach ($notifies as $n): ?>
        <tr>
          <td><?= (int)$n['id'] ?></td>
          <td>
            <div><?= htmlspecialchars((string)$n['title']) ?></div>
            <?php if (!empty($n['subtitle'])): ?>
              <div class="muted"><?= htmlspecialchars((string)$n['subtitle']) ?></div>
            <?php endif; ?>
            <div class="muted"><?= htmlspecialchars(mb_strimwidth((string)$n['body'], 0, 60, '…', 'UTF-8')) ?></div>
          </td>
          <td class="muted">
            <?= htmlspecialchars((string)($n['tag'] ?? '')) ?>
            · <?= htmlspecialchars((string)($n['style'] ?? 'normal')) ?>
          </td>
          <td class="muted"><?= date('Y-m-d H:i', (int)$n['created_at']) ?></td>
          <td>
            <form method="post" onsubmit="return confirm('删除这条通知？')">
              <input type="hidden" name="key" value="<?= htmlspecialchars(HUIHUO_PANEL_KEY) ?>"/>
              <input type="hidden" name="action" value="notify_del"/>
              <input type="hidden" name="id" value="<?= (int)$n['id'] ?>"/>
              <button class="ghost" type="submit">删除</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
      <?php if (!$notifies): ?><tr><td colspan="5" class="muted">暂无通知</td></tr><?php endif; ?>
      </tbody>
    </table>
  </div>

<?php elseif ($tab === 'update'): ?>
  <div class="tip">
    <b>双端说明：</b>Android / iOS 各自独立配置 versionCode。<br/>
    App 本地 <code>ApiConfig.appVersionCode</code> 小于服务器 versionCode 才算有新版本。<br/>
    <b>强制更新</b>勾选后：用户打开 App 才会弹窗；不勾选则仅「设置→检查更新」可见。<br/>
    iOS 一般填 App Store / TestFlight / 企业签 OTA 地址；也可上传 .ipa 托管到本站。<br/>
    App 内 iOS 更新弹窗支持：官网下载、下载 IPA 后分享到第三方签名工具、复制/打开直链。<br/>
    每次保存会写入「更新日志」，官网 <code>?api=website</code> 可拉取双端安装包与日志列表。<br/>
    <b>上传限制：</b>当前 PHP <code>upload_max_filesize=<?= htmlspecialchars((string)ini_get('upload_max_filesize')) ?></code>，
    <code>post_max_size=<?= htmlspecialchars((string)ini_get('post_max_size')) ?></code>。
    APK 超过此大小会被丢弃——请在宝塔/php.ini 调大（建议 ≥100M），并同步调大 Nginx <code>client_max_body_size</code>。
  </div>
  <div class="grid2">
    <?php
    foreach ([
        'android' => ['title' => 'Android（APK）', 'row' => $updateAndroid, 'accept' => '.apk,application/vnd.android.package-archive'],
        'ios' => ['title' => 'iOS（IPA / Store）', 'row' => $updateIos, 'accept' => '.ipa,application/octet-stream'],
    ] as $plat => $meta):
        $row = $meta['row'] ?: [];
    ?>
    <div class="card">
      <h3 style="margin:0 0 8px;font-size:16px"><?= htmlspecialchars($meta['title']) ?></h3>
      <form method="post" enctype="multipart/form-data">
        <input type="hidden" name="key" value="<?= htmlspecialchars(HUIHUO_PANEL_KEY) ?>"/>
        <input type="hidden" name="action" value="update_save"/>
        <input type="hidden" name="platform" value="<?= htmlspecialchars($plat) ?>"/>
        <label>应用名称（弹窗标题）</label>
        <input type="text" name="app_name" value="<?= htmlspecialchars((string)($row['app_name'] ?? '灰火')) ?>" placeholder="例如：灰火 / 哇TV"/>
        <label>图标 URL（或下方上传）</label>
        <input type="text" name="icon_url" value="<?= htmlspecialchars((string)($row['icon_url'] ?? '')) ?>" placeholder="https://…/icon.png"/>
        <input type="file" name="icon_file" accept="image/png,image/jpeg,image/webp,.png,.jpg,.jpeg,.webp"/>
        <?php if (!empty($row['icon_url'])): ?>
          <p class="muted">当前图标：<code><?= htmlspecialchars((string)$row['icon_url']) ?></code></p>
        <?php endif; ?>
        <label>背景图 URL（或下方上传）</label>
        <input type="text" name="bg_url" value="<?= htmlspecialchars((string)($row['bg_url'] ?? '')) ?>" placeholder="https://…/cover.jpg"/>
        <input type="file" name="bg_file" accept="image/png,image/jpeg,image/webp,.png,.jpg,.jpeg,.webp"/>
        <?php if (!empty($row['bg_url'])): ?>
          <p class="muted">当前背景：<code><?= htmlspecialchars((string)$row['bg_url']) ?></code></p>
        <?php endif; ?>
        <label>版本名 version</label>
        <input type="text" name="version" value="<?= htmlspecialchars((string)($row['version'] ?? '1.0.0')) ?>" required/>
        <label>versionCode（整数，必须大于 App 当前值才会提示）</label>
        <input type="number" name="version_code" value="<?= (int)($row['version_code'] ?? 2) ?>" required min="1"/>
        <label>下载地址（可手填，或下方上传后自动填）</label>
        <input type="text" name="download_url" value="<?= htmlspecialchars((string)($row['download_url'] ?? $row['apk_url'] ?? '')) ?>" placeholder="https://…"/>
        <label>官网下载页（可选，App「官网下载」按钮）</label>
        <input type="text" name="website_url" value="<?= htmlspecialchars((string)($row['website_url'] ?? '')) ?>" placeholder="https://www.watv.fun"/>
        <label>上传安装包（可选）</label>
        <input type="file" name="pkg" accept="<?= htmlspecialchars($meta['accept']) ?>"/>
        <label>更新说明</label>
        <textarea name="changelog"><?= htmlspecialchars((string)($row['changelog'] ?? '')) ?></textarea>
        <label><input type="checkbox" name="force_update" value="1" <?= !empty($row['force_update']) ? 'checked' : '' ?>/> 强制更新（启动即弹窗）</label>
        <div class="row"><button type="submit">保存 <?= strtoupper($plat) ?> 配置</button></div>
      </form>
      <?php if (!empty($row['download_url']) || !empty($row['apk_url'])): ?>
        <p class="muted">当前包：<code><?= htmlspecialchars((string)($row['download_url'] ?? $row['apk_url'])) ?></code></p>
      <?php endif; ?>
    </div>
    <?php endforeach; ?>
  </div>
  <p class="muted">安装包保存目录：<code><?= htmlspecialchars($siteBase) ?>/static/app/releases/</code>（请保证 PHP 可写）</p>

<?php elseif ($tab === 'redeem'): ?>
<?php
  $redeems = $pdo->query("SELECT * FROM `{$tRedeem}` ORDER BY `id` DESC LIMIT 200")->fetchAll();
?>
  <div class="card">
    <h2>新增兑换码</h2>
    <p class="muted">App「兑福利」调用 <code>?api=redeem</code>。奖励写入会员积分或会员到期时间。</p>
    <form method="post">
      <input type="hidden" name="action" value="redeem_add"/>
      <div class="row">
        <label>兑换码</label>
        <input type="text" name="code" placeholder="例如 HH2026VIP7" required/>
      </div>
      <div class="row">
        <label>奖励类型</label>
        <select name="reward_type">
          <option value="points">积分</option>
          <option value="vip_days">会员天数</option>
        </select>
      </div>
      <div class="row">
        <label>奖励数值</label>
        <input type="number" name="reward_value" min="1" value="100" required/>
      </div>
      <div class="row">
        <label>备注</label>
        <input type="text" name="note" placeholder="可选"/>
      </div>
      <div class="row"><button type="submit">添加</button></div>
    </form>
  </div>
  <div class="card">
    <h2>兑换码列表</h2>
    <table>
      <tr><th>码</th><th>奖励</th><th>状态</th><th>使用者</th><th></th></tr>
      <?php foreach ($redeems as $r): ?>
        <tr>
          <td><code><?= htmlspecialchars((string)$r['code']) ?></code></td>
          <td><?= htmlspecialchars((string)$r['reward_type']) ?> × <?= (int)$r['reward_value'] ?></td>
          <td><?= ((int)$r['status'] === 1 && (int)$r['used_by'] === 0) ? '可用' : '已用' ?></td>
          <td class="muted"><?= htmlspecialchars((string)($r['used_name'] ?: '-')) ?></td>
          <td>
            <form method="post" onsubmit="return confirm('删除该兑换码？')">
              <input type="hidden" name="action" value="redeem_del"/>
              <input type="hidden" name="id" value="<?= (int)$r['id'] ?>"/>
              <button type="submit">删除</button>
            </form>
          </td>
        </tr>
      <?php endforeach; ?>
      <?php if (!$redeems): ?><tr><td colspan="5" class="muted">暂无兑换码</td></tr><?php endif; ?>
    </table>
  </div>

<?php elseif ($tab === 'logs'): ?>
  <div class="card">
    <form method="post" onsubmit="return confirm('清空全部更新记录？')" style="margin-bottom:12px">
      <input type="hidden" name="key" value="<?= htmlspecialchars(HUIHUO_PANEL_KEY) ?>"/>
      <input type="hidden" name="action" value="log_clear"/>
      <button class="ghost" type="submit">清空记录</button>
    </form>
    <table>
      <thead>
        <tr>
          <th>时间</th><th>端</th><th>用户</th><th>设备</th><th>版本</th><th>IP</th>
        </tr>
      </thead>
      <tbody>
      <?php foreach ($logs as $L): ?>
        <tr>
          <td class="muted"><?= date('m-d H:i', (int)$L['reported_at']) ?></td>
          <td><?= htmlspecialchars((string)$L['platform']) ?></td>
          <td>
            <?php if ((int)$L['user_id'] > 0): ?>
              #<?= (int)$L['user_id'] ?> <?= htmlspecialchars((string)$L['user_name']) ?>
            <?php else: ?>
              <span class="muted">游客</span>
            <?php endif; ?>
          </td>
          <td class="muted"><?= htmlspecialchars(mb_strimwidth((string)$L['device_id'], 0, 18, '…', 'UTF-8')) ?></td>
          <td>
            <?= htmlspecialchars((string)$L['from_version']) ?>(<?= (int)$L['from_code'] ?>)
            →
            <b><?= htmlspecialchars((string)$L['to_version']) ?>(<?= (int)$L['to_code'] ?>)</b>
          </td>
          <td class="muted"><?= htmlspecialchars((string)$L['ip']) ?></td>
        </tr>
      <?php endforeach; ?>
      <?php if (!$logs): ?><tr><td colspan="6" class="muted">暂无记录（用户点「复制下载链接」或升到新版本后会上报）</td></tr><?php endif; ?>
      </tbody>
    </table>
  </div>

<?php elseif ($tab === 'config'): ?>
  <div class="card">
    <h3 style="margin:0 0 12px">QQ 互联登录（审核通过后填这里）</h3>
    <form method="post">
      <input type="hidden" name="key" value="<?= htmlspecialchars(HUIHUO_PANEL_KEY) ?>"/>
      <input type="hidden" name="action" value="qq_login_save"/>
      <label><input type="checkbox" name="qq_enabled" value="1" <?= !empty($qqCfg['enabled']) ? 'checked' : '' ?>/> 启用 QQ 登录</label>
      <label>QQ AppID</label>
      <input type="text" name="qq_app_id" value="<?= htmlspecialchars((string)$qqCfg['app_id']) ?>" placeholder="审核通过后填写 APP ID"/>
      <label>QQ AppKey</label>
      <input type="text" name="qq_app_key" value="<?= htmlspecialchars((string)$qqCfg['app_key']) ?>" placeholder="审核通过后填写 APP Key"/>
      <label>iOS Universal Link（可选）</label>
      <input type="text" name="qq_universal_link" value="<?= htmlspecialchars((string)$qqCfg['universal_link']) ?>" placeholder="https://your.domain/qq_conn/"/>
      <div class="row"><button type="submit">保存 QQ 参数</button></div>
      <p class="muted">写入 app_config.json 的 <code>qq_login</code>。App 用 tencent_kit 拉起 QQ 授权后，调面板 <code>?api=qq_oauth</code> 写入 CMS Cookie。请保证本面板已上传到站点根目录。</p>
    </form>
  </div>
  <div class="card">
    <form method="post">
      <input type="hidden" name="key" value="<?= htmlspecialchars(HUIHUO_PANEL_KEY) ?>"/>
      <input type="hidden" name="action" value="config_save"/>
      <label>app_config.json（完整 JSON）</label>
      <textarea name="config_json" style="min-height:320px"><?= htmlspecialchars($configJson) ?></textarea>
      <div class="row"><button type="submit">保存远程配置</button></div>
    </form>
  </div>

<?php else: ?>
  <div class="card">
    <p><b>App 接口</b>（公开）：</p>
    <ul>
      <li><code><?= htmlspecialchars($baseApi) ?>notify_list</code></li>
      <li><code><?= htmlspecialchars($baseApi) ?>comment_list&amp;rid=影片ID</code>（按影片过滤，修主题 ajax 串台）</li>
      <li><code><?= htmlspecialchars($baseApi) ?>app_update&amp;platform=android</code></li>
      <li><code><?= htmlspecialchars($baseApi) ?>app_update&amp;platform=ios</code></li>
      <li><code><?= htmlspecialchars($baseApi) ?>website</code>（官网安装包 + 更新日志）</li>
      <li><code><?= htmlspecialchars($baseApi) ?>app_config</code></li>
      <li><code><?= htmlspecialchars($baseApi) ?>update_report</code>（POST JSON）</li>
    </ul>
    <p class="muted">表：<?= htmlspecialchars($tNotify) ?> / <?= htmlspecialchars($tUpdate) ?> / <?= htmlspecialchars($tLog) ?> / <?= htmlspecialchars($tConfig) ?></p>
  </div>
<?php endif; ?>
</div>
</body>
</html>
<?php

function huihuoPublicBase(): string
{
    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || ((string)($_SERVER['SERVER_PORT'] ?? '') === '443')
        || (strtolower((string)($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https');
    $host = (string)($_SERVER['HTTP_HOST'] ?? 'localhost');
    return ($https ? 'https' : 'http') . '://' . $host;
}

function huihuoUploadErrorMessage(int $err): string
{
    $ini = ini_get('upload_max_filesize') ?: '?';
    $post = ini_get('post_max_size') ?: '?';
    switch ($err) {
        case UPLOAD_ERR_INI_SIZE:
        case UPLOAD_ERR_FORM_SIZE:
            return "安装包超过服务器限制（upload_max_filesize={$ini}，post_max_size={$post}）。请在宝塔调大 PHP/Nginx 限制后重试，或改用手填下载地址。";
        case UPLOAD_ERR_PARTIAL:
            return '安装包只上传了一部分，请重试';
        case UPLOAD_ERR_NO_FILE:
            return '未收到安装包文件';
        case UPLOAD_ERR_NO_TMP_DIR:
            return '服务器临时目录不可用';
        case UPLOAD_ERR_CANT_WRITE:
            return '服务器磁盘无法写入临时文件';
        case UPLOAD_ERR_EXTENSION:
            return '上传被 PHP 扩展拦截';
        default:
            return "安装包上传失败（错误码 {$err}）";
    }
}

function huihuoSaveAsset(string $root, string $prefix, array $file): string
{
    $name = (string)($file['name'] ?? '');
    $tmp = (string)($file['tmp_name'] ?? '');
    $err = (int)($file['error'] ?? UPLOAD_ERR_NO_FILE);
    if ($err !== UPLOAD_ERR_OK) {
        throw new RuntimeException(huihuoUploadErrorMessage($err));
    }
    if ($tmp === '' || !is_file($tmp)) {
        throw new RuntimeException('图片临时文件丢失');
    }
    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
    if (!in_array($ext, ['png', 'jpg', 'jpeg', 'webp', 'gif'], true)) {
        $finfo = function_exists('finfo_open') ? finfo_open(FILEINFO_MIME_TYPE) : false;
        $mime = $finfo ? (string)finfo_file($finfo, $tmp) : '';
        if ($finfo) {
            finfo_close($finfo);
        }
        if (strpos($mime, 'png') !== false) {
            $ext = 'png';
        } elseif (strpos($mime, 'jpeg') !== false || strpos($mime, 'jpg') !== false) {
            $ext = 'jpg';
        } elseif (strpos($mime, 'webp') !== false) {
            $ext = 'webp';
        } else {
            throw new RuntimeException('图片仅支持 png / jpg / webp');
        }
    }
    $dir = $root . '/static/app/brand';
    if (!is_dir($dir) && !@mkdir($dir, 0755, true)) {
        throw new RuntimeException('无法创建目录 static/app/brand');
    }
    if (!is_writable($dir)) {
        throw new RuntimeException('目录 static/app/brand 不可写');
    }
    $safe = 'huihuo_' . preg_replace('/[^a-z0-9_]+/i', '', $prefix) . '_' . time() . '.' . $ext;
    $dest = $dir . '/' . $safe;
    $ok = is_uploaded_file($tmp) ? @move_uploaded_file($tmp, $dest) : false;
    if (!$ok) {
        $ok = @rename($tmp, $dest) || @copy($tmp, $dest);
        if ($ok && is_file($tmp)) {
            @unlink($tmp);
        }
    }
    if (!$ok || !is_file($dest)) {
        throw new RuntimeException('保存图片失败');
    }
    @chmod($dest, 0644);
    return huihuoPublicBase() . '/static/app/brand/' . $safe;
}

function huihuoSavePackage(string $root, string $platform, int $code, array $file): string
{
    $name = (string)($file['name'] ?? '');
    $tmp = (string)($file['tmp_name'] ?? '');
    $err = (int)($file['error'] ?? UPLOAD_ERR_NO_FILE);
    if ($err !== UPLOAD_ERR_OK) {
        throw new RuntimeException(huihuoUploadErrorMessage($err));
    }
    if ($tmp === '' || !is_file($tmp)) {
        throw new RuntimeException('上传临时文件丢失，请重试或检查 post_max_size');
    }
    // 部分环境 is_uploaded_file 异常，优先信任 UPLOAD_ERR_OK + 可读临时文件
    if (!is_uploaded_file($tmp) && !is_readable($tmp)) {
        throw new RuntimeException('安装包临时文件不可读');
    }

    $ext = strtolower(pathinfo($name, PATHINFO_EXTENSION));
    // 兼容中文名 / 无扩展名：按 MIME 兜底
    if ($ext === '' || strlen($ext) > 5) {
        $finfo = function_exists('finfo_open') ? finfo_open(FILEINFO_MIME_TYPE) : false;
        $mime = $finfo ? (string)finfo_file($finfo, $tmp) : '';
        if ($finfo) {
            finfo_close($finfo);
        }
        if (strpos($mime, 'android') !== false || $mime === 'application/zip' || $mime === 'application/java-archive') {
            $ext = $platform === 'ios' ? 'ipa' : 'apk';
        } elseif ($platform === 'ios') {
            $ext = 'ipa';
        } else {
            $ext = 'apk';
        }
    }
    if ($platform === 'ios') {
        if ($ext !== 'ipa' && $ext !== 'plist') {
            throw new RuntimeException('iOS 请上传 .ipa 或 .plist（当前：' . ($ext !== '' ? $ext : $name) . '）');
        }
    } else {
        if ($ext !== 'apk') {
            throw new RuntimeException('Android 请上传 .apk（当前文件：' . $name . '）');
        }
    }
    $dir = $root . '/static/app/releases';
    if (!is_dir($dir) && !@mkdir($dir, 0755, true)) {
        throw new RuntimeException('无法创建目录 static/app/releases，请检查权限（chmod 755 或归属 www）');
    }
    if (!is_writable($dir)) {
        throw new RuntimeException('目录 static/app/releases 不可写，请 chmod 或改归属为运行 PHP 的用户');
    }
    $safe = 'huihuo_' . $platform . '_v' . $code . '_' . time() . '.' . $ext;
    $dest = $dir . '/' . $safe;
    $ok = false;
    if (is_uploaded_file($tmp)) {
        $ok = @move_uploaded_file($tmp, $dest);
    }
    if (!$ok) {
        $ok = @rename($tmp, $dest) || @copy($tmp, $dest);
        if ($ok && is_file($tmp)) {
            @unlink($tmp);
        }
    }
    if (!$ok || !is_file($dest)) {
        throw new RuntimeException('保存安装包失败，请检查磁盘空间与目录权限');
    }
    @chmod($dest, 0644);
    return huihuoPublicBase() . '/static/app/releases/' . $safe;
}

function huihuoEnsureTables(
    PDO $pdo,
    string $tNotify,
    string $tUpdate,
    string $tConfig,
    string $tLog,
    string $tRedeem = '',
    string $tChangelog = ''
): void {
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS `{$tNotify}` (
          `id` int unsigned NOT NULL AUTO_INCREMENT,
          `title` varchar(200) NOT NULL DEFAULT '',
          `body` text NOT NULL,
          `link` varchar(500) NOT NULL DEFAULT '',
          `tag` varchar(40) NOT NULL DEFAULT '',
          `subtitle` varchar(200) NOT NULL DEFAULT '',
          `cover_url` varchar(500) NOT NULL DEFAULT '',
          `accent` varchar(16) NOT NULL DEFAULT '',
          `style` varchar(20) NOT NULL DEFAULT 'normal',
          `status` tinyint NOT NULL DEFAULT 1,
          `created_at` int unsigned NOT NULL DEFAULT 0,
          PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS `{$tUpdate}` (
          `id` int unsigned NOT NULL AUTO_INCREMENT,
          `platform` varchar(16) NOT NULL DEFAULT 'android',
          `version` varchar(32) NOT NULL DEFAULT '',
          `version_code` int NOT NULL DEFAULT 0,
          `apk_url` varchar(500) NOT NULL DEFAULT '',
          `download_url` varchar(500) NOT NULL DEFAULT '',
          `changelog` text NOT NULL,
          `force_update` tinyint NOT NULL DEFAULT 0,
          `app_name` varchar(80) NOT NULL DEFAULT '',
          `icon_url` varchar(500) NOT NULL DEFAULT '',
          `bg_url` varchar(500) NOT NULL DEFAULT '',
          `website_url` varchar(500) NOT NULL DEFAULT '',
          `updated_at` int unsigned NOT NULL DEFAULT 0,
          PRIMARY KEY (`id`),
          KEY `idx_platform` (`platform`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
    // 旧表补列
    huihuoEnsureColumn($pdo, $tNotify, 'tag', "varchar(40) NOT NULL DEFAULT ''");
    huihuoEnsureColumn($pdo, $tNotify, 'subtitle', "varchar(200) NOT NULL DEFAULT ''");
    huihuoEnsureColumn($pdo, $tNotify, 'cover_url', "varchar(500) NOT NULL DEFAULT ''");
    huihuoEnsureColumn($pdo, $tNotify, 'accent', "varchar(16) NOT NULL DEFAULT ''");
    huihuoEnsureColumn($pdo, $tNotify, 'style', "varchar(20) NOT NULL DEFAULT 'normal'");
    huihuoEnsureColumn($pdo, $tUpdate, 'platform', "varchar(16) NOT NULL DEFAULT 'android'");
    huihuoEnsureColumn($pdo, $tUpdate, 'download_url', "varchar(500) NOT NULL DEFAULT ''");
    huihuoEnsureColumn($pdo, $tUpdate, 'app_name', "varchar(80) NOT NULL DEFAULT ''");
    huihuoEnsureColumn($pdo, $tUpdate, 'icon_url', "varchar(500) NOT NULL DEFAULT ''");
    huihuoEnsureColumn($pdo, $tUpdate, 'bg_url', "varchar(500) NOT NULL DEFAULT ''");
    huihuoEnsureColumn($pdo, $tUpdate, 'website_url', "varchar(500) NOT NULL DEFAULT ''");

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS `{$tConfig}` (
          `k` varchar(64) NOT NULL,
          `v` mediumtext NOT NULL,
          `updated_at` int unsigned NOT NULL DEFAULT 0,
          PRIMARY KEY (`k`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS `{$tLog}` (
          `id` int unsigned NOT NULL AUTO_INCREMENT,
          `platform` varchar(16) NOT NULL DEFAULT 'android',
          `user_id` int NOT NULL DEFAULT 0,
          `user_name` varchar(100) NOT NULL DEFAULT '',
          `device_id` varchar(80) NOT NULL DEFAULT '',
          `from_version` varchar(32) NOT NULL DEFAULT '',
          `from_code` int NOT NULL DEFAULT 0,
          `to_version` varchar(32) NOT NULL DEFAULT '',
          `to_code` int NOT NULL DEFAULT 0,
          `ip` varchar(64) NOT NULL DEFAULT '',
          `ua` varchar(255) NOT NULL DEFAULT '',
          `reported_at` int unsigned NOT NULL DEFAULT 0,
          PRIMARY KEY (`id`),
          KEY `idx_device_code` (`device_id`,`to_code`),
          KEY `idx_time` (`reported_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
    if ($tRedeem !== '') {
        $pdo->exec(
            "CREATE TABLE IF NOT EXISTS `{$tRedeem}` (
              `id` int unsigned NOT NULL AUTO_INCREMENT,
              `code` varchar(32) NOT NULL DEFAULT '',
              `reward_type` varchar(16) NOT NULL DEFAULT 'points',
              `reward_value` int NOT NULL DEFAULT 0,
              `note` varchar(200) NOT NULL DEFAULT '',
              `status` tinyint NOT NULL DEFAULT 1,
              `used_by` int NOT NULL DEFAULT 0,
              `used_name` varchar(100) NOT NULL DEFAULT '',
              `used_at` int unsigned NOT NULL DEFAULT 0,
              `created_at` int unsigned NOT NULL DEFAULT 0,
              PRIMARY KEY (`id`),
              UNIQUE KEY `uk_code` (`code`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
        );
    }
    if ($tChangelog !== '') {
        $pdo->exec(
            "CREATE TABLE IF NOT EXISTS `{$tChangelog}` (
              `id` int unsigned NOT NULL AUTO_INCREMENT,
              `platform` varchar(16) NOT NULL DEFAULT 'android',
              `version` varchar(32) NOT NULL DEFAULT '',
              `version_code` int NOT NULL DEFAULT 0,
              `download_url` varchar(500) NOT NULL DEFAULT '',
              `changelog` text NOT NULL,
              `app_name` varchar(80) NOT NULL DEFAULT '',
              `created_at` int unsigned NOT NULL DEFAULT 0,
              PRIMARY KEY (`id`),
              KEY `idx_time` (`created_at`),
              KEY `idx_platform` (`platform`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
        );
    }
}

function huihuoEnsureColumn(PDO $pdo, string $table, string $column, string $ddl): void
{
    try {
        $st = $pdo->query("SHOW COLUMNS FROM `{$table}` LIKE " . $pdo->quote($column));
        if ($st && $st->fetch()) {
            return;
        }
        $pdo->exec("ALTER TABLE `{$table}` ADD COLUMN `{$column}` {$ddl}");
    } catch (Throwable $e) {
        // ignore
    }
}

function huihuoEnsureCheckinTable(PDO $pdo, string $table): void
{
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS `{$table}` (
          `user_id` int unsigned NOT NULL,
          `last_day` int unsigned NOT NULL DEFAULT 0,
          `streak` int unsigned NOT NULL DEFAULT 0,
          `total` int unsigned NOT NULL DEFAULT 0,
          `updated_at` int unsigned NOT NULL DEFAULT 0,
          PRIMARY KEY (`user_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
}

/** 简易 HTTP GET（QQ 互联校验） */
function huihuoHttpGet(string $url, int $timeout = 12): string
{
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_CONNECTTIMEOUT => $timeout,
            CURLOPT_TIMEOUT => $timeout,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_SSL_VERIFYHOST => false,
            CURLOPT_USERAGENT => 'HuihuoPanel/1.0',
        ]);
        $body = curl_exec($ch);
        curl_close($ch);
        return is_string($body) ? $body : '';
    }
    $ctx = stream_context_create([
        'http' => ['timeout' => $timeout, 'ignore_errors' => true],
        'ssl' => ['verify_peer' => false, 'verify_peer_name' => false],
    ]);
    $body = @file_get_contents($url, false, $ctx);
    return is_string($body) ? $body : '';
}

/** 从 app_config 读取 QQ 互联参数 */
function huihuoQqLoginConfig(PDO $pdo, string $tConfig, string $root): array
{
    $out = ['enabled' => false, 'app_id' => '', 'app_key' => '', 'universal_link' => ''];
    $json = huihuoKvGet($pdo, $tConfig, 'app_config');
    if ($json === null || $json === '') {
        $file = $root . '/static/app/app_config.json';
        if (is_file($file)) {
            $json = (string)file_get_contents($file);
        }
    }
    if ($json === null || $json === '') {
        return $out;
    }
    $decoded = json_decode($json, true);
    if (!is_array($decoded) || !isset($decoded['qq_login']) || !is_array($decoded['qq_login'])) {
        return $out;
    }
    $q = $decoded['qq_login'];
    $out['app_id'] = trim((string)($q['app_id'] ?? ''));
    $out['app_key'] = trim((string)($q['app_key'] ?? ''));
    $out['universal_link'] = trim((string)($q['universal_link'] ?? ''));
    $enabledFlag = !empty($q['enabled']);
    $out['enabled'] = $enabledFlag || ($out['app_id'] !== '' && $out['app_key'] !== '');
    return $out;
}

/** 校验 QQ access_token 并拉简单资料 */
function huihuoQqVerifyToken(string $appId, string $accessToken, string $openid): array
{
    $meUrl = 'https://graph.qq.com/oauth2.0/me?access_token=' . rawurlencode($accessToken);
    $meRaw = huihuoHttpGet($meUrl);
    // callback( {"client_id":"...","openid":"..."} );
    if (!preg_match('/\{.*\}/s', $meRaw, $m)) {
        throw new RuntimeException('QQ token 校验失败');
    }
    $me = json_decode($m[0], true);
    if (!is_array($me)) {
        throw new RuntimeException('QQ token 校验失败');
    }
    if (!empty($me['error'])) {
        throw new RuntimeException((string)($me['error_description'] ?? $me['error']));
    }
    $gotOpen = trim((string)($me['openid'] ?? ''));
    $gotCid = trim((string)($me['client_id'] ?? ''));
    if ($gotOpen === '' || strcasecmp($gotOpen, $openid) !== 0) {
        throw new RuntimeException('QQ openid 不匹配');
    }
    if ($appId !== '' && $gotCid !== '' && strcasecmp($gotCid, $appId) !== 0) {
        throw new RuntimeException('QQ AppID 不匹配');
    }

    $nick = '';
    $portrait = '';
    $infoUrl = 'https://graph.qq.com/user/get_simple_userinfo?access_token='
        . rawurlencode($accessToken)
        . '&oauth_consumer_key=' . rawurlencode($appId)
        . '&openid=' . rawurlencode($openid)
        . '&format=json';
    $infoRaw = huihuoHttpGet($infoUrl);
    $info = json_decode($infoRaw, true);
    if (is_array($info) && (int)($info['ret'] ?? -1) === 0) {
        $nick = trim((string)($info['nickname'] ?? ''));
        $portrait = trim((string)($info['figureurl_qq_2'] ?? $info['figureurl_qq_1'] ?? $info['figureurl_2'] ?? ''));
    }
    return ['openid' => $gotOpen, 'nickname' => $nick, 'portrait' => $portrait];
}

/** 生成 MacCMS 会员 Cookie 串（与站内登录一致） */
function huihuoMacUserCookieHeader(array $u): string
{
    $uid = (int)($u['user_id'] ?? 0);
    $name = (string)($u['user_name'] ?? '');
    $pwd = (string)($u['user_pwd'] ?? '');
    $gid = (int)($u['group_id'] ?? 2);
    $gname = (string)($u['group_name'] ?? '注册会员');
    $portrait = (string)($u['user_portrait'] ?? '');
    $random = md5(uniqid((string)mt_rand(), true));
    $check = md5($uid . $name . $pwd . $random);
    $parts = [
        'user_id=' . $uid,
        'user_name=' . rawurlencode($name),
        'group_id=' . $gid,
        'group_name=' . rawurlencode($gname),
        'user_check=' . $check,
        'user_random=' . $random,
    ];
    if ($portrait !== '') {
        $parts[] = 'user_portrait=' . rawurlencode($portrait);
    }
    return implode('; ', $parts);
}

/** QQ 授权 → 查找/创建 mac_user → Cookie */
function huihuoQqOauthLogin(PDO $pdo, string $prefix, string $tConfig, string $root, array $body): array
{
    $cfg = huihuoQqLoginConfig($pdo, $tConfig, $root);
    if ($cfg['app_id'] === '' || $cfg['app_key'] === '') {
        throw new RuntimeException('后台未配置 QQ AppID / AppKey');
    }
    $openid = trim((string)($body['openid'] ?? ''));
    $token = trim((string)($body['access_token'] ?? $body['accessToken'] ?? ''));
    $nickHint = trim((string)($body['nickname'] ?? ''));
    if ($openid === '' || $token === '') {
        throw new RuntimeException('缺少 openid / access_token');
    }

    $profile = huihuoQqVerifyToken($cfg['app_id'], $token, $openid);
    $nick = $profile['nickname'] !== '' ? $profile['nickname'] : $nickHint;
    if ($nick === '') {
        $nick = 'QQ用户' . substr(md5($openid), 0, 6);
    }
    $portrait = (string)$profile['portrait'];

    $tUser = $prefix . 'user';
    $tGroup = $prefix . 'group';

    // 用 user_qq 存 openid（兼容无独立 openid 字段的站点）
    $st = $pdo->prepare("SELECT * FROM `{$tUser}` WHERE `user_qq`=? LIMIT 1");
    $st->execute([$openid]);
    $row = $st->fetch(PDO::FETCH_ASSOC);

    $now = time();
    $ip = (string)($_SERVER['REMOTE_ADDR'] ?? '');

    if (!$row) {
        $uname = 'qq_' . substr(md5($openid), 0, 12);
        // 撞名则追加后缀
        $try = $uname;
        for ($i = 0; $i < 8; $i++) {
            $chk = $pdo->prepare("SELECT `user_id` FROM `{$tUser}` WHERE `user_name`=? LIMIT 1");
            $chk->execute([$try]);
            if (!$chk->fetchColumn()) {
                $uname = $try;
                break;
            }
            $try = $uname . substr(md5($openid . $i), 0, 4);
        }
        $pwd = md5(uniqid('qq', true));
        $gid = 2;
        try {
            $g = $pdo->query("SELECT `group_id` FROM `{$tGroup}` WHERE `group_status`=1 AND `group_id`>1 ORDER BY `group_id` ASC LIMIT 1");
            if ($g) {
                $found = (int)$g->fetchColumn();
                if ($found > 0) {
                    $gid = $found;
                }
            }
        } catch (Throwable $e) {
            // ignore
        }

        $cols = ['user_name', 'user_pwd', 'user_nick_name', 'user_qq', 'group_id', 'user_status', 'user_reg_time', 'user_reg_ip', 'user_login_time', 'user_login_ip', 'user_login_num', 'user_points'];
        $vals = [$uname, $pwd, $nick, $openid, $gid, 1, $now, $ip, $now, $ip, 1, 0];
        // 可选头像字段
        try {
            $hasPortrait = $pdo->query("SHOW COLUMNS FROM `{$tUser}` LIKE 'user_portrait'");
            if ($hasPortrait && $hasPortrait->fetch() && $portrait !== '') {
                $cols[] = 'user_portrait';
                $vals[] = $portrait;
            }
        } catch (Throwable $e) {
            // ignore
        }
        $ph = implode(',', array_fill(0, count($cols), '?'));
        $pdo->prepare(
            'INSERT INTO `' . $tUser . '` (`' . implode('`,`', $cols) . '`) VALUES (' . $ph . ')'
        )->execute($vals);
        $uid = (int)$pdo->lastInsertId();
        $st = $pdo->prepare("SELECT * FROM `{$tUser}` WHERE `user_id`=? LIMIT 1");
        $st->execute([$uid]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            throw new RuntimeException('创建用户失败');
        }
    } else {
        $uid = (int)$row['user_id'];
        $sets = ['user_login_time=?', 'user_login_ip=?', 'user_login_num=`user_login_num`+1'];
        $args = [$now, $ip];
        if ($nick !== '') {
            $sets[] = 'user_nick_name=?';
            $args[] = $nick;
        }
        try {
            $hasPortrait = $pdo->query("SHOW COLUMNS FROM `{$tUser}` LIKE 'user_portrait'");
            if ($hasPortrait && $hasPortrait->fetch() && $portrait !== '') {
                $sets[] = 'user_portrait=?';
                $args[] = $portrait;
            }
        } catch (Throwable $e) {
            // ignore
        }
        $args[] = $uid;
        $pdo->prepare(
            'UPDATE `' . $tUser . '` SET ' . implode(',', $sets) . ' WHERE `user_id`=?'
        )->execute($args);
        $st = $pdo->prepare("SELECT * FROM `{$tUser}` WHERE `user_id`=? LIMIT 1");
        $st->execute([$uid]);
        $row = $st->fetch(PDO::FETCH_ASSOC) ?: $row;
    }

    $gname = '注册会员';
    try {
        $gs = $pdo->prepare("SELECT `group_name` FROM `{$tGroup}` WHERE `group_id`=? LIMIT 1");
        $gs->execute([(int)($row['group_id'] ?? 2)]);
        $gn = (string)($gs->fetchColumn() ?: '');
        if ($gn !== '') {
            $gname = $gn;
        }
    } catch (Throwable $e) {
        // ignore
    }
    $row['group_name'] = $gname;
    if ($portrait !== '' && empty($row['user_portrait'])) {
        $row['user_portrait'] = $portrait;
    }

    $cookie = huihuoMacUserCookieHeader($row);
    return [
        'cookie' => $cookie,
        'user_id' => (int)$row['user_id'],
        'user_name' => (string)$row['user_name'],
        'nick_name' => (string)($row['user_nick_name'] ?? $nick),
        'portrait' => (string)($row['user_portrait'] ?? $portrait),
        'group_id' => (int)($row['group_id'] ?? 2),
        'group_name' => $gname,
    ];
}

function huihuoKvGet(PDO $pdo, string $table, string $k): ?string
{
    $st = $pdo->prepare("SELECT `v` FROM `{$table}` WHERE `k`=? LIMIT 1");
    $st->execute([$k]);
    $row = $st->fetch();
    return $row ? (string)$row['v'] : null;
}

function huihuoKvSet(PDO $pdo, string $table, string $k, string $v): void
{
    $st = $pdo->prepare(
        "INSERT INTO `{$table}` (`k`,`v`,`updated_at`) VALUES (?,?,?)
         ON DUPLICATE KEY UPDATE `v`=VALUES(`v`), `updated_at`=VALUES(`updated_at`)"
    );
    $st->execute([$k, $v, time()]);
}

function huihuoRefreshNotifyJson(PDO $pdo, string $tNotify, string $root): void
{
    $rows = $pdo->query(
        "SELECT `id`,`title`,`body`,`link`,`tag`,`subtitle`,`cover_url`,`accent`,`style`,`created_at`
         FROM `{$tNotify}` WHERE `status`=1 ORDER BY `id` DESC LIMIT 50"
    )->fetchAll();
    huihuoWriteNotifyJson($root, $rows);
}

function huihuoWriteNotifyJson(string $root, array $rows): void
{
    $dir = $root . '/static/app';
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    file_put_contents(
        $dir . '/notify_list.json',
        json_encode(['code' => 1, 'list' => $rows], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)
    );
}

function huihuoWriteAppUpdateJson(string $root, string $platform, array $data): void
{
    $dir = $root . '/static/app';
    if (!is_dir($dir)) {
        @mkdir($dir, 0755, true);
    }
    $file = $dir . '/app_update_' . $platform . '.json';
    file_put_contents($file, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
    // 兼容旧路径：android 再写一份 app_update.json
    if ($platform === 'android') {
        file_put_contents(
            $dir . '/app_update.json',
            json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)
        );
    }
}

/**
 * H5 / 跨域：把 provide 接口经本面板转发（面板已带 CORS）。
 * ?api=cms_proxy&target=vod|art|website&ac=list&pg=1...
 */
function huihuoServeCmsProxy(): void
{
    $target = strtolower(trim((string)($_GET['target'] ?? 'vod')));
    $map = [
        'vod' => 'vod',
        'art' => 'art',
        'website' => 'website',
    ];
    if (!isset($map[$target])) {
        http_response_code(400);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['code' => 0, 'msg' => 'bad target'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    $q = $_GET;
    unset($q['api'], $q['target']);
    $qs = http_build_query($q);

    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || ((string)($_SERVER['SERVER_PORT'] ?? '') === '443')
        || (strtolower((string)($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https');
    $scheme = $https ? 'https' : 'http';
    $host = (string)($_SERVER['HTTP_HOST'] ?? '127.0.0.1');
    $url = $scheme . '://' . $host . '/api.php/provide/' . $map[$target] . '/';
    if ($qs !== '') {
        $url .= '?' . $qs;
    }

    $ctx = stream_context_create([
        'http' => [
            'timeout' => 20,
            'header' => "Accept: application/json\r\nUser-Agent: HuiHuoCmsProxy/1.0\r\n",
            'ignore_errors' => true,
        ],
        'ssl' => [
            'verify_peer' => false,
            'verify_peer_name' => false,
        ],
    ]);
    $body = @file_get_contents($url, false, $ctx);
    if ($body === false || $body === '') {
        http_response_code(502);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['code' => 0, 'msg' => 'cms_proxy failed'], JSON_UNESCAPED_UNICODE);
        exit;
    }
    header('Content-Type: application/json; charset=utf-8');
    echo $body;
    exit;
}

/**
 * 封面图反代：客户端直连部分采集站 CDN（如 pic.yayazy.info）会被重置时，
 * 经本站拉取并短时缓存后下发。
 */
function huihuoServeImgProxy(string $root): void
{
    $raw = isset($_GET['u']) ? trim((string)$_GET['u']) : '';
    if ($raw === '' || strlen($raw) > 1500) {
        http_response_code(400);
        header('Content-Type: text/plain; charset=utf-8');
        echo 'bad url';
        return;
    }
    $url = $raw;
    if (strpos($url, 'http://') !== 0 && strpos($url, 'https://') !== 0) {
        http_response_code(400);
        header('Content-Type: text/plain; charset=utf-8');
        echo 'only http(s)';
        return;
    }
    $parts = parse_url($url);
    $host = strtolower((string)($parts['host'] ?? ''));
    if ($host === '' || $host === 'localhost' || $host === '127.0.0.1'
        || strpos($host, '10.') === 0
        || strpos($host, '192.168.') === 0
        || preg_match('/^172\.(1[6-9]|2\d|3[0-1])\./', $host)) {
        http_response_code(403);
        header('Content-Type: text/plain; charset=utf-8');
        echo 'host blocked';
        return;
    }

    $cacheDir = $root . '/static/app/img_cache';
    if (!is_dir($cacheDir)) {
        @mkdir($cacheDir, 0755, true);
    }
    $key = md5($url);
    $metaFile = $cacheDir . '/' . $key . '.json';
    $binFile = $cacheDir . '/' . $key . '.bin';
    $ttl = 86400 * 7;

    if (is_file($binFile) && is_file($metaFile) && (time() - filemtime($binFile) < $ttl)) {
        $meta = json_decode((string)file_get_contents($metaFile), true);
        $ctype = is_array($meta) ? (string)($meta['ctype'] ?? 'image/jpeg') : 'image/jpeg';
        header('Content-Type: ' . $ctype);
        header('Cache-Control: public, max-age=86400');
        header('X-Huihuo-Img-Cache: hit');
        readfile($binFile);
        return;
    }

    $data = null;
    $ctype = 'image/jpeg';
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_MAXREDIRS => 4,
            CURLOPT_CONNECTTIMEOUT => 8,
            CURLOPT_TIMEOUT => 18,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_SSL_VERIFYHOST => 0,
            CURLOPT_USERAGENT => 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
            CURLOPT_HTTPHEADER => [
                'Accept: image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
                'Referer: https://' . $host . '/',
            ],
        ]);
        $body = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $ct = (string)curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
        curl_close($ch);
        if ($body !== false && $code >= 200 && $code < 300 && strlen($body) > 32) {
            $data = $body;
            if ($ct !== '' && stripos($ct, 'image/') === 0) {
                $ctype = explode(';', $ct)[0];
            }
        }
    }
    if ($data === null) {
        $ctx = stream_context_create([
            'http' => [
                'timeout' => 18,
                'header' => "User-Agent: Mozilla/5.0\r\nAccept: image/*\r\nReferer: https://{$host}/\r\n",
            ],
            'ssl' => [
                'verify_peer' => false,
                'verify_peer_name' => false,
            ],
        ]);
        $body = @file_get_contents($url, false, $ctx);
        if ($body !== false && strlen($body) > 32) {
            $data = $body;
        }
    }
    if ($data === null) {
        http_response_code(502);
        header('Content-Type: text/plain; charset=utf-8');
        echo 'fetch failed';
        return;
    }

    @file_put_contents($binFile, $data);
    @file_put_contents($metaFile, json_encode(['ctype' => $ctype, 'src' => $url], JSON_UNESCAPED_UNICODE));
    header('Content-Type: ' . $ctype);
    header('Cache-Control: public, max-age=86400');
    header('X-Huihuo-Img-Cache: miss');
    echo $data;
}

function huihuoHandleApi(
    PDO $pdo,
    string $api,
    string $tNotify,
    string $tUpdate,
    string $tConfig,
    string $tLog,
    string $tRedeem,
    string $root,
    string $prefix,
    string $tChangelog = ''
): void {
    header('Content-Type: application/json; charset=utf-8');
    try {
        if ($api === 'website') {
            $pack = static function (PDO $pdo, string $tUpdate, string $platform) use ($root): ?array {
                $st = $pdo->prepare(
                    "SELECT * FROM `{$tUpdate}` WHERE `platform`=? ORDER BY `id` DESC LIMIT 1"
                );
                $st->execute([$platform]);
                $row = $st->fetch();
                if (!$row) {
                    return null;
                }
                $url = (string)($row['download_url'] ?? '');
                if ($url === '') {
                    $url = (string)($row['apk_url'] ?? '');
                }
                return [
                    'platform' => $platform,
                    'version' => (string)$row['version'],
                    'version_code' => (int)$row['version_code'],
                    'download_url' => $url,
                    'changelog' => (string)$row['changelog'],
                    'force_update' => (int)$row['force_update'] === 1,
                    'app_name' => (string)($row['app_name'] ?? ''),
                    'icon_url' => (string)($row['icon_url'] ?? ''),
                    'website_url' => (string)($row['website_url'] ?? ''),
                    'updated_at' => (int)$row['updated_at'],
                ];
            };
            $android = $pack($pdo, $tUpdate, 'android');
            $ios = $pack($pdo, $tUpdate, 'ios');
            $logs = [];
            if ($tChangelog !== '') {
                try {
                    $logs = $pdo->query(
                        "SELECT `id`,`platform`,`version`,`version_code`,`download_url`,`changelog`,`app_name`,`created_at`
                         FROM `{$tChangelog}` ORDER BY `id` DESC LIMIT 40"
                    )->fetchAll();
                } catch (Throwable $e) {
                    $logs = [];
                }
            }
            // 若尚无归档，用当前双端配置拼一份日志
            if (!$logs) {
                foreach ([$android, $ios] as $row) {
                    if (!$row) {
                        continue;
                    }
                    $logs[] = [
                        'id' => 0,
                        'platform' => $row['platform'],
                        'version' => $row['version'],
                        'version_code' => $row['version_code'],
                        'download_url' => $row['download_url'],
                        'changelog' => $row['changelog'],
                        'app_name' => $row['app_name'],
                        'created_at' => $row['updated_at'],
                    ];
                }
            }
            echo json_encode([
                'code' => 1,
                'data' => [
                    'android' => $android,
                    'ios' => $ios,
                    'changelogs' => $logs,
                ],
            ], JSON_UNESCAPED_UNICODE);
            return;
        }
        if ($api === 'notify_list') {
            $rows = $pdo->query(
                "SELECT `id`,`title`,`body`,`link`,`tag`,`subtitle`,`cover_url`,`accent`,`style`,`created_at`
                 FROM `{$tNotify}` WHERE `status`=1 ORDER BY `id` DESC LIMIT 50"
            )->fetchAll();
            huihuoWriteNotifyJson($root, $rows);
            echo json_encode(['code' => 1, 'list' => $rows], JSON_UNESCAPED_UNICODE);
            return;
        }
        if ($api === 'comment_list') {
            // 按影片 ID 或片名（后台 link【片名】）过滤
            $dbCfg = macLoadDbConfig($root);
            $prefix = $dbCfg && !empty($dbCfg['prefix']) ? $dbCfg['prefix'] : 'mac_';
            $tComment = $prefix . 'comment';
            $tUser = $prefix . 'user';
            $tVod = $prefix . 'vod';
            $rid = (int)($_GET['rid'] ?? 0);
            $mid = (int)($_GET['mid'] ?? 1);
            $name = trim((string)($_GET['name'] ?? ''));
            $name = preg_replace('/[【】\[\]\s]+/u', '', $name) ?? $name;
            $page = max(1, (int)($_GET['page'] ?? 1));
            $limit = min(50, max(1, (int)($_GET['limit'] ?? 30)));
            $offset = ($page - 1) * $limit;
            if ($rid <= 0 && $name === '') {
                echo json_encode(['code' => 0, 'msg' => 'rid or name required', 'list' => []], JSON_UNESCAPED_UNICODE);
                return;
            }

            // 片名 → 可能的 vod_id 列表（App 里的 id 常和评论表不一致）
            $nameIds = [];
            if ($name !== '') {
                $stFind = $pdo->prepare(
                    "SELECT `vod_id` FROM `{$tVod}`
                     WHERE REPLACE(REPLACE(REPLACE(`vod_name`,'【',''),'】',''),' ','') = ?
                        OR `vod_name` = ?
                        OR `vod_name` LIKE ?
                     ORDER BY `vod_id` DESC LIMIT 8"
                );
                $stFind->execute([$name, $name, '%' . $name . '%']);
                foreach ($stFind->fetchAll(PDO::FETCH_COLUMN) as $vid) {
                    $vid = (int)$vid;
                    if ($vid > 0) {
                        $nameIds[] = $vid;
                    }
                }
                if ($rid <= 0 && !empty($nameIds)) {
                    $rid = (int)$nameIds[0];
                }
            }

            $joinUser = "LEFT JOIN `{$tUser}` `u` ON (
                (`c`.`user_id` > 0 AND `u`.`user_id` = `c`.`user_id`)
                OR (
                    (`c`.`user_id` IS NULL OR `c`.`user_id` = 0)
                    AND (
                        `u`.`user_name` = `c`.`comment_name`
                        OR `u`.`user_nick_name` = `c`.`comment_name`
                    )
                )
            )";
            $joinVod = "LEFT JOIN `{$tVod}` `v` ON `v`.`vod_id` = `c`.`comment_rid`";
            $select = "`c`.`comment_id`,`c`.`comment_mid`,`c`.`comment_rid`,`c`.`comment_pid`,`c`.`user_id`,
                       `c`.`comment_name`,`c`.`comment_content`,`c`.`comment_time`,
                       `c`.`comment_up`,`c`.`comment_down`,`c`.`comment_reply`,
                       COALESCE(NULLIF(`v`.`vod_name`, ''), '') AS `vod_name`,
                       COALESCE(NULLIF(`u`.`user_portrait`, ''), '') AS `user_portrait`,
                       COALESCE(NULLIF(`u`.`user_qq`, ''), '') AS `user_qq`,
                       COALESCE(NULLIF(`u`.`user_nick_name`, ''), '') AS `user_nick_name`,
                       COALESCE(NULLIF(`u`.`user_name`, ''), '') AS `user_login`,
                       COALESCE(
                           NULLIF(`u`.`user_nick_name`, ''),
                           NULLIF(`u`.`user_name`, ''),
                           `c`.`comment_name`
                       ) AS `user_name`,
                       COALESCE(
                           NULLIF(`u`.`user_nick_name`, ''),
                           NULLIF(`u`.`user_name`, ''),
                           `c`.`comment_name`
                       ) AS `display_name`";

            $buildWhere = function (bool $withMid) use ($rid, $name, $nameIds, $mid) {
                $parts = [];
                $args = [];
                // 有精确 rid 时只按 rid 过滤，禁止 OR 片名导致串台
                if ($rid > 0) {
                    $parts[] = '`c`.`comment_rid`=?';
                    $args[] = $rid;
                } else {
                    foreach ($nameIds as $vid) {
                        $parts[] = '`c`.`comment_rid`=?';
                        $args[] = (int)$vid;
                    }
                    if ($name !== '') {
                        $parts[] = "(REPLACE(REPLACE(REPLACE(COALESCE(`v`.`vod_name`,''),'【',''),'】',''),' ','') = ? OR `v`.`vod_name` = ?)";
                        $args[] = $name;
                        $args[] = $name;
                    }
                }
                if (empty($parts)) {
                    return [null, []];
                }
                $where = '(' . implode(' OR ', $parts) . ')';
                if ($withMid && $mid > 0) {
                    $where .= ' AND `c`.`comment_mid`=?';
                    $args[] = $mid;
                }
                return [$where, $args];
            };

            [$where, $args] = $buildWhere(true);
            $rows = [];
            if ($where !== null) {
                $sql = "SELECT {$select}
                        FROM `{$tComment}` `c`
                        {$joinVod}
                        {$joinUser}
                        WHERE {$where}
                        ORDER BY `c`.`comment_id` DESC
                        LIMIT {$limit} OFFSET {$offset}";
                $st = $pdo->prepare($sql);
                $st->execute($args);
                $rows = $st->fetchAll(PDO::FETCH_ASSOC);
            }

            if (empty($rows) && $mid > 0) {
                [$where2, $args2] = $buildWhere(false);
                if ($where2 !== null) {
                    $st2 = $pdo->prepare(
                        "SELECT {$select}
                         FROM `{$tComment}` `c`
                         {$joinVod}
                         {$joinUser}
                         WHERE {$where2}
                         ORDER BY `c`.`comment_id` DESC
                         LIMIT {$limit} OFFSET {$offset}"
                    );
                    $st2->execute($args2);
                    $rows = $st2->fetchAll(PDO::FETCH_ASSOC);
                    $mid = 0;
                }
            }

            foreach ($rows as &$row) {
                $portrait = trim((string)($row['user_portrait'] ?? ''));
                $low = strtolower($portrait);
                $isPlaceholder = $portrait === ''
                    || strpos($low, 'duface') !== false
                    || strpos($low, 'touxiang.png') !== false
                    || strpos($low, 'nopic') !== false
                    || strpos($low, 'noavatar') !== false
                    || strpos($low, 'default_avatar') !== false
                    || strpos($low, 'default-avatar') !== false;
                if ($isPlaceholder) {
                    $row['user_portrait'] = '';
                    $row['avatar'] = '';
                } else {
                    if (str_starts_with($portrait, '//')) {
                        $portrait = 'https:' . $portrait;
                    } elseif ($portrait !== '' && !preg_match('#^https?://#i', $portrait)) {
                        $portrait = rtrim(huihuoPublicBase(), '/') . '/' . ltrim($portrait, '/');
                    }
                    $row['user_portrait'] = $portrait;
                    $row['avatar'] = $portrait;
                }
            }
            unset($row);

            echo json_encode([
                'code' => 1,
                'rid' => $rid,
                'name' => $name,
                'mid' => $mid,
                'page' => $page,
                'total' => count($rows),
                'list' => $rows,
            ], JSON_UNESCAPED_UNICODE);
            return;
        }
        if ($api === 'comment_mine') {
            try {
            $dbCfg = macLoadDbConfig($root);
            $prefix = $dbCfg && !empty($dbCfg['prefix']) ? $dbCfg['prefix'] : 'mac_';
            $tComment = $prefix . 'comment';
            $tUser = $prefix . 'user';
            $tVod = $prefix . 'vod';
            $userId = (int)($_GET['user_id'] ?? $_POST['user_id'] ?? 0);
            $userName = trim((string)($_GET['user_name'] ?? $_POST['user_name'] ?? ''));
            $nickName = trim((string)($_GET['nick_name'] ?? $_POST['nick_name'] ?? ''));
            $aliases = [];
            if (isset($_GET['alias']) && is_array($_GET['alias'])) {
                foreach ($_GET['alias'] as $a) {
                    $a = trim((string)$a);
                    if ($a !== '') {
                        $aliases[] = $a;
                    }
                }
            } elseif (isset($_GET['alias']) && is_string($_GET['alias'])) {
                $a = trim((string)$_GET['alias']);
                if ($a !== '') {
                    $aliases[] = $a;
                }
            }
            $page = max(1, (int)($_GET['page'] ?? 1));
            $limit = min(50, max(1, (int)($_GET['limit'] ?? 30)));
            $offset = ($page - 1) * $limit;
            if ($userId <= 0 && $userName === '' && $nickName === '' && empty($aliases)) {
                echo json_encode(['code' => 0, 'msg' => 'user_id required', 'list' => []], JSON_UNESCAPED_UNICODE);
                return;
            }
            // 登录评论常有 user_id；游客/旧数据可能只有 comment_name（用户44556）
            $parts = [];
            $args = [];
            if ($userId > 0) {
                $parts[] = '`c`.`user_id`=?';
                $args[] = $userId;
                $aliases[] = (string)$userId;
                $aliases[] = '用户' . $userId;
            }
            $names = [];
            foreach (array_merge([$userName, $nickName], $aliases) as $n) {
                $n = trim((string)$n);
                if ($n !== '' && !in_array($n, $names, true)) {
                    $names[] = $n;
                }
            }
            foreach ($names as $n) {
                $parts[] = '`c`.`comment_name`=?';
                $args[] = $n;
            }
            // 按登录名/昵称反查会员 id（不依赖 user_qq 字段，避免旧库 500）
            if (!empty($names)) {
                try {
                    $in = implode(',', array_fill(0, count($names), '?'));
                    $stU = $pdo->prepare(
                        "SELECT `user_id` FROM `{$tUser}`
                         WHERE `user_name` IN ($in)
                            OR `user_nick_name` IN ($in)
                         LIMIT 20"
                    );
                    $stU->execute(array_merge($names, $names));
                    foreach ($stU->fetchAll(PDO::FETCH_COLUMN) as $uid) {
                        $uid = (int)$uid;
                        if ($uid > 0) {
                            $parts[] = '`c`.`user_id`=?';
                            $args[] = $uid;
                        }
                    }
                } catch (Throwable $e) {
                    // ignore
                }
            }
            if (empty($parts)) {
                echo json_encode(['code' => 1, 'user_id' => $userId, 'page' => $page, 'total' => 0, 'list' => []], JSON_UNESCAPED_UNICODE);
                return;
            }
            $where = '(' . implode(' OR ', $parts) . ')';
            $sql = "SELECT `c`.`comment_id`,`c`.`comment_mid`,`c`.`comment_rid`,`c`.`comment_pid`,`c`.`user_id`,
                           `c`.`comment_name`,`c`.`comment_content`,`c`.`comment_time`,
                           `c`.`comment_up`,`c`.`comment_down`,`c`.`comment_reply`,
                           COALESCE(NULLIF(`v`.`vod_name`, ''), '') AS `vod_name`,
                           COALESCE(NULLIF(`v`.`vod_pic`, ''), '') AS `vod_pic`,
                           COALESCE(NULLIF(`u`.`user_portrait`, ''), '') AS `user_portrait`,
                           COALESCE(NULLIF(`u`.`user_name`, ''), '') AS `user_login`,
                           COALESCE(
                               NULLIF(`u`.`user_nick_name`, ''),
                               NULLIF(`u`.`user_name`, ''),
                               `c`.`comment_name`
                           ) AS `display_name`,
                           COALESCE(
                               NULLIF(`u`.`user_nick_name`, ''),
                               NULLIF(`u`.`user_name`, ''),
                               `c`.`comment_name`
                           ) AS `user_name`
                    FROM `{$tComment}` `c`
                    LEFT JOIN `{$tVod}` `v` ON `v`.`vod_id` = `c`.`comment_rid`
                    LEFT JOIN `{$tUser}` `u` ON (
                        (`c`.`user_id` > 0 AND `u`.`user_id` = `c`.`user_id`)
                        OR (
                            (`c`.`user_id` IS NULL OR `c`.`user_id` = 0)
                            AND (
                                `u`.`user_name` = `c`.`comment_name`
                                OR `u`.`user_nick_name` = `c`.`comment_name`
                            )
                        )
                    )
                    WHERE {$where}
                    ORDER BY `c`.`comment_id` DESC
                    LIMIT {$limit} OFFSET {$offset}";
            $st = $pdo->prepare($sql);
            $st->execute($args);
            $rows = $st->fetchAll(PDO::FETCH_ASSOC);
            foreach ($rows as &$row) {
                $portrait = trim((string)($row['user_portrait'] ?? ''));
                $low = strtolower($portrait);
                $isPlaceholder = $portrait === ''
                    || strpos($low, 'duface') !== false
                    || strpos($low, 'touxiang.png') !== false
                    || strpos($low, 'nopic') !== false
                    || strpos($low, 'noavatar') !== false
                    || strpos($low, 'default_avatar') !== false;
                if ($isPlaceholder) {
                    $row['user_portrait'] = '';
                    $row['avatar'] = '';
                } else {
                    if (str_starts_with($portrait, '//')) {
                        $portrait = 'https:' . $portrait;
                    } elseif ($portrait !== '' && !preg_match('#^https?://#i', $portrait)) {
                        $portrait = rtrim(huihuoPublicBase(), '/') . '/' . ltrim($portrait, '/');
                    }
                    $row['user_portrait'] = $portrait;
                    $row['avatar'] = $portrait;
                }
                $pic = trim((string)($row['vod_pic'] ?? ''));
                if ($pic !== '' && !preg_match('#^https?://#i', $pic) && !str_starts_with($pic, '//')) {
                    $row['vod_pic'] = rtrim(huihuoPublicBase(), '/') . '/' . ltrim($pic, '/');
                } elseif (str_starts_with($pic, '//')) {
                    $row['vod_pic'] = 'https:' . $pic;
                }
            }
            unset($row);
            echo json_encode([
                'code' => 1,
                'user_id' => $userId,
                'page' => $page,
                'total' => count($rows),
                'list' => $rows,
            ], JSON_UNESCAPED_UNICODE);
            return;
            } catch (Throwable $e) {
                echo json_encode([
                    'code' => 0,
                    'msg' => 'comment_mine error: ' . $e->getMessage(),
                    'list' => [],
                ], JSON_UNESCAPED_UNICODE);
                return;
            }
        }
        if ($api === 'app_update') {
            $platform = strtolower(trim((string)($_GET['platform'] ?? 'android')));
            if ($platform !== 'ios') {
                $platform = 'android';
            }
            $st = $pdo->prepare(
                "SELECT * FROM `{$tUpdate}` WHERE `platform`=? ORDER BY `id` DESC LIMIT 1"
            );
            $st->execute([$platform]);
            $row = $st->fetch();
            if (!$row && $platform === 'android') {
                // 兼容旧单端数据
                $row = $pdo->query("SELECT * FROM `{$tUpdate}` ORDER BY `id` DESC LIMIT 1")->fetch();
            }
            if (!$row) {
                $file = $root . '/static/app/app_update_' . $platform . '.json';
                if (!is_file($file) && $platform === 'android') {
                    $file = $root . '/static/app/app_update.json';
                }
                if (is_file($file)) {
                    echo file_get_contents($file);
                    return;
                }
                echo json_encode(['code' => 1, 'data' => null], JSON_UNESCAPED_UNICODE);
                return;
            }
            $url = (string)($row['download_url'] ?? '');
            if ($url === '') {
                $url = (string)($row['apk_url'] ?? '');
            }
            echo json_encode([
                'code' => 1,
                'data' => [
                    'platform' => $platform,
                    'version' => $row['version'],
                    'version_code' => (int)$row['version_code'],
                    'apk_url' => $url,
                    'download_url' => $url,
                    'changelog' => $row['changelog'],
                    'force_update' => (int)$row['force_update'] === 1,
                    'app_name' => (string)($row['app_name'] ?? ''),
                    'icon_url' => (string)($row['icon_url'] ?? ''),
                    'bg_url' => (string)($row['bg_url'] ?? ''),
                    'website_url' => (string)($row['website_url'] ?? ''),
                    'updated_at' => (int)$row['updated_at'],
                ],
            ], JSON_UNESCAPED_UNICODE);
            return;
        }
        if ($api === 'app_config') {
            $json = huihuoKvGet($pdo, $tConfig, 'app_config');
            if ($json === null || $json === '') {
                $file = $root . '/static/app/app_config.json';
                if (is_file($file)) {
                    echo file_get_contents($file);
                    return;
                }
                echo json_encode(['code' => 1, 'data' => new stdClass()], JSON_UNESCAPED_UNICODE);
                return;
            }
            $decoded = json_decode($json, true);
            echo json_encode(['code' => 1, 'data' => $decoded], JSON_UNESCAPED_UNICODE);
            return;
        }
        if ($api === 'qq_oauth') {
            $raw = file_get_contents('php://input');
            $j = json_decode($raw ?: '[]', true);
            if (!is_array($j)) {
                $j = $_POST;
            }
            try {
                $data = huihuoQqOauthLogin($pdo, $prefix, $tConfig, $root, is_array($j) ? $j : []);
                echo json_encode([
                    'code' => 1,
                    'msg' => '登录成功',
                    'data' => $data,
                ], JSON_UNESCAPED_UNICODE);
            } catch (Throwable $e) {
                echo json_encode([
                    'code' => 0,
                    'msg' => $e->getMessage() !== '' ? $e->getMessage() : 'QQ 登录失败',
                ], JSON_UNESCAPED_UNICODE);
            }
            return;
        }
        if ($api === 'update_report') {
            $raw = file_get_contents('php://input');
            $j = json_decode($raw ?: '[]', true);
            if (!is_array($j)) {
                $j = $_POST;
            }
            $platform = strtolower(trim((string)($j['platform'] ?? 'android')));
            if ($platform !== 'ios') {
                $platform = 'android';
            }
            $deviceId = trim((string)($j['device_id'] ?? ''));
            $userId = (int)($j['user_id'] ?? 0);
            $userName = trim((string)($j['user_name'] ?? ''));
            $fromCode = (int)($j['from_code'] ?? 0);
            $toCode = (int)($j['to_code'] ?? 0);
            $fromVer = trim((string)($j['from_version'] ?? ''));
            $toVer = trim((string)($j['to_version'] ?? ''));
            if ($deviceId === '' || $toCode <= 0) {
                echo json_encode(['code' => 0, 'msg' => 'device_id / to_code required'], JSON_UNESCAPED_UNICODE);
                return;
            }
            $ip = (string)($_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? '');
            if (strpos($ip, ',') !== false) {
                $ip = trim(explode(',', $ip)[0]);
            }
            $ua = substr((string)($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 255);

            // 同设备同目标版本 24h 内只记一条
            $st = $pdo->prepare(
                "SELECT `id` FROM `{$tLog}` WHERE `device_id`=? AND `to_code`=? AND `platform`=? AND `reported_at`>? LIMIT 1"
            );
            $st->execute([$deviceId, $toCode, $platform, time() - 86400]);
            if ($st->fetch()) {
                echo json_encode(['code' => 1, 'msg' => 'already'], JSON_UNESCAPED_UNICODE);
                return;
            }
            $ins = $pdo->prepare(
                "INSERT INTO `{$tLog}`
                (`platform`,`user_id`,`user_name`,`device_id`,`from_version`,`from_code`,`to_version`,`to_code`,`ip`,`ua`,`reported_at`)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)"
            );
            $ins->execute([
                $platform, $userId, $userName, $deviceId,
                $fromVer, $fromCode, $toVer, $toCode,
                $ip, $ua, time(),
            ]);
            echo json_encode(['code' => 1, 'msg' => 'ok'], JSON_UNESCAPED_UNICODE);
            return;
        }
        if ($api === 'checkin' || $api === 'checkin_status') {
            $raw = file_get_contents('php://input');
            $body = [];
            if (is_string($raw) && $raw !== '') {
                $decoded = json_decode($raw, true);
                if (is_array($decoded)) {
                    $body = $decoded;
                }
            }
            $userId = (int)($body['user_id'] ?? $_GET['user_id'] ?? $_POST['user_id'] ?? 0);
            if ($userId <= 0) {
                echo json_encode(['code' => 0, 'msg' => '请先登录'], JSON_UNESCAPED_UNICODE);
                return;
            }
            $tUser = $prefix . 'user';
            $tCheckin = $prefix . 'huihuo_checkin';
            huihuoEnsureCheckinTable($pdo, $tCheckin);
            // 兼容签到插件字段
            huihuoEnsureColumn($pdo, $tUser, 'user_sign_time', 'int unsigned NOT NULL DEFAULT 0');

            $reward = (int)(huihuoKvGet($pdo, $tConfig, 'checkin_points') ?? '10');
            if ($reward <= 0) {
                $reward = 10;
            }
            $today = (int)date('Ymd');
            $yesterday = (int)date('Ymd', time() - 86400);

            $st = $pdo->prepare(
                "SELECT `last_day`,`streak`,`total` FROM `{$tCheckin}` WHERE `user_id`=? LIMIT 1"
            );
            $st->execute([$userId]);
            $row = $st->fetch(PDO::FETCH_ASSOC) ?: null;
            $lastDay = (int)($row['last_day'] ?? 0);
            $streak = (int)($row['streak'] ?? 0);
            $total = (int)($row['total'] ?? 0);
            $checkedToday = $lastDay === $today;

            // 若 checkin 表无记录，用 user_sign_time 兜底判断今日是否已签
            if (!$checkedToday && !$row) {
                $u = $pdo->prepare("SELECT `user_sign_time` FROM `{$tUser}` WHERE `user_id`=? LIMIT 1");
                $u->execute([$userId]);
                $signTs = (int)($u->fetchColumn() ?: 0);
                if ($signTs > 0 && (int)date('Ymd', $signTs) === $today) {
                    $checkedToday = true;
                    $lastDay = $today;
                }
            }

            if ($api === 'checkin_status') {
                $pts = $pdo->prepare("SELECT `user_points` FROM `{$tUser}` WHERE `user_id`=? LIMIT 1");
                $pts->execute([$userId]);
                $points = (int)($pts->fetchColumn() ?: 0);
                echo json_encode([
                    'code' => 1,
                    'data' => [
                        'checked_today' => $checkedToday ? 1 : 0,
                        'streak' => $streak,
                        'total' => $total,
                        'reward_points' => $reward,
                        'user_points' => $points,
                        'last_day' => $lastDay,
                    ],
                ], JSON_UNESCAPED_UNICODE);
                return;
            }

            // checkin
            if ($checkedToday) {
                $pts = $pdo->prepare("SELECT `user_points` FROM `{$tUser}` WHERE `user_id`=? LIMIT 1");
                $pts->execute([$userId]);
                echo json_encode([
                    'code' => 0,
                    'msg' => '今日已打卡',
                    'data' => [
                        'checked_today' => 1,
                        'streak' => $streak,
                        'total' => $total,
                        'reward_points' => 0,
                        'user_points' => (int)($pts->fetchColumn() ?: 0),
                    ],
                ], JSON_UNESCAPED_UNICODE);
                return;
            }

            $pdo->beginTransaction();
            try {
                $exists = $pdo->prepare("SELECT `user_id` FROM `{$tUser}` WHERE `user_id`=? LIMIT 1 FOR UPDATE");
                $exists->execute([$userId]);
                if (!$exists->fetchColumn()) {
                    throw new RuntimeException('用户不存在');
                }

                $newStreak = ($lastDay === $yesterday) ? ($streak + 1) : 1;
                $newTotal = $total + 1;
                $pdo->prepare(
                    "INSERT INTO `{$tCheckin}` (`user_id`,`last_day`,`streak`,`total`,`updated_at`)
                     VALUES (?,?,?,?,?)
                     ON DUPLICATE KEY UPDATE
                       `last_day`=VALUES(`last_day`),
                       `streak`=VALUES(`streak`),
                       `total`=VALUES(`total`),
                       `updated_at`=VALUES(`updated_at`)"
                )->execute([$userId, $today, $newStreak, $newTotal, time()]);

                $pdo->prepare(
                    "UPDATE `{$tUser}` SET `user_points`=`user_points`+?,`user_sign_time`=? WHERE `user_id`=?"
                )->execute([$reward, time(), $userId]);

                $pts = $pdo->prepare("SELECT `user_points` FROM `{$tUser}` WHERE `user_id`=? LIMIT 1");
                $pts->execute([$userId]);
                $points = (int)($pts->fetchColumn() ?: 0);
                $pdo->commit();

                echo json_encode([
                    'code' => 1,
                    'msg' => '打卡成功，积分 +' . $reward,
                    'data' => [
                        'checked_today' => 1,
                        'streak' => $newStreak,
                        'total' => $newTotal,
                        'reward_points' => $reward,
                        'user_points' => $points,
                    ],
                ], JSON_UNESCAPED_UNICODE);
            } catch (Throwable $e) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                echo json_encode(['code' => 0, 'msg' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
            }
            return;
        }
        if ($api === 'user_vip') {
            $userId = (int)($_GET['user_id'] ?? $_POST['user_id'] ?? 0);
            if ($userId <= 0) {
                echo json_encode(['code' => 0, 'msg' => 'user_id required'], JSON_UNESCAPED_UNICODE);
                return;
            }
            $tUser = $prefix . 'user';
            $tGroup = $prefix . 'group';
            $st = $pdo->prepare(
                "SELECT `u`.`user_id`,`u`.`user_name`,`u`.`user_nick_name`,`u`.`user_points`,
                        `u`.`user_end_time`,`u`.`group_id`,
                        `u`.`user_login_time`,`u`.`user_login_ip`,
                        `u`.`user_last_login_time`,`u`.`user_last_login_ip`,
                        COALESCE(NULLIF(`g`.`group_name`,''),'') AS `group_name`
                 FROM `{$tUser}` `u`
                 LEFT JOIN `{$tGroup}` `g` ON `g`.`group_id`=`u`.`group_id`
                 WHERE `u`.`user_id`=? LIMIT 1"
            );
            $st->execute([$userId]);
            $row = $st->fetch(PDO::FETCH_ASSOC);
            if (!$row) {
                echo json_encode(['code' => 0, 'msg' => 'user not found'], JSON_UNESCAPED_UNICODE);
                return;
            }
            $endRaw = trim((string)($row['user_end_time'] ?? ''));
            $endTs = 0;
            if (is_numeric($endRaw)) {
                $endTs = (int)$endRaw;
                if ($endTs > 9999999999) {
                    $endTs = (int)floor($endTs / 1000);
                }
            } elseif (preg_match('/^(\d{4})-(\d{1,2})-(\d{1,2})/', $endRaw, $m)) {
                $endTs = (int)strtotime(sprintf('%04d-%02d-%02d', (int)$m[1], (int)$m[2], (int)$m[3]));
            }
            $endText = '';
            if ($endTs > 1000000000) {
                // 远未来才算永久占位
                if ($endTs >= 4102444800) {
                    $endText = '永久';
                } else {
                    $endText = date('Y-m-d', $endTs);
                }
            }
            $loginTs = (int)($row['user_login_time'] ?? 0);
            if ($loginTs <= 0) {
                $loginTs = (int)($row['user_last_login_time'] ?? 0);
            }
            $loginTimeText = $loginTs > 1000000000 ? date('Y-m-d H:i', $loginTs) : '';
            $loginIpRaw = trim((string)($row['user_login_ip'] ?? ''));
            if ($loginIpRaw === '' || $loginIpRaw === '0') {
                $loginIpRaw = trim((string)($row['user_last_login_ip'] ?? ''));
            }
            $loginIp = $loginIpRaw;
            if ($loginIp !== '' && ctype_digit($loginIp)) {
                $loginIp = long2ip((int)$loginIp) ?: $loginIp;
            }
            echo json_encode([
                'code' => 1,
                'data' => [
                    'user_id' => (int)$row['user_id'],
                    'user_name' => (string)($row['user_name'] ?? ''),
                    'user_nick_name' => (string)($row['user_nick_name'] ?? ''),
                    'user_points' => (int)($row['user_points'] ?? 0),
                    'group_id' => (int)($row['group_id'] ?? 0),
                    'group_name' => (string)($row['group_name'] ?? ''),
                    'user_end_time' => $endRaw,
                    'user_end_ts' => $endTs,
                    'user_end_text' => $endText,
                    'user_login_time' => $loginTs,
                    'user_login_time_text' => $loginTimeText,
                    'user_login_ip' => $loginIp,
                ],
            ], JSON_UNESCAPED_UNICODE);
            return;
        }
        if ($api === 'art_detail') {
            $artId = (int)($_GET['id'] ?? $_GET['art_id'] ?? 0);
            if ($artId <= 0) {
                echo json_encode(['code' => 0, 'msg' => 'id required'], JSON_UNESCAPED_UNICODE);
                return;
            }
            $tArt = $prefix . 'art';
            $tType = $prefix . 'type';
            $st = $pdo->prepare(
                "SELECT `a`.*, COALESCE(NULLIF(`t`.`type_name`,''),'') AS `type_name`
                 FROM `{$tArt}` `a`
                 LEFT JOIN `{$tType}` `t` ON `t`.`type_id`=`a`.`type_id`
                 WHERE `a`.`art_id`=? LIMIT 1"
            );
            $st->execute([$artId]);
            $row = $st->fetch(PDO::FETCH_ASSOC);
            if (!$row) {
                echo json_encode(['code' => 0, 'msg' => 'not found'], JSON_UNESCAPED_UNICODE);
                return;
            }
            echo json_encode(['code' => 1, 'data' => $row], JSON_UNESCAPED_UNICODE);
            return;
        }
        if ($api === 'vod_collect_sync') {
            // 扫描 mac_vod 新增，写入一条「片库更新」公告（幂等：按 last_vod_id）
            $tVod = $prefix . 'vod';
            $pdo->beginTransaction();
            try {
                $pdo->exec(
                    "INSERT IGNORE INTO `{$tConfig}` (`k`,`v`,`updated_at`) VALUES ('vod_collect_last_id','0'," . time() . ')'
                );
                $st = $pdo->query(
                    "SELECT `v` FROM `{$tConfig}` WHERE `k`='vod_collect_last_id' FOR UPDATE"
                );
                $lastId = (int)($st ? $st->fetchColumn() : 0);
                // 首次：只记当前最大 id 作基线，不刷历史公告
                if ($lastId <= 0) {
                    $maxNow = (int)$pdo->query(
                        "SELECT COALESCE(MAX(`vod_id`),0) FROM `{$tVod}` WHERE `vod_status`=1"
                    )->fetchColumn();
                    huihuoKvSet($pdo, $tConfig, 'vod_collect_last_id', (string)$maxNow);
                    $pdo->commit();
                    echo json_encode([
                        'code' => 1,
                        'msg' => 'baseline',
                        'added' => 0,
                        'titles' => [],
                        'last_id' => $maxNow,
                    ], JSON_UNESCAPED_UNICODE);
                    return;
                }
                $q = $pdo->prepare(
                    "SELECT `vod_id`,`vod_name` FROM `{$tVod}`
                     WHERE `vod_id`>? AND `vod_status`=1
                     ORDER BY `vod_id` ASC LIMIT 80"
                );
                $q->execute([$lastId]);
                $rows = $q->fetchAll(PDO::FETCH_ASSOC) ?: [];
                if (!$rows) {
                    $pdo->commit();
                    echo json_encode([
                        'code' => 1,
                        'msg' => 'ok',
                        'added' => 0,
                        'titles' => [],
                        'last_id' => $lastId,
                    ], JSON_UNESCAPED_UNICODE);
                    return;
                }
                $titles = [];
                $maxId = $lastId;
                foreach ($rows as $r) {
                    $vid = (int)($r['vod_id'] ?? 0);
                    $name = trim((string)($r['vod_name'] ?? ''));
                    if ($vid > $maxId) {
                        $maxId = $vid;
                    }
                    if ($name !== '') {
                        $titles[] = $name;
                    }
                }
                $titles = array_values(array_unique($titles));
                $n = count($titles);
                $show = array_slice($titles, 0, 30);
                $bodyLines = [];
                foreach ($show as $i => $t) {
                    $bodyLines[] = ($i + 1) . '. ' . $t;
                }
                if ($n > count($show)) {
                    $bodyLines[] = '……等共 ' . $n . ' 部';
                }
                $title = '片库更新 · 新增 ' . $n . ' 部';
                $body = implode("\n", $bodyLines);
                $pdo->prepare(
                    "INSERT INTO `{$tNotify}`
                    (`title`,`body`,`link`,`tag`,`subtitle`,`cover_url`,`accent`,`style`,`status`,`created_at`)
                    VALUES (?,?,?,?,?,?,?,?,1,?)"
                )->execute([
                    $title,
                    $body,
                    '',
                    '片库更新',
                    '采集入库',
                    '',
                    '#1ECAD3',
                    'important',
                    time(),
                ]);
                huihuoKvSet($pdo, $tConfig, 'vod_collect_last_id', (string)$maxId);
                huihuoRefreshNotifyJson($pdo, $tNotify, $root);
                $pdo->commit();
                echo json_encode([
                    'code' => 1,
                    'msg' => 'ok',
                    'added' => $n,
                    'titles' => $show,
                    'last_id' => $maxId,
                ], JSON_UNESCAPED_UNICODE);
            } catch (Throwable $e) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                echo json_encode(['code' => 0, 'msg' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
            }
            return;
        }
        if ($api === 'redeem') {
            $raw = file_get_contents('php://input');
            $body = [];
            if (is_string($raw) && $raw !== '') {
                $decoded = json_decode($raw, true);
                if (is_array($decoded)) {
                    $body = $decoded;
                }
            }
            $code = strtoupper(trim((string)($body['code'] ?? $_POST['code'] ?? '')));
            $userId = (int)($body['user_id'] ?? $_POST['user_id'] ?? 0);
            $userName = trim((string)($body['user_name'] ?? $_POST['user_name'] ?? ''));
            if ($code === '') {
                echo json_encode(['code' => 0, 'msg' => '请输入兑换码'], JSON_UNESCAPED_UNICODE);
                return;
            }
            if ($userId <= 0) {
                echo json_encode(['code' => 0, 'msg' => '请先登录'], JSON_UNESCAPED_UNICODE);
                return;
            }
            $pdo->beginTransaction();
            try {
                $st = $pdo->prepare(
                    "SELECT * FROM `{$tRedeem}` WHERE `code`=? LIMIT 1 FOR UPDATE"
                );
                $st->execute([$code]);
                $row = $st->fetch(PDO::FETCH_ASSOC);
                if (!$row) {
                    throw new RuntimeException('兑换码不存在');
                }
                if ((int)$row['status'] !== 1 || (int)$row['used_by'] > 0) {
                    throw new RuntimeException('兑换码已使用或已失效');
                }
                $rtype = (string)$row['reward_type'];
                $rval = (int)$row['reward_value'];
                $tUser = $prefix . 'user';
                if ($rtype === 'vip_days') {
                    $u = $pdo->prepare(
                        "SELECT `user_end_time`,`group_id` FROM `{$tUser}` WHERE `user_id`=? LIMIT 1"
                    );
                    $u->execute([$userId]);
                    $urow = $u->fetch(PDO::FETCH_ASSOC) ?: [];
                    $cur = $urow['user_end_time'] ?? 0;
                    $now = time();
                    $base = is_numeric($cur) ? (int)$cur : 0;
                    if ($base < $now) {
                        $base = $now;
                    }
                    $end = $base + max(1, $rval) * 86400;
                    // 注册会员(≤2) 升到默认 VIP 组 3，已是更高组则保留
                    $gid = (int)($urow['group_id'] ?? 0);
                    if ($gid < 3) {
                        $gid = 3;
                    }
                    $pdo->prepare(
                        "UPDATE `{$tUser}` SET `user_end_time`=?,`group_id`=? WHERE `user_id`=?"
                    )->execute([(string)$end, $gid, $userId]);
                    $rewardText = '会员 +' . $rval . ' 天';
                } else {
                    $pdo->prepare(
                        "UPDATE `{$tUser}` SET `user_points`=`user_points`+? WHERE `user_id`=?"
                    )->execute([max(1, $rval), $userId]);
                    $rewardText = '积分 +' . $rval;
                }
                $pdo->prepare(
                    "UPDATE `{$tRedeem}` SET `status`=0,`used_by`=?,`used_name`=?,`used_at`=? WHERE `id`=?"
                )->execute([$userId, $userName, time(), (int)$row['id']]);
                $pdo->commit();
                echo json_encode([
                    'code' => 1,
                    'msg' => '兑换成功',
                    'reward_type' => $rtype,
                    'reward_value' => $rval,
                    'reward_text' => $rewardText,
                ], JSON_UNESCAPED_UNICODE);
            } catch (Throwable $e) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                echo json_encode(['code' => 0, 'msg' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
            }
            return;
        }
        http_response_code(404);
        echo json_encode(['code' => 0, 'msg' => 'unknown api'], JSON_UNESCAPED_UNICODE);
    } catch (Throwable $e) {
        http_response_code(500);
        echo json_encode(['code' => 0, 'msg' => $e->getMessage()], JSON_UNESCAPED_UNICODE);
    }
}
