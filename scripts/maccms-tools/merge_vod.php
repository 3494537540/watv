<?php
/**
 * 苹果 CMS：影视重复「严谨合并」
 *
 * 原则：宁可不合并，也不误合并。同名 ≠ 同片。
 *
 * 只有「强证据」才自动合并：
 *   - 年份一致 / 导演有交集 / 主演明显重叠 / 封面图一致
 * 仅同名、元数据空、封面不同且无其它证据 → 绝不合并（列入存疑）
 *
 * 不参与判定（仅展示参考）：语言、地区（如「国语」写在地区、「中国大陆」写在语言都很常见，且常为空）
 * 不阻止合并：扩展分类(vod_class)、备注、播放线路不同
 * 强制不合并：年份差≥2；导演都有且无交集；主演都有且完全无交集（safe）
 *
 * Web：
 *   ?key=huihuo_merge_2026&mode=dry&level=safe
 *   （也兼容 huihuo_dedupe_2026 / huihuo_type_2026）
 *
 * 密钥：huihuo_merge_2026
 */
declare(strict_types=1);

const SECRET_KEY = 'huihuo_merge_2026';
/** 兼容其它运维脚本密钥，避免记混 */
const SECRET_KEYS = ['huihuo_merge_2026', 'huihuo_dedupe_2026', 'huihuo_type_2026'];
const MAC_ROOT = '';

$cli = (PHP_SAPI === 'cli');
if (!$cli) {
    header('Content-Type: text/plain; charset=utf-8');
}

@ini_set('memory_limit', '512M');
@set_time_limit(0);

$opts = $cli ? getopt('', ['key:', 'mode:', 'level:', 'limit:', 'confirm:', 'name:']) : [];
$key = $cli ? (isset($opts['key']) ? $opts['key'] : '') : (string)(isset($_GET['key']) ? $_GET['key'] : '');
$mode = $cli ? (isset($opts['mode']) ? $opts['mode'] : 'dry') : (string)(isset($_GET['mode']) ? $_GET['mode'] : 'dry');
$level = $cli ? (isset($opts['level']) ? $opts['level'] : 'safe') : (string)(isset($_GET['level']) ? $_GET['level'] : 'safe');
$limit = $cli ? (isset($opts['limit']) ? (int)$opts['limit'] : 50) : (int)(isset($_GET['limit']) ? $_GET['limit'] : 50);
$confirm = $cli ? (isset($opts['confirm']) ? $opts['confirm'] : '') : (string)(isset($_GET['confirm']) ? $_GET['confirm'] : '');
$nameFilter = $cli ? (isset($opts['name']) ? $opts['name'] : '') : (string)(isset($_GET['name']) ? $_GET['name'] : '');

if (!keyAllowed($key)) {
    http_response_code(403);
    echo "forbidden: key 不对\n";
    echo "请用: key=huihuo_merge_2026\n";
    echo "完整示例:\n";
    echo "  ?key=huihuo_merge_2026&mode=dry&level=safe\n";
    exit(1);
}

$level = strtolower($level);
if (!in_array($level, ['safe', 'strict', 'normal', 'loose'], true)) {
    $level = 'safe';
}

/**
 * require_strong: 必须有强证据才 merge
 * block_zero_actor: 双方主演都有且零交集 → 强制不合并
 * allow_name_only: 是否允许「仅同名」合并（safe/strict=否）
 */
$thresholds = [
    'safe' => [
        'merge' => 80,
        'hard_block_year' => true,
        'require_strong' => true,
        'block_zero_actor' => true,
        'allow_name_only' => false,
        'cover_mismatch_needs_other' => true,
    ],
    'strict' => [
        'merge' => 70,
        'hard_block_year' => true,
        'require_strong' => true,
        'block_zero_actor' => true,
        'allow_name_only' => false,
        'cover_mismatch_needs_other' => true,
    ],
    'normal' => [
        'merge' => 55,
        'hard_block_year' => true,
        'require_strong' => false,
        'block_zero_actor' => false,
        'allow_name_only' => false,
        'cover_mismatch_needs_other' => false,
    ],
    'loose' => [
        'merge' => 40,
        'hard_block_year' => false,
        'require_strong' => false,
        'block_zero_actor' => false,
        'allow_name_only' => true,
        'cover_mismatch_needs_other' => false,
    ],
];
$cfg = $thresholds[$level];

$bootstrap = __DIR__ . '/mac_bootstrap.php';
if (!is_file($bootstrap)) {
    $bootstrap = __DIR__ . '/backups/mac_bootstrap.php';
}
if (is_file($bootstrap)) {
    require $bootstrap;
    $root = MAC_ROOT !== '' ? rtrim(MAC_ROOT, '/\\') : macFindRoot(__DIR__);
    if ($root === null) {
        echo "找不到苹果CMS根目录\n";
        exit(1);
    }
    try {
        $pdo = macPdo($root);
        $prefix = macTypeTable($root)['prefix'];
    } catch (Throwable $e) {
        echo '数据库失败: ' . $e->getMessage() . "\n";
        exit(1);
    }
} else {
    $root = MAC_ROOT !== '' ? rtrim(MAC_ROOT, '/\\') : findMacRootLocal(__DIR__);
    if ($root === null) {
        echo "找不到苹果CMS根目录，且缺少 mac_bootstrap.php\n";
        exit(1);
    }
    $dbCfg = loadDbConfigLocal($root);
    if ($dbCfg === null) {
        echo "读 database.php 失败\n";
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
        echo '数据库失败: ' . $e->getMessage() . "\n";
        exit(1);
    }
    $prefix = $dbCfg['prefix'] ? $dbCfg['prefix'] : 'mac_';
}

$table = str_replace('`', '', $prefix . 'vod');
$cols = array_column($pdo->query("SHOW COLUMNS FROM `{$table}`")->fetchAll(), 'Field');
foreach (['vod_id', 'vod_name', 'vod_play_from', 'vod_play_url'] as $c) {
    if (!in_array($c, $cols, true)) {
        echo "表缺少字段 {$c}\n";
        exit(1);
    }
}

$metaCols = [
    'vod_id', 'vod_name', 'type_id', 'vod_class', 'vod_year', 'vod_area', 'vod_lang',
    'vod_actor', 'vod_director', 'vod_remarks', 'vod_total', 'vod_serial',
    'vod_play_from', 'vod_play_url', 'vod_pic', 'vod_score', 'vod_hits', 'vod_time',
];
$metaCols = array_values(array_intersect($metaCols, $cols));
$metaSql = implode(',', array_map(function ($c) {
    return '`' . $c . '`';
}, $metaCols));

echo "CMS根目录: {$root}\n";
echo "数据表: {$table}\n";
echo "模式: {$mode} | 规则档: {$level}（重要数据请用 safe）\n";
echo "原则: 宁可不合并，也不误把两部不同的剧并成一条。\n";
echo "注意: 语言/地区字段常为空或写反（国语↔中国大陆），只作展示参考，不参与合并判定。\n\n";
printRulesHelp($level, $cfg);

if ($mode === 'merge' && $confirm !== 'YES') {
    echo "合并需要 confirm=YES。请先 mode=dry 仔细核对「确定合并」列表。\n";
    exit(1);
}
if (!in_array($mode, ['dry', 'merge'], true)) {
    echo "未知 mode，可用 dry / merge\n";
    exit(1);
}

$total = (int)$pdo->query("SELECT COUNT(*) FROM `{$table}`")->fetchColumn();
echo "库内视频总数: {$total}\n";

$nameSql = "SELECT `vod_id`, `vod_name` FROM `{$table}`";
$nameParams = [];
if ($nameFilter !== '') {
    $nameSql .= ' WHERE `vod_name` LIKE ?';
    $nameParams[] = '%' . $nameFilter . '%';
}
$st = $pdo->prepare($nameSql);
$st->execute($nameParams);

$byNormIds = [];
$normSampleTitle = [];
$scanned = 0;
while ($row = $st->fetch(PDO::FETCH_ASSOC)) {
    $scanned++;
    $nk = normalizeTitle((string)$row['vod_name']);
    if ($nk === '') {
        continue;
    }
    if (!isset($byNormIds[$nk])) {
        $byNormIds[$nk] = [];
        $normSampleTitle[$nk] = (string)$row['vod_name'];
    }
    $byNormIds[$nk][] = (int)$row['vod_id'];
}
$st->closeCursor();
unset($st);

$dupNorms = [];
foreach ($byNormIds as $nk => $ids) {
    if (count($ids) >= 2) {
        $dupNorms[] = $nk;
    } else {
        unset($byNormIds[$nk], $normSampleTitle[$nk]);
    }
}
echo "已扫片名: {$scanned}\n";
echo "归一化同名候选组: " . count($dupNorms) . "\n\n";
flush_merge();

$show = max(1, min(200, $limit));
$candidateGroups = count($dupNorms);
$mergeGroupCount = 0;
$deleteCount = 0;
$unsureCount = 0;
$blockPairCount = 0;
$previewMerge = [];
$previewUnsure = [];
$previewBlock = [];
$mergedOk = 0;

if ($mode === 'merge') {
    $pdo->beginTransaction();
}

try {
    $processed = 0;
    foreach ($dupNorms as $nk) {
        $ids = $byNormIds[$nk];
        unset($byNormIds[$nk]);
        $processed++;
        if ($processed % 300 === 0) {
            echo "…已分析 {$processed}/{$candidateGroups} 组"
                . ($mode === 'merge' ? "，已写入 {$mergedOk}" : '') . "\n";
            flush_merge();
        }

        $rows = loadRowsByIds($pdo, $table, $metaSql, $ids);
        if (count($rows) < 2) {
            continue;
        }

        // 记录存疑/硬冲突样例（基于两两判决，不依赖簇）
        $pairNotes = collectPairNotes($rows, $cfg);
        $blockPairCount += $pairNotes['block'];
        $unsureCount += $pairNotes['unsure'];
        foreach ($pairNotes['unsure_samples'] as $s) {
            if (count($previewUnsure) < $show) {
                $previewUnsure[] = $s;
            }
        }
        foreach ($pairNotes['block_samples'] as $s) {
            if (count($previewBlock) < $show) {
                $previewBlock[] = $s;
            }
        }

        $clusters = clusterRows($rows, $cfg);
        foreach ($clusters as $cluster) {
            if (count($cluster) < 2) {
                continue;
            }
            // safe/strict：禁止「传递合并」误伤（A≈B、B≈C 但 A≠C）
            // 只输出「全员两两均为 merge」的团；否则拆成确定的 pair 逐对合并
            if (!empty($cfg['require_strong'])) {
                if (clusterFullyCompatible($cluster, $cfg)) {
                    handleCluster($cluster, $mode, $show, $cfg, $cols, $pdo, $table,
                        $mergeGroupCount, $deleteCount, $previewMerge, $mergedOk);
                } else {
                    foreach (extractSafePairs($cluster, $cfg) as $pair) {
                        handleCluster($pair, $mode, $show, $cfg, $cols, $pdo, $table,
                            $mergeGroupCount, $deleteCount, $previewMerge, $mergedOk);
                    }
                }
                continue;
            }
            handleCluster($cluster, $mode, $show, $cfg, $cols, $pdo, $table,
                $mergeGroupCount, $deleteCount, $previewMerge, $mergedOk);
        }
        unset($rows, $clusters);
    }

    if ($mode === 'merge') {
        $pdo->commit();
    }
} catch (Throwable $e) {
    if ($mode === 'merge') {
        $pdo->rollBack();
    }
    echo '失败' . ($mode === 'merge' ? '已回滚' : '') . ': ' . $e->getMessage() . "\n";
    exit(1);
}

unset($byNormIds, $normSampleTitle, $dupNorms);

echo "======== 统计 ========\n";
echo "同名候选组: {$candidateGroups}\n";
echo "【确定合并】组: {$mergeGroupCount}（将删重复约 {$deleteCount} 条）\n";
echo "【存疑】对数(约): {$unsureCount}（不会自动合并）\n";
echo "【判定不同片】对数(约): {$blockPairCount}（不会合并）\n\n";

if ($mode === 'dry') {
    echo "======== A. 确定合并（仅这些会在 merge 时写入，最多 {$show}）========\n";
    if (!$previewMerge) {
        echo "（无）— 说明当前档位下没有「证据足够」的重复，这是正常且安全的。\n";
    }
    $i = 0;
    foreach ($previewMerge as $p) {
        $i++;
        echo "\n#{$i} 保留 #{$p['keep_id']} 「{$p['title']}」 ← 合并 " . count($p['remove_ids']) . " 条\n";
        echo "   证据: {$p['reason']}\n";
        echo "   合并后线路: {$p['play_from']}\n";
        foreach ($p['members'] as $m) {
            $mark = ((int)$m['vod_id'] === (int)$p['keep_id']) ? 'KEEP' : 'DEL ';
            $pic = coverKey($m['vod_pic'] ?? '');
            echo "   [{$mark}] #{$m['vod_id']} year={$m['vod_year']}"
                . " area/lang(仅参考)=" . short(refAreaLang($m), 24)
                . " dir=" . short($m['vod_director'], 16)
                . " actor=" . short($m['vod_actor'], 20)
                . " pic=" . ($pic !== '' ? short($pic, 28) : '-')
                . " from={$m['vod_play_from']}\n";
        }
    }
    if ($mergeGroupCount > count($previewMerge)) {
        echo "\n... 其余 " . ($mergeGroupCount - count($previewMerge)) . " 组已计入总数\n";
    }

    echo "\n======== B. 存疑（同名但证据不足，绝不自动合并）========\n";
    if (!$previewUnsure) {
        echo "（无样例）\n";
    }
    foreach ($previewUnsure as $s) {
        echo "- #{$s['a']} vs #{$s['b']} 「{$s['title']}」 score={$s['score']} | {$s['why']}\n";
    }

    echo "\n======== C. 判定为不同作品（强制不合并）========\n";
    if (!$previewBlock) {
        echo "（无样例）\n";
    }
    foreach ($previewBlock as $s) {
        echo "- #{$s['a']} vs #{$s['b']} 「{$s['title']}」 | {$s['why']}\n";
    }

    echo "\n--------\n";
    echo "请人工抽查 A 列表。确认无误后再：\n";
    echo "?key=密钥&mode=merge&level={$level}&confirm=YES\n";
    echo "重要：B/C 不会被 merge。不要用 loose 档处理正式库。\n";
    exit(0);
}

echo "\n完成：合并组 {$mergedOk}，删除重复约 {$deleteCount} 条。\n";
echo "请到后台：系统 → 缓存清理。用完请删除本 PHP。\n";
exit(0);

// ----------------- flow helpers -----------------

function handleCluster(
    $cluster,
    $mode,
    $show,
    $cfg,
    $cols,
    $pdo,
    $table,
    &$mergeGroupCount,
    &$deleteCount,
    &$previewMerge,
    &$mergedOk
) {
    $plan = buildMergePlan($cluster);
    $mergeGroupCount++;
    $deleteCount += count($plan['remove_ids']);
    if ($mode === 'dry') {
        if (count($previewMerge) < $show) {
            $plan['members'] = slimMembers($plan['members']);
            $plan['play_url'] = '';
            $previewMerge[] = $plan;
        }
    } else {
        applyMergePlan($pdo, $table, $cols, $plan);
        $mergedOk++;
        if ($mergedOk <= 30 || $mergedOk % 100 === 0) {
            echo "已合并 #{$plan['keep_id']} 「{$plan['title']}」删 " . count($plan['remove_ids']) . " 条\n";
            flush_merge();
        }
    }
}

function keyAllowed($key)
{
    if ($key === '') {
        return false;
    }
    foreach (SECRET_KEYS as $ok) {
        if (hash_equals($ok, $key)) {
            return true;
        }
    }
    return false;
}

/** 语言/地区仅展示：很多源站会把国语写进地区、把中国大陆写进语言 */
function refAreaLang($m)
{
    $area = trim((string)($m['vod_area'] ?? ''));
    $lang = trim((string)($m['vod_lang'] ?? ''));
    if ($area === '' && $lang === '') {
        return '-';
    }
    if ($area === '') {
        return $lang;
    }
    if ($lang === '') {
        return $area;
    }
    if ($area === $lang) {
        return $area;
    }
    return $area . '/' . $lang;
}

function flush_merge()
{
    if (function_exists('ob_flush')) {
        @ob_flush();
    }
    @flush();
}

function loadRowsByIds(PDO $pdo, $table, $metaSql, $ids)
{
    $ids = array_values(array_unique(array_map('intval', $ids)));
    $out = [];
    foreach (array_chunk($ids, 200) as $chunk) {
        $in = implode(',', $chunk);
        foreach ($pdo->query("SELECT {$metaSql} FROM `{$table}` WHERE `vod_id` IN ({$in})")->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $out[] = $r;
        }
    }
    return $out;
}

function slimMembers($members)
{
    $out = [];
    foreach ($members as $m) {
        $out[] = [
            'vod_id' => $m['vod_id'],
            'vod_name' => $m['vod_name'],
            'vod_year' => isset($m['vod_year']) ? $m['vod_year'] : '',
            'vod_lang' => isset($m['vod_lang']) ? $m['vod_lang'] : '',
            'vod_director' => isset($m['vod_director']) ? $m['vod_director'] : '',
            'vod_actor' => isset($m['vod_actor']) ? short($m['vod_actor'], 40) : '',
            'vod_class' => isset($m['vod_class']) ? short($m['vod_class'], 40) : '',
            'vod_play_from' => isset($m['vod_play_from']) ? $m['vod_play_from'] : '',
            'vod_pic' => isset($m['vod_pic']) ? $m['vod_pic'] : '',
            'vod_play_url' => '',
            'vod_hits' => isset($m['vod_hits']) ? $m['vod_hits'] : 0,
            'vod_remarks' => isset($m['vod_remarks']) ? short($m['vod_remarks'], 20) : '',
            'vod_total' => isset($m['vod_total']) ? $m['vod_total'] : 0,
        ];
    }
    return $out;
}

function applyMergePlan(PDO $pdo, $table, $cols, $plan)
{
    $upd = $pdo->prepare("UPDATE `{$table}` SET `vod_play_from` = ?, `vod_play_url` = ? WHERE `vod_id` = ?");
    $upd->execute([$plan['play_from'], $plan['play_url'], $plan['keep_id']]);

    $keep = null;
    foreach ($plan['members'] as $m) {
        if ((int)$m['vod_id'] === (int)$plan['keep_id']) {
            $keep = $m;
            break;
        }
    }
    if ($keep !== null) {
        fillEmptyMeta($pdo, $table, $cols, $keep, $plan['members']);
    }
    if ($plan['remove_ids']) {
        $in = implode(',', array_map('intval', $plan['remove_ids']));
        $pdo->exec("DELETE FROM `{$table}` WHERE `vod_id` IN ({$in})");
    }
}

function printRulesHelp($level, $cfg)
{
    echo "规则档 {$level}：\n";
    echo "  【不参与判定】语言、地区（可为空、可写反，如国语/中国大陆）— 仅预览参考\n";
    echo "  【可合并差异】扩展分类 / 备注 / 线路不同；一侧字段为空不算冲突\n";
    echo "  【强制不合并】年份差≥2；导演都有且无交集"
        . ($cfg['block_zero_actor'] ? '；主演都有且完全无交集' : '') . "\n";
    echo "  【强证据】至少其一: 同年份 / 导演交集 / 主演明显重叠 / 封面一致\n";
    echo "  【仅同名】" . ($cfg['allow_name_only'] ? '允许（危险）' : '绝不合并 → 列入存疑') . "\n";
    echo "  【封面】一致=强证据；不同且无其它强证据 → 不合并\n";
    echo "  合并阈值 ≥ {$cfg['merge']}，且通过强证据门闩\n\n";
}

// ----------------- judgment -----------------

/**
 * @return array{verdict:string,score:int,why:string,strong:list<string>}
 */
function judgePair($a, $b, $cfg)
{
    $score = 30; // 同归一化名
    $why = [];
    $strong = [];
    $hardBlock = false;

    $ea = editionTag($a['vod_name'] ?? '');
    $eb = editionTag($b['vod_name'] ?? '');
    $pa = partTag($a['vod_name'] ?? '');
    $pb = partTag($b['vod_name'] ?? '');
    if ($pa !== $pb) {
        $la = $pa === 'full' ? '全本/未标分卷' : $pa;
        $lb = $pb === 'full' ? '全本/未标分卷' : $pb;
        return [
            'verdict' => 'block',
            'score' => 0,
            'why' => "分卷不同({$la}/{$lb})，不合并",
            'strong' => [],
        ];
    }
    if ($ea !== $eb) {
        return [
            'verdict' => 'block',
            'score' => 0,
            'why' => '版本不同(' . ($ea !== '' ? $ea : '默认版') . '/' . ($eb !== '' ? $eb : '默认版') . ')，不合并',
            'strong' => [],
        ];
    }

    if (mediaKindConflict($a, $b)) {
        return [
            'verdict' => 'block',
            'score' => 0,
            'why' => '不同类型内容冲突（电影/电视剧/短剧/综艺/动漫等），不合并',
            'strong' => [],
        ];
    }

    // ---- 年份 ----
    $ya = yearNum($a);
    $yb = yearNum($b);
    if ($ya > 0 && $yb > 0) {
        $diff = abs($ya - $yb);
        if ($diff === 0) {
            $score += 30;
            $strong[] = "同年:{$ya}";
        } elseif ($diff === 1) {
            $score += 5;
            $why[] = "年份差1({$ya}/{$yb})";
            // 年份差 1 不算强证据，可能是上映/收录差
        } else {
            $why[] = "年份冲突:{$ya}/{$yb}";
            if ($cfg['hard_block_year']) {
                return ['verdict' => 'block', 'score' => 0, 'why' => implode('; ', $why), 'strong' => []];
            }
            $score -= 50;
            $hardBlock = true;
        }
    }

    // ---- 导演 ----
    $da = peopleSet($a['vod_director'] ?? '');
    $db = peopleSet($b['vod_director'] ?? '');
    if ($da && $db) {
        $inter = array_intersect($da, $db);
        if ($inter) {
            $score += 35;
            $strong[] = '导演:' . implode(',', array_slice($inter, 0, 3));
        } else {
            $why[] = '导演不同:' . short(implode(',', $da), 12) . '/' . short(implode(',', $db), 12);
            return ['verdict' => 'block', 'score' => 0, 'why' => implode('; ', $why), 'strong' => []];
        }
    }

    // ---- 主演 ----
    $aa = peopleSet($a['vod_actor'] ?? '');
    $ab = peopleSet($b['vod_actor'] ?? '');
    if ($aa && $ab) {
        $inter = array_intersect($aa, $ab);
        $ic = count($inter);
        $min = min(count($aa), count($ab));
        if ($ic === 0) {
            $why[] = '主演无交集';
            if ($cfg['block_zero_actor'] && count($aa) >= 2 && count($ab) >= 2) {
                return ['verdict' => 'block', 'score' => 0, 'why' => implode('; ', $why), 'strong' => []];
            }
            $score -= 30;
        } elseif ($ic >= 2 || ($min > 0 && $ic / $min >= 0.4)) {
            $score += 30;
            $strong[] = '主演重叠:' . implode(',', array_slice($inter, 0, 4));
        } elseif ($ic === 1) {
            $score += 10;
            $why[] = '主演仅1人重合';
            // 单人重合不算强证据（同名配角常见）
        }
    }

    // ---- 封面 ----
    $ca = coverInfo($a['vod_pic'] ?? '');
    $cb = coverInfo($b['vod_pic'] ?? '');
    $coverRel = compareCover($ca, $cb);
    if ($coverRel === 'same') {
        $score += 40;
        $strong[] = '封面一致';
    } elseif ($coverRel === 'diff') {
        $why[] = '封面不同';
        if (!empty($cfg['cover_mismatch_needs_other'])) {
            // 封面冲突时：若没有其它强证据，直接存疑/不合并
            // （强证据在后面统一门闩；这里先减分）
            $score -= 15;
        }
    }

    // ---- 集数 ----
    $ta = (int)($a['vod_total'] ?? 0);
    $tb = (int)($b['vod_total'] ?? 0);
    if ($ta > 0 && $tb > 0) {
        if ($ta === $tb) {
            $score += 8;
        } elseif (abs($ta - $tb) >= 10 && max($ta, $tb) >= 10) {
            $score -= 20;
            $why[] = "集数差大:{$ta}/{$tb}";
        }
    }

    // 元数据空 = 未知，不是冲突。只有「两边都几乎没证据」才略降分并倾向存疑
    $richA = metaRichness($a) + ($ca['key'] !== '' ? 1 : 0);
    $richB = metaRichness($b) + ($cb['key'] !== '' ? 1 : 0);
    if ($richA === 0 && $richB === 0) {
        $why[] = '双方关键字段为空(年/导/演/封面)，仅同名不足以合并';
        $score -= 10;
    } elseif ($richA === 0 || $richB === 0) {
        // 一侧空一侧有：不扣分，靠有的一侧 + 封面等证据；空侧不构成冲突
        $why[] = '一侧关键字段为空(忽略，不视为冲突)';
    }

    if ($hardBlock) {
        return ['verdict' => 'block', 'score' => $score, 'why' => implode('; ', $why) ?: '硬冲突', 'strong' => $strong];
    }

    // 强证据门闩
    if (!empty($cfg['require_strong']) && !$strong) {
        $why[] = '缺少强证据(年/导/演/封面)；语言地区不计入';
        return [
            'verdict' => 'unsure',
            'score' => $score,
            'why' => implode('; ', $why) ?: '证据不足',
            'strong' => [],
        ];
    }

    // 封面冲突 + 要求其它强证据：若强证据里只有「封面」以外的还好；若封面是 diff 且 strong 为空已在上面；
    // 若封面 diff 且 strong 仅有弱项——已由 require_strong 处理。
    // 额外：封面明确不同，且强证据只有「同年」而主演/导演都空 → 仍可能是同名同年不同片，safe 再抬高
    if ($coverRel === 'diff' && !empty($cfg['cover_mismatch_needs_other'])) {
        $nonCoverStrong = array_filter($strong, function ($s) {
            return strpos($s, '封面') === false;
        });
        if (!$nonCoverStrong) {
            $why[] = '封面不同且无其它强证据';
            return ['verdict' => 'unsure', 'score' => $score, 'why' => implode('; ', $why), 'strong' => $strong];
        }
        // 若只有「同年」一项强证据 + 封面不同 → safe 视为存疑
        if (count($nonCoverStrong) === 1 && strpos(reset($nonCoverStrong), '同年') === 0 && empty($da) && empty($db) && empty($aa) && empty($ab)) {
            $why[] = '仅同年+封面不同，可能同名同岁不同片';
            return ['verdict' => 'unsure', 'score' => $score, 'why' => implode('; ', $why), 'strong' => $strong];
        }
    }

    if (!$cfg['allow_name_only'] && !$strong) {
        return ['verdict' => 'unsure', 'score' => $score, 'why' => '仅同名', 'strong' => []];
    }

    if ($score >= $cfg['merge'] && $strong) {
        return [
            'verdict' => 'merge',
            'score' => $score,
            'why' => implode('; ', $strong) . ($why ? ' | ' . implode('; ', $why) : ''),
            'strong' => $strong,
        ];
    }

    if ($score >= $cfg['merge'] && $cfg['allow_name_only']) {
        return ['verdict' => 'merge', 'score' => $score, 'why' => '分数达标(loose)', 'strong' => $strong];
    }

    return [
        'verdict' => 'unsure',
        'score' => $score,
        'why' => implode('; ', $why) ?: ('分数不足:' . $score),
        'strong' => $strong,
    ];
}

function collectPairNotes($rows, $cfg)
{
    $block = 0;
    $unsure = 0;
    $unsureSamples = [];
    $blockSamples = [];
    $n = count($rows);
    $maxPairs = min(80, (int)(($n * ($n - 1)) / 2));
    $seen = 0;
    for ($i = 0; $i < $n; $i++) {
        for ($j = $i + 1; $j < $n; $j++) {
            $jdg = judgePair($rows[$i], $rows[$j], $cfg);
            if ($jdg['verdict'] === 'block') {
                $block++;
                if (count($blockSamples) < 30) {
                    $blockSamples[] = [
                        'a' => (int)$rows[$i]['vod_id'],
                        'b' => (int)$rows[$j]['vod_id'],
                        'title' => (string)$rows[$i]['vod_name'],
                        'why' => $jdg['why'],
                    ];
                }
            } elseif ($jdg['verdict'] === 'unsure') {
                $unsure++;
                if (count($unsureSamples) < 30) {
                    $unsureSamples[] = [
                        'a' => (int)$rows[$i]['vod_id'],
                        'b' => (int)$rows[$j]['vod_id'],
                        'title' => (string)$rows[$i]['vod_name'],
                        'score' => $jdg['score'],
                        'why' => $jdg['why'],
                    ];
                }
            }
            $seen++;
            if ($seen >= $maxPairs) {
                break 2;
            }
        }
    }
    return [
        'block' => $block,
        'unsure' => $unsure,
        'unsure_samples' => $unsureSamples,
        'block_samples' => $blockSamples,
    ];
}

function clusterRows($rows, $cfg)
{
    $n = count($rows);
    $parent = range(0, $n - 1);
    $find = function ($x) use (&$parent, &$find) {
        if ($parent[$x] !== $x) {
            $parent[$x] = $find($parent[$x]);
        }
        return $parent[$x];
    };
    $union = function ($a, $b) use (&$parent, $find) {
        $ra = $find($a);
        $rb = $find($b);
        if ($ra !== $rb) {
            $parent[$rb] = $ra;
        }
    };

    for ($i = 0; $i < $n; $i++) {
        for ($j = $i + 1; $j < $n; $j++) {
            $jdg = judgePair($rows[$i], $rows[$j], $cfg);
            if ($jdg['verdict'] === 'merge') {
                $union($i, $j);
            }
        }
    }

    $groups = [];
    for ($i = 0; $i < $n; $i++) {
        $r = $find($i);
        if (!isset($groups[$r])) {
            $groups[$r] = [];
        }
        $groups[$r][] = $rows[$i];
    }
    return array_values($groups);
}

/** 并查集传递后，要求簇内任意两两都是 merge，否则不安全 */
function clusterFullyCompatible($cluster, $cfg)
{
    $n = count($cluster);
    for ($i = 0; $i < $n; $i++) {
        for ($j = $i + 1; $j < $n; $j++) {
            $jdg = judgePair($cluster[$i], $cluster[$j], $cfg);
            if ($jdg['verdict'] !== 'merge') {
                return false;
            }
        }
    }
    return true;
}

/**
 * 从簇中提取「确定可合并」的互斥 pair（每个 id 最多出现一次），避免传递误并。
 * @return list<list<array>>
 */
function extractSafePairs($cluster, $cfg)
{
    $n = count($cluster);
    $edges = [];
    for ($i = 0; $i < $n; $i++) {
        for ($j = $i + 1; $j < $n; $j++) {
            $jdg = judgePair($cluster[$i], $cluster[$j], $cfg);
            if ($jdg['verdict'] === 'merge') {
                $edges[] = ['i' => $i, 'j' => $j, 'score' => $jdg['score']];
            }
        }
    }
    usort($edges, function ($a, $b) {
        return $b['score'] <=> $a['score'];
    });
    $used = [];
    $pairs = [];
    foreach ($edges as $e) {
        if (isset($used[$e['i']]) || isset($used[$e['j']])) {
            continue;
        }
        $used[$e['i']] = true;
        $used[$e['j']] = true;
        $pairs[] = [$cluster[$e['i']], $cluster[$e['j']]];
    }
    return $pairs;
}

function normalizeTitle($name)
{
    $s = trim($name);
    $s = preg_replace('/\s+/u', '', $s);
    $s = str_replace(['　'], '', $s);
    $part = 'full';
    if (preg_match('/[（(【\[]\s*(上篇|中篇|下篇|上部|中部|下部|前篇|后篇|上|中|下|全集|全)\s*[）)】\]]/u', $s, $m)) {
        $part = ($m[1] === '全集' || $m[1] === '全') ? 'full' : $m[1];
        $s = preg_replace('/[（(【\[]\s*(上篇|中篇|下篇|上部|中部|下部|前篇|后篇|上|中|下|全集|全)\s*[）)】\]]/u', '', $s);
    }
    $s = preg_replace('/(上篇|中篇|下篇|上部|中部|下部)$/u', '', $s);
    $s = preg_replace('/[《》【】\[\]（）()·・\.\,，。！!？?\-—_：:]/u', '', $s);
    do {
        $prev = $s;
        $s = preg_replace('/(全\d+集|更新至.+$|更至.+$|高清|蓝光|超清|4k|4K|HD|hd)$/u', '', $s);
        $s = preg_replace('/(?<!极)完结$/u', '', $s);
    } while ($s !== $prev && $s !== '');
    return mb_strtolower($s, 'UTF-8') . '#part:' . $part . '#';
}

function partTag($name)
{
    $s = preg_replace('/\s+/u', '', (string)$name);
    if (preg_match('/[（(【\[]\s*(上篇|中篇|下篇|上部|中部|下部|前篇|后篇|上|中|下|全集|全)\s*[）)】\]]/u', $s, $m)) {
        $p = $m[1];
        return ($p === '全集' || $p === '全') ? 'full' : $p;
    }
    if (preg_match('/(上篇|中篇|下篇|上部|中部|下部)$/u', $s, $m)) {
        return $m[1];
    }
    return 'full';
}

function editionTag($name)
{
    $s = preg_replace('/\s+/u', '', (string)$name);
    $s = preg_replace('/[（(【\[]\s*(上|中|下|上篇|中篇|下篇|上部|中部|下部|前篇|后篇|全集|全)\s*[）)】\]]/u', '', $s);
    $tags = [
        '国语版', '粤语版', '英语版', '日语版', '韩语版', '越南语版', '泰语版',
        '法语版', '德语版', '俄语版', '双语版', '配音版', '原声版', '中字版', '无字版',
        '剧场版', '电视版', 'TV版', '未删减版', '加长版', '导演剪辑版',
        '国语', '粤语', '中字', '无字', '双语',
    ];
    foreach ($tags as $tag) {
        if (mb_stripos($s, $tag) !== false) {
            return mb_strtolower($tag, 'UTF-8');
        }
    }
    return '';
}

/** @return 'movie'|'series'|'short'|'variety'|'anime'|'doc'|'comic'|'unknown' */
function mediaKind($row)
{
    // 与 merge_lib 对齐的精简版（文本+集数）；完整分类树在 UI 扫描里更准
    $blob = trim(
        (string)($row['vod_class'] ?? '') . ' ' .
        (string)($row['vod_remarks'] ?? '') . ' ' .
        (string)($row['vod_name'] ?? '')
    );
    $rules = [
        'short' => '/短剧|微短剧|竖屏|抖音剧|快手剧|小程序剧/u',
        'anime' => '/动漫|动画|卡通|番剧|国漫|日漫/u',
        'variety' => '/综艺|真人秀|晚会|访谈|选秀|脱口秀/u',
        'doc' => '/纪录片|纪录/u',
        'comic' => '/漫画|有声漫画|动态漫/u',
        'movie' => '/电影|影片|院线|剧场版|微电影/u',
        'series' => '/连续剧|电视剧|电视连续剧|网剧|日剧|韩剧|美剧|台剧|港剧|英剧|泰剧|剧集/u',
    ];
    foreach ($rules as $kind => $re) {
        if (preg_match($re, $blob)) {
            return $kind;
        }
    }
    $eps = max((int)($row['vod_total'] ?? 0), (int)($row['vod_serial'] ?? 0));
    if ($eps === 1) {
        return 'movie';
    }
    return 'unknown';
}

function mediaKindConflict($a, $b)
{
    $ka = mediaKind($a);
    $kb = mediaKind($b);
    if ($ka !== 'unknown' && $kb !== 'unknown' && $ka !== $kb) {
        return true;
    }
    // 不同 type_id 且都能读到时：保守拦截（文本版无法解析根分类时靠 type_id）
    $ta = isset($a['type_id']) ? (int)$a['type_id'] : 0;
    $tb = isset($b['type_id']) ? (int)$b['type_id'] : 0;
    if ($ta > 0 && $tb > 0 && $ta !== $tb) {
        // 仅当至少一方已识别出形态且不同，或集数冲突；纯同频道子类不同不拦
        // 这里无法知根分类，用形态+集数
    }
    $ea = max((int)($a['vod_total'] ?? 0), (int)($a['vod_serial'] ?? 0));
    $eb = max((int)($b['vod_total'] ?? 0), (int)($b['vod_serial'] ?? 0));
    if ($ea > 0 && $eb > 0 && (($ea <= 1 && $eb >= 5) || ($eb <= 1 && $ea >= 5))) {
        return true;
    }
    return false;
}

function yearNum($row)
{
    $y = preg_replace('/\D+/', '', (string)($row['vod_year'] ?? ''));
    if ($y === '') {
        return 0;
    }
    $y = (int)substr($y, 0, 4);
    return ($y >= 1900 && $y <= 2100) ? $y : 0;
}

function peopleSet($s)
{
    $s = str_replace(['/', '|', '、', '，', ';', '；'], ',', $s);
    $parts = preg_split('/,+/', $s);
    $out = [];
    foreach ($parts as $p) {
        $p = preg_replace('/\s+/u', '', trim($p));
        if ($p === '' || mb_strlen($p, 'UTF-8') < 2) {
            continue;
        }
        // 去掉常见职位后缀
        $p = preg_replace('/(饰|配音|主演|导演)$/u', '', $p);
        if ($p === '') {
            continue;
        }
        $out[mb_strtolower($p, 'UTF-8')] = true;
    }
    return array_keys($out);
}

function metaRichness($row)
{
    $n = 0;
    if (yearNum($row) > 0) {
        $n++;
    }
    if (trim((string)($row['vod_director'] ?? '')) !== '') {
        $n++;
    }
    if (trim((string)($row['vod_actor'] ?? '')) !== '') {
        $n++;
    }
    return $n;
}

/**
 * @return array{url:string,path:string,key:string,base:string,stem:string}
 */
function coverInfo($pic)
{
    $pic = trim((string)$pic);
    if ($pic === '') {
        return ['url' => '', 'path' => '', 'key' => '', 'base' => '', 'stem' => ''];
    }
    $raw = preg_replace('/[?#].*$/', '', $pic);
    $raw = str_replace('\\', '/', $raw);
    $path = $raw;
    if (preg_match('#^https?://#i', $raw)) {
        $path = (string)(parse_url($raw, PHP_URL_PATH) ?: '');
    }
    $path = strtolower($path);
    $path = preg_replace('#/+#', '/', $path);
    $path = preg_replace('#/(?:thumb|thumbs|small|poster|resize|pic|imgs?|w\d+|h\d+|\d{2,4}x\d{2,4})(?=/|$)#i', '', $path);
    $path = preg_replace('#/+#', '/', $path);
    $path = '/' . ltrim($path, '/');

    $base = basename($path);
    $stem = pathinfo($base, PATHINFO_FILENAME);
    $stem = preg_replace('/([_-]\d{2,4}x\d{2,4}|_-?\d{2,4}|_(?:small|thumb|poster|large|big|min|max))$/i', '', $stem);
    $ext = strtolower(pathinfo($base, PATHINFO_EXTENSION));
    if ($ext === 'jpeg') {
        $ext = 'jpg';
    }
    $key = $stem . ($ext !== '' ? '.' . $ext : '');
    return [
        'url' => strtolower($raw),
        'path' => $path,
        'key' => $key,
        'base' => $base,
        'stem' => strtolower($stem),
    ];
}

function coverKey($pic)
{
    $c = coverInfo($pic);
    return $c['key'] !== '' ? $c['key'] : $c['url'];
}

function coverStemHashy($stem)
{
    $stem = strtolower((string)$stem);
    if ($stem === '') {
        return false;
    }
    if (strlen($stem) >= 16 && preg_match('/^[a-f0-9]+$/', $stem)) {
        return true;
    }
    if (strlen($stem) >= 18 && preg_match('/^[a-z0-9_-]+$/', $stem)
        && preg_match('/[a-z]/', $stem) && preg_match('/\d/', $stem)
        && !preg_match('/(poster|cover|vod|movie|film|img)/', $stem)) {
        return true;
    }
    return false;
}

/** @return 'same'|'diff'|'unknown' */
function compareCover($ca, $cb)
{
    if ($ca['stem'] === '' || $cb['stem'] === '') {
        return 'unknown';
    }
    if ($ca['url'] !== '' && $ca['url'] === $cb['url']) {
        return 'same';
    }
    if ($ca['path'] !== '' && $ca['path'] === $cb['path'] && $ca['path'] !== '/') {
        return 'same';
    }
    if ($ca['key'] !== '' && $ca['key'] === $cb['key']) {
        return 'same';
    }
    if ($ca['stem'] !== '' && $ca['stem'] === $cb['stem']) {
        return 'same';
    }
    $sa = $ca['stem'];
    $sb = $cb['stem'];
    if (strlen($sa) >= 8 && strlen($sb) >= 8) {
        if (strpos($sa, $sb) !== false || strpos($sb, $sa) !== false) {
            return 'same';
        }
    }
    $na = preg_replace('/(?:[-_]?(?:copy|副本|拷贝|\(\d+\)|（\d+）|\d+))$/u', '', $sa);
    $nb = preg_replace('/(?:[-_]?(?:copy|副本|拷贝|\(\d+\)|（\d+）|\d+))$/u', '', $sb);
    if ($na !== '' && $na === $nb) {
        return 'same';
    }
    // 哈希文件名不同：不能断定封面不同
    if (coverStemHashy($sa) && coverStemHashy($sb) && $sa !== $sb) {
        return 'unknown';
    }
    return 'diff';
}

function buildMergePlan($cluster)
{
    usort($cluster, function ($a, $b) {
        return keepScore($b) <=> keepScore($a);
    });
    $keep = $cluster[0];
    $keepId = (int)$keep['vod_id'];
    $merged = mergePlaySources($cluster);
    $remove = [];
    foreach ($cluster as $r) {
        $id = (int)$r['vod_id'];
        if ($id !== $keepId) {
            $remove[] = $id;
        }
    }

    // 汇总簇内证据（用 keep 与其余的判决）
    $evidence = [];
    for ($i = 1; $i < count($cluster); $i++) {
        $j = judgePair($keep, $cluster[$i], [
            'merge' => 0,
            'hard_block_year' => true,
            'require_strong' => false,
            'block_zero_actor' => false,
            'allow_name_only' => true,
            'cover_mismatch_needs_other' => false,
        ]);
        foreach ($j['strong'] as $s) {
            $evidence[$s] = true;
        }
    }

    return [
        'keep_id' => $keepId,
        'title' => (string)$keep['vod_name'],
        'remove_ids' => $remove,
        'play_from' => $merged['from'],
        'play_url' => $merged['url'],
        'reason' => $evidence ? implode('；', array_keys($evidence)) : '强证据簇',
        'members' => $cluster,
    ];
}

function keepScore($row)
{
    $s = 0;
    $from = strtolower((string)($row['vod_play_from'] ?? ''));
    $url = strtolower((string)($row['vod_play_url'] ?? ''));
    if (strpos($from, 'm3u8') !== false || strpos($url, '.m3u8') !== false) {
        $s += 1000;
    }
    $lines = $from === '' ? 0 : (substr_count($from, '$$$') + 1);
    $s += $lines * 50;
    $s += min(200, (int)($row['vod_hits'] ?? 0) / 10);
    if (trim($url) !== '') {
        $s += 20;
    }
    // 元数据更全的优先保留
    $s += metaRichness($row) * 15;
    if (trim((string)($row['vod_pic'] ?? '')) !== '') {
        $s += 10;
    }
    $s += (int)$row['vod_id'] / 1000000.0;
    return $s;
}

function mergePlaySources($rows)
{
    $map = [];
    foreach ($rows as $r) {
        $froms = explode('$$$', (string)$r['vod_play_from']);
        $urls = explode('$$$', (string)$r['vod_play_url']);
        $n = max(count($froms), count($urls));
        for ($i = 0; $i < $n; $i++) {
            $f = trim(isset($froms[$i]) ? $froms[$i] : '');
            $u = trim(isset($urls[$i]) ? $urls[$i] : '');
            if ($f === '' && $u === '') {
                continue;
            }
            if ($f === '') {
                $f = 'default';
            }
            if (!isset($map[$f]) || strlen($u) > strlen($map[$f])) {
                $map[$f] = $u;
            }
        }
    }
    uksort($map, function ($a, $b) {
        return linePriority($b) <=> linePriority($a);
    });
    return [
        'from' => implode('$$$', array_keys($map)),
        'url' => implode('$$$', array_values($map)),
    ];
}

function linePriority($from)
{
    $f = strtolower($from);
    if (strpos($f, 'm3u8') !== false) {
        return 100;
    }
    if (in_array($f, ['qiyi', 'qq', 'youku'], true) || strpos($f, 'iqiyi') !== false) {
        return 10;
    }
    return 50;
}

function fillEmptyMeta($pdo, $table, $cols, $keep, $members)
{
    $fields = ['vod_year', 'vod_area', 'vod_lang', 'vod_actor', 'vod_director', 'vod_pic', 'vod_class', 'vod_remarks'];
    $sets = [];
    $vals = [];
    foreach ($fields as $f) {
        if (!in_array($f, $cols, true)) {
            continue;
        }
        if (trim((string)($keep[$f] ?? '')) !== '') {
            continue;
        }
        foreach ($members as $m) {
            if ((int)$m['vod_id'] === (int)$keep['vod_id']) {
                continue;
            }
            $v = trim((string)($m[$f] ?? ''));
            if ($v !== '') {
                $sets[] = "`{$f}` = ?";
                $vals[] = $v;
                break;
            }
        }
    }
    if (!$sets) {
        return;
    }
    $vals[] = (int)$keep['vod_id'];
    $pdo->prepare('UPDATE `' . $table . '` SET ' . implode(',', $sets) . ' WHERE vod_id = ?')->execute($vals);
}

function short($s, $n)
{
    $s = trim((string)$s);
    if ($s === '') {
        return '-';
    }
    if (mb_strlen($s, 'UTF-8') <= $n) {
        return $s;
    }
    return mb_substr($s, 0, $n, 'UTF-8') . '…';
}

function findMacRootLocal($start)
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

function loadDbConfigLocal($root)
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
