<?php
/**
 * 苹果 CMS：分类（mac_type）导出 / 一键导入
 *
 * 重装前导出，重装后导入，避免手工点 94 个分类。
 *
 * Web（上传到站点 maccms-tools/ 目录）：
 *   ?key=密钥&mode=export              导出 JSON（浏览器下载）
 *   ?key=密钥&mode=dry&file=xxx.json   预览导入
 *   ?key=密钥&mode=import&file=xxx.json&confirm=YES   覆盖导入（保留 type_id）
 *
 * CLI（SSH，在 MacCMS 根目录或本目录）：
 *   php type_backup.php --key=密钥 --mode=export
 *   php type_backup.php --key=密钥 --mode=import --file=backups/type_xxx.json --confirm=YES
 *
 * 密钥默认：huihuo_type_2026
 * 用完请删除本文件。
 */
declare(strict_types=1);

const SECRET_KEY = 'huihuo_type_2026';
const MAC_ROOT = '';

$bootstrap = __DIR__ . '/mac_bootstrap.php';
if (!is_file($bootstrap)) {
    $bootstrap = __DIR__ . '/backups/mac_bootstrap.php';
}
if (!is_file($bootstrap)) {
    header('Content-Type: text/plain; charset=utf-8');
    http_response_code(500);
    echo "找不到 mac_bootstrap.php\n";
    echo "请与 type_backup.php 放在同一目录：maccms-tools/mac_bootstrap.php\n";
    echo "（JSON 备份放 maccms-tools/backups/ 即可，bootstrap 不要放 backups 里）\n";
    exit(1);
}
require $bootstrap;

$cli = (PHP_SAPI === 'cli');
$opts = $cli ? getopt('', ['key:', 'mode:', 'file:', 'confirm:']) : [];
$key = $cli
    ? (isset($opts['key']) ? $opts['key'] : '')
    : (string)(isset($_GET['key']) ? $_GET['key'] : '');
$mode = $cli
    ? (isset($opts['mode']) ? $opts['mode'] : 'dry')
    : (string)(isset($_GET['mode']) ? $_GET['mode'] : 'dry');
$file = $cli
    ? (isset($opts['file']) ? $opts['file'] : '')
    : (string)(isset($_GET['file']) ? $_GET['file'] : '');
$confirm = $cli
    ? (isset($opts['confirm']) ? $opts['confirm'] : '')
    : (string)(isset($_GET['confirm']) ? $_GET['confirm'] : '');

if ($key === '' || !hash_equals(SECRET_KEY, $key)) {
    if (!$cli) {
        header('Content-Type: text/plain; charset=utf-8');
        http_response_code(403);
    }
    echo "forbidden: key 不对\n";
    exit(1);
}

$root = MAC_ROOT !== '' ? rtrim(MAC_ROOT, '/\\') : macFindRoot(__DIR__);
if ($root === null) {
    echo "找不到苹果CMS根目录。请设置 MAC_ROOT 或把脚本放到站点目录下。\n";
    exit(1);
}

try {
    $pdo = macPdo($root);
} catch (Throwable $e) {
    echo '数据库连接失败: ' . $e->getMessage() . "\n";
    exit(1);
}

$typeInfo = macTypeTable($root);
$table = $typeInfo['table'];
$backupDir = __DIR__ . '/backups';
if (!is_dir($backupDir)) {
    @mkdir($backupDir, 0755, true);
}

if ($mode === 'export') {
    doExport($pdo, $table, $backupDir, $cli);
    exit(0);
}

if ($mode === 'dry' || $mode === 'import') {
    $path = resolveBackupFile($backupDir, $file);
    if ($path === null) {
        echo "找不到备份文件。请先 mode=export，或指定 file=backups/type_xxx.json\n";
        listBackupFiles($backupDir);
        exit(1);
    }
    $payload = loadBackupJson($path);
    $rows = isset($payload['rows']) ? $payload['rows'] : [];
    if ($rows === []) {
        echo "备份为空: {$path}\n";
        exit(1);
    }

    echo "CMS根目录: {$root}\n";
    echo "数据表: {$table}\n";
    echo "备份文件: {$path}\n";
    echo "备份时间: " . (isset($payload['exported_at']) ? $payload['exported_at'] : '?') . "\n";
    echo "分类条数: " . count($rows) . "\n\n";
    printTypeTree($rows);

    if ($mode === 'dry') {
        echo "\ndry 结束（未写入）。\n";
        echo "覆盖导入: mode=import&file=" . basename($path) . "&confirm=YES\n";
        echo "说明：import 会 TRUNCATE 分类表并按备份还原 type_id（适合新装空库）。\n";
        exit(0);
    }

    if ($confirm !== 'YES') {
        echo "\n导入需要 confirm=YES，已取消。\n";
        exit(1);
    }

    $n = doImportReplace($pdo, $table, $rows);
    echo "\n已导入 {$n} 条分类。\n";
    echo "请到后台：系统 → 清空缓存。\n";
    echo "若已配置采集绑定，重装后仍需在「采集 → 接口 → 绑定分类」里核对一次。\n";
    exit(0);
}

if (!$cli) {
    header('Content-Type: text/plain; charset=utf-8');
}
echo "未知 mode={$mode}\n";
echo "可用: export | dry | import\n";
exit(1);

/** @param PDO $pdo */
function doExport($pdo, $table, $backupDir, $cli)
{
    $cols = macTypeColumns($pdo, $table);
    $st = $pdo->query('SELECT * FROM `' . str_replace('`', '', $table) . '` ORDER BY type_pid ASC, type_sort ASC, type_id ASC');
    $rows = $st->fetchAll();

    $payload = [
        'format' => 'maccms_type_backup_v1',
        'exported_at' => gmdate('Y-m-d\TH:i:s\Z'),
        'table' => $table,
        'columns' => $cols,
        'row_count' => count($rows),
        'rows' => $rows,
    ];

    $name = 'type_' . date('Ymd_His') . '.json';
    $path = rtrim($backupDir, '/\\') . DIRECTORY_SEPARATOR . $name;
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    if ($json === false) {
        echo "JSON 编码失败\n";
        exit(1);
    }
    file_put_contents($path, $json);

    if ($cli) {
        echo "已导出 " . count($rows) . " 条 → {$path}\n";
        printTypeTree($rows);
        return;
    }

    header('Content-Type: application/json; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . $name . '"');
    echo $json;
}

/** @param list<array<string,mixed>> $rows */
function printTypeTree($rows)
{
    $byId = [];
    $children = [];
    foreach ($rows as $r) {
        $id = (int)$r['type_id'];
        $byId[$id] = $r;
        $pid = (int)$r['type_pid'];
        if (!isset($children[$pid])) {
            $children[$pid] = [];
        }
        $children[$pid][] = $id;
    }

    echo "分类树预览（前 40 行）：\n";
    $lines = 0;
    $walk = function ($pid, $depth) use (&$walk, &$lines, $children, $byId) {
        if (!isset($children[$pid])) {
            return;
        }
        foreach ($children[$pid] as $id) {
            if ($lines >= 40) {
                return;
            }
            $r = $byId[$id];
            $st = ((int)$r['type_status'] === 1) ? '开' : '关';
            $mid = isset($r['type_mid']) ? $r['type_mid'] : '?';
            echo str_repeat('  ', $depth)
                . "- [{$id}] {$r['type_name']} ({$r['type_en']}) pid={$r['type_pid']} mid={$mid} {$st}\n";
            $lines++;
            $walk($id, $depth + 1);
        }
    };
    $walk(0, 0);
    if (count($rows) > 40) {
        echo "... 共 " . count($rows) . " 条\n";
    }
}

/** @return string|null */
function resolveBackupFile($backupDir, $file)
{
    if ($file === '') {
        $files = glob(rtrim($backupDir, '/\\') . DIRECTORY_SEPARATOR . 'type_*.json');
        if (!$files) {
            return null;
        }
        usort($files, function ($a, $b) {
            return filemtime($b) <=> filemtime($a);
        });
        return $files[0];
    }
    if (is_file($file)) {
        return $file;
    }
    $p = rtrim($backupDir, '/\\') . DIRECTORY_SEPARATOR . basename($file);
    if (is_file($p)) {
        return $p;
    }
    $p2 = __DIR__ . DIRECTORY_SEPARATOR . basename($file);
    if (is_file($p2)) {
        return $p2;
    }
    return null;
}

/** @return array<string,mixed> */
function loadBackupJson($path)
{
    $raw = file_get_contents($path);
    if ($raw === false) {
        throw new RuntimeException('读文件失败');
    }
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        throw new RuntimeException('JSON 无效');
    }
    return $data;
}

/** @param list<array<string,mixed>> $rows */
function doImportReplace($pdo, $table, $rows)
{
    $liveCols = macTypeColumns($pdo, $table);
    $backupCols = [];
    if (isset($rows[0]) && is_array($rows[0])) {
        $backupCols = array_keys($rows[0]);
    }
    $cols = array_values(array_intersect($liveCols, $backupCols));
    if ($cols === []) {
        throw new RuntimeException('备份字段与当前表不匹配');
    }
    if (!in_array('type_id', $cols, true) || !in_array('type_name', $cols, true)) {
        throw new RuntimeException('备份缺少 type_id / type_name');
    }

    $safeTable = str_replace('`', '', $table);
    $pdo->beginTransaction();
    try {
        $pdo->exec('TRUNCATE TABLE `' . $safeTable . '`');
        $placeholders = implode(',', array_fill(0, count($cols), '?'));
        $colList = implode(',', array_map(function ($c) {
            return '`' . str_replace('`', '', $c) . '`';
        }, $cols));
        $sql = 'INSERT INTO `' . $safeTable . '` (' . $colList . ') VALUES (' . $placeholders . ')';
        $st = $pdo->prepare($sql);

        $maxId = 0;
        foreach ($rows as $row) {
            $vals = [];
            foreach ($cols as $c) {
                $vals[] = array_key_exists($c, $row) ? $row[$c] : '';
            }
            $st->execute($vals);
            if (isset($row['type_id'])) {
                $maxId = max($maxId, (int)$row['type_id']);
            }
        }
        if ($maxId > 0) {
            $pdo->exec('ALTER TABLE `' . $safeTable . '` AUTO_INCREMENT = ' . ($maxId + 1));
        }
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        throw $e;
    }
    return count($rows);
}

/** @param string $backupDir */
function listBackupFiles($backupDir)
{
    $files = glob(rtrim($backupDir, '/\\') . DIRECTORY_SEPARATOR . 'type_*.json');
    if (!$files) {
        echo "backups/ 下暂无 type_*.json\n";
        return;
    }
    echo "已有备份：\n";
    foreach ($files as $f) {
        echo '  · ' . basename($f) . "\n";
    }
}
