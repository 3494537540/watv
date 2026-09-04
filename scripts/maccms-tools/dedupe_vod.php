<?php
/**
 * 苹果 CMS：一键清理影视库
 *
 *   ?key=密钥&mode=dry       只统计
 *   ?key=密钥&mode=empty     删无播放链接空壳
 *   ?key=密钥&mode=official  删「全部」官源（qiyi/qq/youku 网页线，无 m3u8）
 *   ?key=密钥&mode=dedupe    同名只留 1 条（优先 m3u8）
 *   ?key=密钥&mode=clean     空壳 + 官源 + 重名（推荐一次做完）
 *   ?key=密钥&mode=wipe&confirm=YES  清空全部
 *
 * 上传到：/www/wwwroot/154.12.29.28/maccms-tools/dedupe_vod.php
 * 用完请删除本文件。
 */

declare(strict_types=1);

const SECRET_KEY = 'huihuo_dedupe_2026';
const MAC_ROOT = '';

header('Content-Type: text/plain; charset=utf-8');

$cli = (PHP_SAPI === 'cli');
$opts = $cli ? getopt('', ['key:', 'mode:', 'confirm:']) : [];
$key = $cli ? (isset($opts['key']) ? $opts['key'] : '') : (string)(isset($_GET['key']) ? $_GET['key'] : '');
$mode = $cli ? (isset($opts['mode']) ? $opts['mode'] : 'dry') : (string)(isset($_GET['mode']) ? $_GET['mode'] : 'dry');
$confirm = $cli ? (isset($opts['confirm']) ? $opts['confirm'] : '') : (string)(isset($_GET['confirm']) ? $_GET['confirm'] : '');

if ($key === '' || !hash_equals(SECRET_KEY, $key)) {
    http_response_code(403);
    echo "forbidden: key 不对\n";
    exit(1);
}

$root = MAC_ROOT !== '' ? rtrim(MAC_ROOT, '/\\') : findMacRoot(__DIR__);
if ($root === null) {
    echo "找不到苹果CMS根目录（需含 application/database.php）\n";
    echo "请把 MAC_ROOT 改成例如 /www/wwwroot/154.12.29.28\n";
    exit(1);
}

$dbCfg = loadDbConfig($root);
if ($dbCfg === null) {
    echo "读取数据库配置失败\n";
    exit(1);
}

try {
    $pdo = new PDO(
        sprintf(
            'mysql:host=%s;port=%s;dbname=%s;charset=%s',
            $dbCfg['hostname'],
            $dbCfg['hostport'] ? $dbCfg['hostport'] : '3306',
            $dbCfg['database'],
            $dbCfg['charset'] ? $dbCfg['charset'] : 'utf8mb4'
        ),
        $dbCfg['username'],
        $dbCfg['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );
} catch (Throwable $e) {
    echo '数据库连接失败: ' . $e->getMessage() . "\n";
    exit(1);
}

$prefix = $dbCfg['prefix'] ? $dbCfg['prefix'] : 'mac_';
$table = $prefix . 'vod';
$emptyWhere = emptyPlayWhere();
$officialWhere = officialPlayWhere();

echo "CMS根目录: {$root}\n";
echo "数据表: {$table}\n";
echo "模式: {$mode}\n\n";

$total = (int)$pdo->query("SELECT COUNT(*) FROM `{$table}`")->fetchColumn();
$emptyCount = (int)$pdo->query("SELECT COUNT(*) FROM `{$table}` WHERE {$emptyWhere}")->fetchColumn();
$officialCount = (int)$pdo->query("SELECT COUNT(*) FROM `{$table}` WHERE {$officialWhere}")->fetchColumn();

$dupGroups = $pdo->query(
    "SELECT vod_name, COUNT(*) AS c FROM `{$table}` GROUP BY vod_name HAVING c > 1"
)->fetchAll();
$dupNames = count($dupGroups);
$dupRows = 0;
foreach ($dupGroups as $g) {
    $dupRows += ((int)$g['c'] - 1);
}

echo "当前视频总数: {$total}\n";
echo "无播放链接空壳: {$emptyCount}\n";
echo "「全部」官源网页线(无m3u8): {$officialCount}\n";
echo "重名片名数: {$dupNames}\n";
echo "可删重复条数(大约): {$dupRows}\n\n";

if ($mode === 'dry') {
    echo "dry 模式结束（未删除）。\n";
    echo "删空壳:     ?key=密钥&mode=empty\n";
    echo "删官源全部: ?key=密钥&mode=official\n";
    echo "删重名:     ?key=密钥&mode=dedupe\n";
    echo "一次全做:   ?key=密钥&mode=clean\n";
    echo "清空库:     ?key=密钥&mode=wipe&confirm=YES\n";
    exit(0);
}

if ($mode === 'wipe') {
    if ($confirm !== 'YES') {
        echo "清空全部需要 confirm=YES，已取消。\n";
        exit(1);
    }
    $pdo->exec("TRUNCATE TABLE `{$table}`");
    foreach (['vod_search', 'vod_rank'] as $extra) {
        try {
            $pdo->exec("TRUNCATE TABLE `{$prefix}{$extra}`");
            echo "已清空 {$prefix}{$extra}\n";
        } catch (Throwable $e) {
        }
    }
    echo "已清空全部视频。请重新跑 m3u8 采集。\n";
    exit(0);
}

if ($mode === 'empty' || $mode === 'clean') {
    $n = deleteByWhere($pdo, $table, $emptyWhere, '空壳');
    echo "已删除无播放链接空壳: {$n} 条\n\n";
    if ($mode === 'empty') {
        finishHint();
        exit(0);
    }
}

if ($mode === 'official' || $mode === 'clean') {
    $n = deleteByWhere($pdo, $table, $officialWhere, '官源全部');
    echo "已删除「全部」官源网页影视: {$n} 条\n\n";
    if ($mode === 'official') {
        finishHint();
        exit(0);
    }
}

if ($mode === 'dedupe' || $mode === 'clean') {
    $result = dedupeByName($pdo, $table);
    echo "\n完成删重：处理重名组 {$result['groups']} 个，删除重复 {$result['deleted']} 条。\n";
    finishHint();
    exit(0);
}

echo "未知 mode，可用: dry / empty / official / dedupe / clean / wipe\n";
exit(1);

function finishHint()
{
    echo "请到后台：系统 → 缓存清理。\n";
    echo "用完请删除本 PHP 文件。\n";
}

/** 无播放地址 */
function emptyPlayWhere()
{
    return "(vod_play_url IS NULL OR TRIM(vod_play_url) = '' OR TRIM(REPLACE(vod_play_url, '\$\$\$', '')) = '')";
}

/**
 * 「全部」资源站官源：qiyi / qq / youku 网页，且没有 m3u8 直链
 * 已有 mtm3u8/modum3u8 等的不删
 */
function officialPlayWhere()
{
    $noM3u8 = "(IFNULL(vod_play_url,'') NOT LIKE '%.m3u8%' AND IFNULL(vod_play_from,'') NOT LIKE '%m3u8%')";
    // 播放器编码或地址域名命中官源
    $isOfficial = "("
        . "IFNULL(vod_play_from,'') LIKE '%qiyi%' "
        . "OR IFNULL(vod_play_from,'') LIKE '%youku%' "
        . "OR IFNULL(vod_play_from,'') = 'qq' "
        . "OR IFNULL(vod_play_from,'') LIKE 'qq$$$%' "
        . "OR IFNULL(vod_play_from,'') LIKE '%$$$qq' "
        . "OR IFNULL(vod_play_from,'') LIKE '%$$$qq$$$%' "
        . "OR IFNULL(vod_play_url,'') LIKE '%iqiyi.com%' "
        . "OR IFNULL(vod_play_url,'') LIKE '%v.qq.com%' "
        . "OR IFNULL(vod_play_url,'') LIKE '%youku.com%' "
        . "OR IFNULL(vod_play_url,'') LIKE '%.iq.com%'"
        . ")";
    return "({$isOfficial} AND {$noM3u8})";
}

/**
 * @param PDO $pdo
 * @return int
 */
function deleteByWhere($pdo, $table, $where, $label)
{
    $samples = $pdo->query(
        "SELECT vod_id, vod_name, vod_play_from FROM `{$table}` WHERE {$where} ORDER BY vod_id DESC LIMIT 10"
    )->fetchAll();
    if ($samples) {
        echo "{$label}样例（最多10条）:\n";
        foreach ($samples as $s) {
            echo "  #{$s['vod_id']} {$s['vod_name']} from={$s['vod_play_from']}\n";
        }
        echo "\n";
    }
    return (int)$pdo->exec("DELETE FROM `{$table}` WHERE {$where}");
}

/**
 * @param PDO $pdo
 * @return array
 */
function dedupeByName($pdo, $table)
{
    $deleted = 0;
    $kept = 0;
    $names = $pdo->query(
        "SELECT vod_name FROM `{$table}` GROUP BY vod_name HAVING COUNT(*) > 1"
    )->fetchAll(PDO::FETCH_COLUMN);

    foreach ($names as $name) {
        $st = $pdo->prepare(
            "SELECT vod_id, vod_name, vod_play_from, vod_play_url FROM `{$table}` WHERE vod_name = ? ORDER BY vod_id DESC"
        );
        $st->execute([$name]);
        $rows = $st->fetchAll();
        if (count($rows) < 2) {
            continue;
        }

        $keepId = null;
        foreach ($rows as $r) {
            $from = strtolower((string)$r['vod_play_from']);
            $url = strtolower((string)$r['vod_play_url']);
            if (strpos($from, 'm3u8') !== false || strpos($url, '.m3u8') !== false) {
                $keepId = (int)$r['vod_id'];
                break;
            }
        }
        if ($keepId === null) {
            foreach ($rows as $r) {
                if (trim((string)$r['vod_play_url']) !== '') {
                    $keepId = (int)$r['vod_id'];
                    break;
                }
            }
        }
        if ($keepId === null) {
            $keepId = (int)$rows[0]['vod_id'];
        }

        $ids = [];
        foreach ($rows as $r) {
            $id = (int)$r['vod_id'];
            if ($id !== $keepId) {
                $ids[] = $id;
            }
        }
        if ($ids === []) {
            continue;
        }
        $pdo->exec('DELETE FROM `' . $table . '` WHERE vod_id IN (' . implode(',', $ids) . ')');
        $deleted += count($ids);
        $kept++;
        echo "保留 #{$keepId} 「{$name}」，删除 " . count($ids) . " 条\n";
    }

    return ['groups' => $kept, 'deleted' => $deleted];
}

/** @return string|null */
function findMacRoot($start)
{
    $dir = realpath($start);
    for ($i = 0; $i < 6; $i++) {
        if ($dir && is_file($dir . '/application/database.php')) {
            return $dir;
        }
        $parent = dirname($dir);
        if ($parent === $dir) {
            break;
        }
        $dir = $parent;
    }
    foreach ([dirname($start), dirname(dirname($start)), '/www/wwwroot/154.12.29.28'] as $g) {
        if (is_file($g . '/application/database.php')) {
            return $g;
        }
    }
    return null;
}

/** @return array|null */
function loadDbConfig($root)
{
    $file = $root . '/application/database.php';
    if (!is_file($file)) {
        return null;
    }
    $cfg = include $file;
    if (!is_array($cfg)) {
        return null;
    }
    return [
        'hostname' => isset($cfg['hostname']) ? $cfg['hostname'] : '127.0.0.1',
        'database' => isset($cfg['database']) ? $cfg['database'] : '',
        'username' => isset($cfg['username']) ? $cfg['username'] : '',
        'password' => isset($cfg['password']) ? $cfg['password'] : '',
        'hostport' => isset($cfg['hostport']) ? $cfg['hostport'] : '3306',
        'charset' => isset($cfg['charset']) ? $cfg['charset'] : 'utf8mb4',
        'prefix' => isset($cfg['prefix']) ? $cfg['prefix'] : 'mac_',
    ];
}
