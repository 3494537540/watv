<?php
/**
 * 合并工具共享库（供 merge_vod_ui.php 使用）
 * PHP 7.2+
 */
declare(strict_types=1);

function mergeKeyAllowed($key)
{
    $keys = ['huihuo_merge_2026', 'huihuo_dedupe_2026', 'huihuo_type_2026'];
    if ($key === '') {
        return false;
    }
    foreach ($keys as $ok) {
        if (hash_equals($ok, $key)) {
            return true;
        }
    }
    return false;
}

function mergeLevelCfg($level)
{
    $level = strtolower((string)$level);
    $all = [
        'safe' => [
            'merge' => 80,
            'hard_block_year' => true,
            'require_strong' => true,
            'block_zero_actor' => true,
            'allow_name_only' => false,
            'cover_mismatch_needs_other' => true,
            // 双方都有封面且不一致 → 一律进「待确认」，左侧只留最匹配
            'cover_diff_to_unsure' => true,
        ],
        'strict' => [
            'merge' => 70,
            'hard_block_year' => true,
            'require_strong' => true,
            'block_zero_actor' => true,
            'allow_name_only' => false,
            'cover_mismatch_needs_other' => true,
            'cover_diff_to_unsure' => true,
        ],
        'normal' => [
            'merge' => 55,
            'hard_block_year' => true,
            'require_strong' => false,
            'block_zero_actor' => false,
            'allow_name_only' => false,
            'cover_mismatch_needs_other' => false,
            'cover_diff_to_unsure' => true,
        ],
        'loose' => [
            'merge' => 40,
            'hard_block_year' => false,
            'require_strong' => false,
            'block_zero_actor' => false,
            'allow_name_only' => true,
            'cover_mismatch_needs_other' => false,
            'cover_diff_to_unsure' => false,
        ],
    ];
    return isset($all[$level]) ? $all[$level] : $all['safe'];
}

function mergeConnect($startDir)
{
    $bootstrap = $startDir . '/mac_bootstrap.php';
    if (!is_file($bootstrap)) {
        $bootstrap = $startDir . '/backups/mac_bootstrap.php';
    }
    if (is_file($bootstrap)) {
        require_once $bootstrap;
        $root = macFindRoot($startDir);
        if ($root === null) {
            throw new RuntimeException('找不到 CMS 根目录');
        }
        $pdo = macPdo($root);
        $prefix = macTypeTable($root)['prefix'];
        return [$pdo, $root, $prefix . 'vod'];
    }
    throw new RuntimeException('缺少 mac_bootstrap.php');
}

function mergeMetaSql(PDO $pdo, $table)
{
    $cols = array_column($pdo->query('SHOW COLUMNS FROM `' . str_replace('`', '', $table) . '`')->fetchAll(), 'Field');
    $want = [
        'vod_id', 'vod_name', 'type_id', 'vod_class', 'vod_year', 'vod_area', 'vod_lang',
        'vod_actor', 'vod_director', 'vod_remarks', 'vod_total', 'vod_serial',
        'vod_play_from', 'vod_play_url', 'vod_pic', 'vod_score', 'vod_hits', 'vod_time',
    ];
    $metaCols = array_values(array_intersect($want, $cols));
    $sql = implode(',', array_map(function ($c) {
        return '`' . $c . '`';
    }, $metaCols));
    return [$metaCols, $sql, $cols];
}

function mergeLoadByIds(PDO $pdo, $table, $metaSql, $ids)
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

/**
 * 片名归一化（用于找「同名组」）
 * 保留语种版本、分卷（上/中/下）、季数；
 * 只去掉标点噪声和清晰度/更新状态。
 *
 * 注意：无「（下）」与带「（下）」必须是不同 key，否则会把上下部误并。
 */
function mergeNormalizeTitle($name)
{
    $s = trim((string)$name);
    $s = preg_replace('/\s+/u', '', $s);
    $s = str_replace(['　'], '', $s);

    // 先抽出分卷标记并固化进 key（避免去掉括号后「下」粘在片名上仍和「全本」纠缠不清）
    $part = mergePartTag($s);
    $s = preg_replace('/[（(【\[]\s*(上|中|下|上篇|中篇|下篇|上部|中部|下部|前篇|后篇|全集|全)\s*[）)】\]]/u', '', $s);
    // 片名末尾紧贴的 上篇/下篇 等
    $s = preg_replace('/(上篇|中篇|下篇|上部|中部|下部)$/u', '', $s);

    // 去掉书名号等噪声标点（括号内分卷已处理）
    $s = preg_replace('/[《》【】\[\]（）()·・\.\,，。！!？?\-—_：:]/u', '', $s);

    // 仅剥离清晰度 / 更新状态（不要剥「完结篇」里的语义时尽量保守：只剥末尾独立「完结」）
    do {
        $prev = $s;
        $s = preg_replace('/(全\d+集|更新至.+$|更至.+$|高清|蓝光|超清|4k|4K|HD|hd)$/u', '', $s);
        // 「完结」仅当整段以完结尾、且前面不是「终极」等词的一部分——用独立后缀
        $s = preg_replace('/(?<!极)完结$/u', '', $s);
    } while ($s !== $prev && $s !== '');

    $key = mb_strtolower($s, 'UTF-8');
    // 分卷写入 key：全本 / 上 / 中 / 下 …
    $key .= '#part:' . $part . '#';
    return $key;
}

/**
 * 分卷/上下部标记。无标记视为 full（全本），与「下」不同片。
 * @return string full|上|中|下|上篇|...
 */
function mergePartTag($name)
{
    $s = preg_replace('/\s+/u', '', (string)$name);
    $s = str_replace(['　'], '', $s);
    if (preg_match('/[（(【\[]\s*(上篇|中篇|下篇|上部|中部|下部|前篇|后篇|上|中|下|全集|全)\s*[）)】\]]/u', $s, $m)) {
        $p = $m[1];
        if ($p === '全集' || $p === '全') {
            return 'full';
        }
        return $p;
    }
    if (preg_match('/(上篇|中篇|下篇|上部|中部|下部)$/u', $s, $m)) {
        return $m[1];
    }
    return 'full';
}

/**
 * 提取语种/版本标记。有标记与无标记、或标记不同 → 视为不同片子
 * @return string 空串表示「未标注版本」（通常是默认版）
 */
function mergeEditionTag($name)
{
    $s = preg_replace('/\s+/u', '', (string)$name);
    $s = str_replace(['　'], '', $s);
    // 先去掉分卷括号，避免干扰
    $s = preg_replace('/[（(【\[]\s*(上|中|下|上篇|中篇|下篇|上部|中部|下部|前篇|后篇|全集|全)\s*[）)】\]]/u', '', $s);
    $tags = [
        '国语版', '粤语版', '英语版', '日语版', '韩语版', '越南语版', '泰语版',
        '法语版', '德语版', '俄语版', '西班牙语版', '印地语版',
        '双语版', '配音版', '原声版', '中字版', '无字版',
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

/** 版本冲突：国语版 ≠ 默认版；分卷 全本 ≠ 下 ≠ 上 */
function mergeEditionConflict($nameA, $nameB)
{
    if (mergeEditionTag($nameA) !== mergeEditionTag($nameB)) {
        return true;
    }
    if (mergePartTag($nameA) !== mergePartTag($nameB)) {
        return true;
    }
    return false;
}

/**
 * 从分类名/备注等文本识别「频道形态」
 * 短剧、综艺、动漫、电影、电视剧等同名极多，必须拆开
 * @return string movie|series|short|variety|anime|doc|comic|unknown
 */
function mergeClassifyKindText($text)
{
    $s = trim((string)$text);
    if ($s === '') {
        return 'unknown';
    }
    // 优先级：越容易和其他类型撞名的越靠前
    $rules = [
        'short' => '/短剧|微短剧|竖屏|抖音剧|快手剧|小程序剧|竖短剧/u',
        'anime' => '/动漫|动画|卡通|番剧|国漫|日漫|配音动漫/u',
        'variety' => '/综艺|真人秀|晚会|访谈|选秀|脱口秀/u',
        'doc' => '/纪录片|纪录/u',
        'comic' => '/漫画|有声漫画|动态漫/u',
        'movie' => '/电影|影片|院线|剧场版|微电影/u',
        // 电视剧类放最后；不含「短剧」
        'series' => '/连续剧|电视剧|电视连续剧|网剧|日剧|韩剧|美剧|台剧|港剧|英剧|泰剧|剧集/u',
    ];
    foreach ($rules as $kind => $re) {
        if (preg_match($re, $s)) {
            return $kind;
        }
    }
    return 'unknown';
}

/**
 * 加载 mac_type → 每个 type_id 的根分类与形态
 * @return array<int,array{name:string,pid:int,root_id:int,root_name:string,kind:string}>
 */
function mergeLoadTypeMap(PDO $pdo, $vodTable)
{
    $typeTable = preg_replace('/vod$/i', 'type', str_replace('`', '', $vodTable));
    if ($typeTable === str_replace('`', '', $vodTable)) {
        $typeTable = 'mac_type';
    }
    try {
        $rows = $pdo->query("SELECT `type_id`,`type_name`,`type_pid` FROM `{$typeTable}`")->fetchAll(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        return [];
    }
    $byId = [];
    foreach ($rows as $r) {
        $id = (int)$r['type_id'];
        $byId[$id] = [
            'name' => (string)$r['type_name'],
            'pid' => (int)$r['type_pid'],
        ];
    }
    $map = [];
    foreach ($byId as $id => $info) {
        $chain = [];
        $cur = $id;
        $guard = 0;
        while ($cur > 0 && isset($byId[$cur]) && $guard < 16) {
            $chain[] = $byId[$cur]['name'];
            $pid = $byId[$cur]['pid'];
            if ($pid <= 0 || $pid === $cur) {
                break;
            }
            $cur = $pid;
            $guard++;
        }
        $rootId = $cur > 0 ? $cur : $id;
        $rootName = isset($byId[$rootId]) ? $byId[$rootId]['name'] : $info['name'];
        // 先看自身分类名，再看整条祖先链（子类「国产短剧」挂在「短剧」下）
        $kind = mergeClassifyKindText($info['name']);
        if ($kind === 'unknown') {
            $kind = mergeClassifyKindText(implode(' ', $chain));
        }
        $map[$id] = [
            'name' => $info['name'],
            'pid' => $info['pid'],
            'root_id' => $rootId,
            'root_name' => $rootName,
            'kind' => $kind,
        ];
    }
    return $map;
}

/** 请求级缓存 type_map */
function mergeTypeMapStore($map = null)
{
    static $stored = null;
    if ($map !== null) {
        $stored = $map;
    }
    return is_array($stored) ? $stored : [];
}

/**
 * 形态：电影 / 电视剧 / 短剧 / 综艺 / 动漫 …
 * @return string
 */
function mergeMediaKind($row)
{
    $typeMap = mergeTypeMapStore();
    $typeId = isset($row['type_id']) ? (int)$row['type_id'] : 0;

    // 1) CMS 分类树（最可靠）
    if ($typeId > 0 && isset($typeMap[$typeId]) && $typeMap[$typeId]['kind'] !== 'unknown') {
        return $typeMap[$typeId]['kind'];
    }

    // 2) 扩展分类 / 备注 / 片名关键词
    $blob = trim(
        (string)($row['vod_class'] ?? '') . ' ' .
        (string)($row['vod_remarks'] ?? '') . ' ' .
        (string)($row['vod_name'] ?? '')
    );
    $fromText = mergeClassifyKindText($blob);
    if ($fromText !== 'unknown') {
        return $fromText;
    }

    // 3) 根分类名再试一次
    if ($typeId > 0 && isset($typeMap[$typeId])) {
        $k = mergeClassifyKindText($typeMap[$typeId]['root_name'] . ' ' . $typeMap[$typeId]['name']);
        if ($k !== 'unknown') {
            return $k;
        }
    }

    // 4) 弱启发：仅 1 集且无剧类信号 → 倾向电影；多集但不瞎归成「电视剧」（短剧也多集）
    $eps = max((int)($row['vod_total'] ?? 0), (int)($row['vod_serial'] ?? 0));
    if ($eps === 1) {
        return 'movie';
    }
    return 'unknown';
}

function mergeMediaKindLabel($kind)
{
    $labels = [
        'movie' => '电影',
        'series' => '电视剧',
        'short' => '短剧',
        'variety' => '综艺',
        'anime' => '动漫',
        'doc' => '纪录片',
        'comic' => '漫画',
        'unknown' => '形态未知',
    ];
    return isset($labels[$kind]) ? $labels[$kind] : '形态未知';
}

function mergeTypeRootId($row)
{
    $typeMap = mergeTypeMapStore();
    $typeId = isset($row['type_id']) ? (int)$row['type_id'] : 0;
    if ($typeId > 0 && isset($typeMap[$typeId])) {
        return (int)$typeMap[$typeId]['root_id'];
    }
    return $typeId;
}

function mergeTypeRootName($row)
{
    $typeMap = mergeTypeMapStore();
    $typeId = isset($row['type_id']) ? (int)$row['type_id'] : 0;
    if ($typeId > 0 && isset($typeMap[$typeId])) {
        return (string)$typeMap[$typeId]['root_name'];
    }
    return '';
}

/**
 * 不同频道形态 / 不同一级分类形态 → 冲突
 * 短剧≠电视剧≠电影≠综艺≠动漫（同名 IP 极常见）
 * 注意：同为「电影」下的动作片/喜剧片若被建成两个一级类，只要形态都是电影，允许合并
 */
function mergeMediaKindConflict($a, $b)
{
    $ka = mergeMediaKind($a);
    $kb = mergeMediaKind($b);
    if ($ka !== 'unknown' && $kb !== 'unknown' && $ka !== $kb) {
        return true;
    }

    $typeMap = mergeTypeMapStore();
    $ra = mergeTypeRootId($a);
    $rb = mergeTypeRootId($b);
    if ($ra > 0 && $rb > 0 && $ra !== $rb) {
        $kra = isset($typeMap[$ra]['kind']) ? $typeMap[$ra]['kind'] : 'unknown';
        $krb = isset($typeMap[$rb]['kind']) ? $typeMap[$rb]['kind'] : 'unknown';
        if ($kra === 'unknown' && isset($typeMap[$ra])) {
            $kra = mergeClassifyKindText($typeMap[$ra]['name']);
        }
        if ($krb === 'unknown' && isset($typeMap[$rb])) {
            $krb = mergeClassifyKindText($typeMap[$rb]['name']);
        }
        // 只有根分类也识别成不同形态才拦（避免「国产剧/欧美剧」都是电视剧却被误拦）
        if ($kra !== 'unknown' && $krb !== 'unknown' && $kra !== $krb) {
            return true;
        }
    }

    // 集数 1 对 ≥5：电影/单片 vs 多集内容
    $ea = max((int)($a['vod_total'] ?? 0), (int)($a['vod_serial'] ?? 0));
    $eb = max((int)($b['vod_total'] ?? 0), (int)($b['vod_serial'] ?? 0));
    if ($ea > 0 && $eb > 0) {
        if (($ea <= 1 && $eb >= 5) || ($eb <= 1 && $ea >= 5)) {
            return true;
        }
    }
    return false;
}

function mergeYearNum($row)
{
    $y = preg_replace('/\D+/', '', (string)($row['vod_year'] ?? ''));
    if ($y === '') {
        return 0;
    }
    $y = (int)substr($y, 0, 4);
    return ($y >= 1900 && $y <= 2100) ? $y : 0;
}

function mergePeopleSet($s)
{
    $s = str_replace(['/', '|', '、', '，', ';', '；'], ',', $s);
    $parts = preg_split('/,+/', $s);
    $out = [];
    foreach ($parts as $p) {
        $p = preg_replace('/\s+/u', '', trim($p));
        if ($p === '' || mb_strlen($p, 'UTF-8') < 2) {
            continue;
        }
        $p = preg_replace('/(饰|配音|主演|导演)$/u', '', $p);
        if ($p === '') {
            continue;
        }
        $out[mb_strtolower($p, 'UTF-8')] = true;
    }
    return array_keys($out);
}

function mergeShort($s, $n)
{
    $s = trim((string)$s);
    if ($s === '') {
        return '';
    }
    if (mb_strlen($s, 'UTF-8') <= $n) {
        return $s;
    }
    return mb_substr($s, 0, $n, 'UTF-8') . '…';
}

function mergeMetaRichness($row)
{
    $n = 0;
    if (mergeYearNum($row) > 0) {
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
 * 封面 URL 归一化：忽略域名、参数、尺寸目录，抽出可比对指纹
 * @return array{url:string,path:string,key:string,base:string,stem:string}
 */
function mergeCoverInfo($pic)
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
    // 去掉常见缩略图/尺寸段
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

/** 是否像采集站哈希文件名（同图常被存成不同哈希） */
function mergeCoverStemHashy($stem)
{
    $stem = strtolower((string)$stem);
    if ($stem === '') {
        return false;
    }
    if (strlen($stem) >= 16 && preg_match('/^[a-f0-9]+$/', $stem)) {
        return true;
    }
    // 20+ 位字母数字混合，无语义
    if (strlen($stem) >= 18 && preg_match('/^[a-z0-9_-]+$/', $stem)
        && preg_match('/[a-z]/', $stem) && preg_match('/\d/', $stem)
        && !preg_match('/(poster|cover|vod|movie|film|img)/', $stem)) {
        return true;
    }
    return false;
}

/**
 * @return 'same'|'diff'|'unknown'
 */
function mergeCompareCover($ca, $cb)
{
    if ($ca['stem'] === '' || $cb['stem'] === '') {
        return 'unknown';
    }
    // 完整 URL 相同
    if ($ca['url'] !== '' && $ca['url'] === $cb['url']) {
        return 'same';
    }
    // 去掉域名后的路径相同（最常见：同图不同 CDN）
    if ($ca['path'] !== '' && $ca['path'] === $cb['path'] && $ca['path'] !== '/') {
        return 'same';
    }
    // 文件名（含扩展）相同
    if ($ca['key'] !== '' && $ca['key'] === $cb['key']) {
        return 'same';
    }
    // 主文件名相同（jpg/png 互换等）
    if ($ca['stem'] !== '' && $ca['stem'] === $cb['stem']) {
        return 'same';
    }
    $sa = $ca['stem'];
    $sb = $cb['stem'];
    // 一个文件名包含另一个（过长后缀/前缀）
    if (strlen($sa) >= 8 && strlen($sb) >= 8) {
        if (strpos($sa, $sb) !== false || strpos($sb, $sa) !== false) {
            return 'same';
        }
    }
    // 去掉 copy/副本/(1) 后再比
    $na = preg_replace('/(?:[-_]?(?:copy|副本|拷贝|\(\d+\)|（\d+）|\d+))$/u', '', $sa);
    $nb = preg_replace('/(?:[-_]?(?:copy|副本|拷贝|\(\d+\)|（\d+）|\d+))$/u', '', $sb);
    if ($na !== '' && $na === $nb) {
        return 'same';
    }

    // 两边都是哈希文件名且不同：同图常被不同采集源存成不同名，不能判「不同」
    if (mergeCoverStemHashy($sa) && mergeCoverStemHashy($sb) && $sa !== $sb) {
        return 'unknown';
    }

    return 'diff';
}

/**
 * 对比两条记录：明确列出「相同 / 不同 / 缺字段」
 * @return array{same:list,diff:list,note:list,cover:string}
 */
function mergeBuildCompare($a, $b)
{
    $same = [];
    $diff = [];
    $note = [];

    $na = mergeNormalizeTitle((string)($a['vod_name'] ?? ''));
    $nb = mergeNormalizeTitle((string)($b['vod_name'] ?? ''));
    $rawA = trim((string)($a['vod_name'] ?? ''));
    $rawB = trim((string)($b['vod_name'] ?? ''));
    $dispA = preg_replace('/\s+/u', '', str_replace(['　'], '', $rawA));
    $dispB = preg_replace('/\s+/u', '', str_replace(['　'], '', $rawB));
    // 原始片名字面不同 → 一律不算「片名相同」（避免（下）/国语版被误报）
    if ($dispA !== '' && $dispA === $dispB) {
        $same[] = '片名相同';
    } elseif ($na !== '' && $na === $nb) {
        $same[] = '片名相同(仅标点/空白差异)';
    } else {
        $diff[] = '片名不同「' . mergeShort($rawA, 28) . '」≠「' . mergeShort($rawB, 28) . '」';
    }
    if (mergeEditionConflict($rawA, $rawB)) {
        $ea = mergeEditionTag($rawA) ?: '默认版';
        $eb = mergeEditionTag($rawB) ?: '默认版';
        if ($ea !== $eb) {
            $diff[] = "版本不同({$ea}/{$eb})";
        }
        $pa = mergePartTag($rawA);
        $pb = mergePartTag($rawB);
        if ($pa !== $pb) {
            $lab = function ($p) {
                return $p === 'full' ? '全本/未标分卷' : $p;
            };
            $diff[] = '分卷不同(' . $lab($pa) . '/' . $lab($pb) . ')';
        }
    }

    $ka = mergeMediaKind($a);
    $kb = mergeMediaKind($b);
    if ($ka !== 'unknown' && $kb !== 'unknown') {
        if ($ka === $kb) {
            $same[] = '形态相同(' . mergeMediaKindLabel($ka) . ')';
        } else {
            $diff[] = '形态不同(' . mergeMediaKindLabel($ka) . '/' . mergeMediaKindLabel($kb) . ')';
        }
    } elseif ($ka !== 'unknown' || $kb !== 'unknown') {
        $note[] = '形态:' . mergeMediaKindLabel($ka !== 'unknown' ? $ka : $kb) . ' / 另一方不明';
    }
    $raName = mergeTypeRootName($a);
    $rbName = mergeTypeRootName($b);
    if ($raName !== '' && $rbName !== '') {
        if ($raName === $rbName) {
            $same[] = '一级分类相同(' . $raName . ')';
        } elseif (mergeMediaKindConflict($a, $b)) {
            $diff[] = '一级分类不同(' . $raName . '/' . $rbName . ')';
        } else {
            $note[] = '分类名不同但仍可能同形态(' . $raName . '/' . $rbName . ')';
        }
    }
    if (mergeMediaKindConflict($a, $b)) {
        $diff[] = '不同类型内容冲突（电影/电视剧/短剧/综艺/动漫等），禁止合并';
    }

    $ya = mergeYearNum($a);
    $yb = mergeYearNum($b);
    if ($ya > 0 && $yb > 0) {
        if ($ya === $yb) {
            $same[] = "年份相同({$ya})";
        } else {
            $diff[] = "年份不同({$ya}/{$yb})";
        }
    } elseif ($ya > 0 || $yb > 0) {
        $note[] = '年份一方为空';
    } else {
        $note[] = '年份双方为空';
    }

    $da = mergePeopleSet($a['vod_director'] ?? '');
    $db = mergePeopleSet($b['vod_director'] ?? '');
    if ($da && $db) {
        $inter = array_values(array_intersect($da, $db));
        if ($inter) {
            $same[] = '导演相同:' . implode(',', array_slice($inter, 0, 3));
        } else {
            $diff[] = '导演不同';
        }
    } elseif ($da || $db) {
        $note[] = '导演一方为空';
    } else {
        $note[] = '导演双方为空';
    }

    $aa = mergePeopleSet($a['vod_actor'] ?? '');
    $ab = mergePeopleSet($b['vod_actor'] ?? '');
    if ($aa && $ab) {
        $inter = array_values(array_intersect($aa, $ab));
        $ic = count($inter);
        if ($ic === 0) {
            $diff[] = '主演无交集';
        } elseif ($ic >= 2) {
            $same[] = '主演重合' . $ic . '人:' . implode(',', array_slice($inter, 0, 4));
        } else {
            $diff[] = '主演仅1人重合:' . $inter[0];
        }
    } elseif ($aa || $ab) {
        $note[] = '主演一方为空';
    } else {
        $note[] = '主演双方为空';
    }

    $ca = mergeCoverInfo($a['vod_pic'] ?? '');
    $cb = mergeCoverInfo($b['vod_pic'] ?? '');
    $coverRel = mergeCompareCover($ca, $cb);
    if ($coverRel === 'same') {
        if ($ca['url'] === $cb['url']) {
            $same[] = '封面相同';
        } else {
            $same[] = '封面相同(链接写法不同，判定为同图)';
        }
    } elseif ($coverRel === 'diff') {
        $diff[] = '封面不同';
    } elseif ($ca['stem'] === '' && $cb['stem'] === '') {
        $note[] = '封面双方为空';
    } elseif ($ca['stem'] === '' || $cb['stem'] === '') {
        $note[] = '封面一方为空';
    } else {
        $note[] = '封面链接不同，无法仅凭地址断定是否同图（不据此拆分）';
    }

    $ta = (int)($a['vod_total'] ?? 0);
    $tb = (int)($b['vod_total'] ?? 0);
    if ($ta > 0 && $tb > 0) {
        if ($ta === $tb) {
            $same[] = "集数相同({$ta})";
        } else {
            $diff[] = "集数不同({$ta}/{$tb})";
        }
    }

    return [
        'same' => $same,
        'diff' => $diff,
        'note' => $note,
        'cover' => $coverRel,
    ];
}

function mergeJudgePair($a, $b, $cfg)
{
    $score = 30;
    $why = [];
    $strong = [];
    $hardBlock = false;

    // 短剧不参与自动合并（重名不同片极多）
    if (mergeIsShortDrama($a) || mergeIsShortDrama($b)) {
        return [
            'verdict' => 'block',
            'score' => 0,
            'why' => '短剧已跳过，不自动合并',
            'strong' => [],
        ];
    }

    // 国语版 / 默认版 / 越南语版 等：不是重复片，禁止自动合并
    $nameA = (string)($a['vod_name'] ?? '');
    $nameB = (string)($b['vod_name'] ?? '');
    if (mergeEditionConflict($nameA, $nameB)) {
        $pa = mergePartTag($nameA);
        $pb = mergePartTag($nameB);
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
        $ea = mergeEditionTag($nameA) ?: '默认版';
        $eb = mergeEditionTag($nameB) ?: '默认版';
        return [
            'verdict' => 'block',
            'score' => 0,
            'why' => "版本不同({$ea}/{$eb})，不合并",
            'strong' => [],
        ];
    }

    // 电影 / 电视剧 / 短剧 / 综艺 / 动漫 / 不同一级分类（同名 IP 极常见）
    if (mergeMediaKindConflict($a, $b)) {
        $ka = mergeMediaKindLabel(mergeMediaKind($a));
        $kb = mergeMediaKindLabel(mergeMediaKind($b));
        $ra = mergeTypeRootName($a) ?: '?';
        $rb = mergeTypeRootName($b) ?: '?';
        $ea = max((int)($a['vod_total'] ?? 0), (int)($a['vod_serial'] ?? 0));
        $eb = max((int)($b['vod_total'] ?? 0), (int)($b['vod_serial'] ?? 0));
        return [
            'verdict' => 'block',
            'score' => 0,
            'why' => "类型冲突({$ka}/{$kb}，分类{$ra}/{$rb}，集数{$ea}/{$eb})，不合并",
            'strong' => [],
        ];
    }

    $ya = mergeYearNum($a);
    $yb = mergeYearNum($b);
    if ($ya > 0 && $yb > 0) {
        $diff = abs($ya - $yb);
        if ($diff === 0) {
            $score += 30;
            $strong[] = "同年:{$ya}";
        } elseif ($diff === 1) {
            $score += 5;
            $why[] = "年份差1({$ya}/{$yb})";
        } else {
            $why[] = "年份冲突:{$ya}/{$yb}";
            if ($cfg['hard_block_year']) {
                return ['verdict' => 'block', 'score' => 0, 'why' => implode('; ', $why), 'strong' => []];
            }
            $score -= 50;
            $hardBlock = true;
        }
    }

    $da = mergePeopleSet($a['vod_director'] ?? '');
    $db = mergePeopleSet($b['vod_director'] ?? '');
    if ($da && $db) {
        $inter = array_intersect($da, $db);
        if ($inter) {
            $score += 35;
            $strong[] = '导演:' . implode(',', array_slice($inter, 0, 3));
        } else {
            $why[] = '导演不同';
            return ['verdict' => 'block', 'score' => 0, 'why' => implode('; ', $why), 'strong' => []];
        }
    }

    $aa = mergePeopleSet($a['vod_actor'] ?? '');
    $ab = mergePeopleSet($b['vod_actor'] ?? '');
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
        }
    }

    $ca = mergeCoverInfo($a['vod_pic'] ?? '');
    $cb = mergeCoverInfo($b['vod_pic'] ?? '');
    $coverRel = mergeCompareCover($ca, $cb);
    if ($coverRel === 'same') {
        $score += 40;
        $strong[] = '封面一致';
    } elseif ($coverRel === 'diff') {
        $why[] = '封面不同';
        $score -= !empty($cfg['cover_mismatch_needs_other']) ? 15 : 5;
    }

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

    $richA = mergeMetaRichness($a) + ($ca['key'] !== '' ? 1 : 0);
    $richB = mergeMetaRichness($b) + ($cb['key'] !== '' ? 1 : 0);
    if ($richA === 0 && $richB === 0) {
        $why[] = '双方关键字段为空';
        $score -= 10;
    }

    if ($hardBlock) {
        return ['verdict' => 'block', 'score' => $score, 'why' => implode('; ', $why) ?: '硬冲突', 'strong' => $strong];
    }

    // 封面明确不同：暂不进「确定可合并」，放到右侧人工确认
    if ($coverRel === 'diff' && !empty($cfg['cover_diff_to_unsure'])) {
        $tip = $strong ? ('强证据:' . implode('; ', $strong) . '；') : '';
        return [
            'verdict' => 'unsure',
            'score' => $score,
            'why' => $tip . '封面不同，暂定待确认',
            'strong' => $strong,
        ];
    }

    if (!empty($cfg['require_strong']) && !$strong) {
        return ['verdict' => 'unsure', 'score' => $score, 'why' => implode('; ', $why) ?: '缺少强证据', 'strong' => []];
    }
    if ($coverRel === 'diff' && !empty($cfg['cover_mismatch_needs_other'])) {
        $nonCoverStrong = array_values(array_filter($strong, function ($s) {
            return strpos($s, '封面') === false;
        }));
        if (!$nonCoverStrong) {
            return ['verdict' => 'unsure', 'score' => $score, 'why' => '封面不同且无其它强证据', 'strong' => $strong];
        }
        if (count($nonCoverStrong) === 1 && strpos($nonCoverStrong[0], '同年') === 0 && !$da && !$db && !$aa && !$ab) {
            return ['verdict' => 'unsure', 'score' => $score, 'why' => '仅同年+封面不同', 'strong' => $strong];
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
    return ['verdict' => 'unsure', 'score' => $score, 'why' => implode('; ', $why) ?: ('分数不足:' . $score), 'strong' => $strong];
}

function mergeKeepScore($row)
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
    $s += mergeMetaRichness($row) * 15;
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
        $pa = (strpos(strtolower($a), 'm3u8') !== false) ? 100 : 50;
        $pb = (strpos(strtolower($b), 'm3u8') !== false) ? 100 : 50;
        return $pb <=> $pa;
    });
    return [
        'from' => implode('$$$', array_keys($map)),
        'url' => implode('$$$', array_values($map)),
    ];
}

function mergeBuildPlan($cluster)
{
    usort($cluster, function ($a, $b) {
        return mergeKeepScore($b) <=> mergeKeepScore($a);
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
    return [
        'keep_id' => $keepId,
        'title' => (string)$keep['vod_name'],
        'remove_ids' => $remove,
        'play_from' => $merged['from'],
        'play_url' => $merged['url'],
        'members_raw' => $cluster,
    ];
}

function mergeUiMember($r)
{
    $kind = mergeMediaKind($r);
    $typeMap = mergeTypeMapStore();
    $typeId = isset($r['type_id']) ? (int)$r['type_id'] : 0;
    $typeName = ($typeId > 0 && isset($typeMap[$typeId])) ? $typeMap[$typeId]['name'] : '';
    $rootName = mergeTypeRootName($r);
    return [
        'vod_id' => (int)$r['vod_id'],
        'vod_name' => (string)$r['vod_name'],
        'vod_year' => (string)($r['vod_year'] ?? ''),
        'vod_area' => (string)($r['vod_area'] ?? ''),
        'vod_lang' => (string)($r['vod_lang'] ?? ''),
        'vod_director' => (string)($r['vod_director'] ?? ''),
        'vod_actor' => mergeShort($r['vod_actor'] ?? '', 80),
        'vod_class' => mergeShort($r['vod_class'] ?? '', 60),
        'vod_remarks' => mergeShort($r['vod_remarks'] ?? '', 40),
        'vod_total' => (int)($r['vod_total'] ?? 0),
        'vod_play_from' => (string)($r['vod_play_from'] ?? ''),
        'vod_pic' => (string)($r['vod_pic'] ?? ''),
        'vod_hits' => (int)($r['vod_hits'] ?? 0),
        'type_id' => $typeId,
        'type_name' => $typeName,
        'type_root' => $rootName,
        'kind' => $kind,
        'kind_label' => mergeMediaKindLabel($kind),
    ];
}

function mergeUiGroup($cluster, $reason, $score, $source)
{
    $plan = mergeBuildPlan($cluster);
    $gid = 'g_' . $plan['keep_id'] . '_' . implode('_', $plan['remove_ids']);
    $membersRaw = $plan['members_raw'];
    $compare = null;
    if (count($membersRaw) >= 2) {
        // 用保留条目与第一条待删条目做对比展示
        $keepRow = $membersRaw[0];
        $other = isset($membersRaw[1]) ? $membersRaw[1] : $membersRaw[0];
        $compare = mergeBuildCompare($keepRow, $other);
    }
    return [
        'gid' => $gid,
        'title' => $plan['title'],
        'keep_id' => $plan['keep_id'],
        'remove_ids' => $plan['remove_ids'],
        'play_from' => $plan['play_from'],
        'reason' => $reason,
        'score' => $score,
        'source' => $source,
        'compare' => $compare,
        'members' => array_map('mergeUiMember', $membersRaw),
    ];
}

/** 按分数保留 Top-N（优先最匹配） */
function mergeKeepTopByScore(array &$list, array $item, $limit)
{
    $list[] = $item;
    usort($list, function ($a, $b) {
        return ((int)($b['score'] ?? 0)) <=> ((int)($a['score'] ?? 0));
    });
    if (count($list) > $limit) {
        $list = array_slice($list, 0, $limit);
    }
}

function mergeTouchesExclude(array $rows, array $excludeIds)
{
    if ($excludeIds === []) {
        return false;
    }
    foreach ($rows as $r) {
        $id = (int)$r['vod_id'];
        if (isset($excludeIds[$id])) {
            return true;
        }
    }
    return false;
}

function mergeFullyCompatible($cluster, $cfg)
{
    $n = count($cluster);
    for ($i = 0; $i < $n; $i++) {
        for ($j = $i + 1; $j < $n; $j++) {
            if (mergeJudgePair($cluster[$i], $cluster[$j], $cfg)['verdict'] !== 'merge') {
                return false;
            }
        }
    }
    return true;
}

function mergeExtractSafePairs($cluster, $cfg)
{
    $n = count($cluster);
    $edges = [];
    for ($i = 0; $i < $n; $i++) {
        for ($j = $i + 1; $j < $n; $j++) {
            $jdg = mergeJudgePair($cluster[$i], $cluster[$j], $cfg);
            if ($jdg['verdict'] === 'merge') {
                $edges[] = ['i' => $i, 'j' => $j, 'score' => $jdg['score'], 'why' => $jdg['why']];
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
        $pairs[] = [
            'rows' => [$cluster[$e['i']], $cluster[$e['j']]],
            'score' => $e['score'],
            'why' => $e['why'],
        ];
    }
    return $pairs;
}

function mergeClusterRows($rows, $cfg)
{
    $n = count($rows);
    $parent = range(0, $n - 1);
    $find = function ($x) use (&$parent, &$find) {
        if ($parent[$x] !== $x) {
            $parent[$x] = $find($parent[$x]);
        }
        return $parent[$x];
    };
    for ($i = 0; $i < $n; $i++) {
        for ($j = $i + 1; $j < $n; $j++) {
            if (mergeJudgePair($rows[$i], $rows[$j], $cfg)['verdict'] === 'merge') {
                $ra = $find($i);
                $rb = $find($j);
                if ($ra !== $rb) {
                    $parent[$rb] = $ra;
                }
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

/**
 * 是否短剧（短剧重名极多，自动扫描一律跳过）
 */
function mergeIsShortDrama($row)
{
    return mergeMediaKind($row) === 'short';
}

/**
 * 从分类树收集所有短剧 type_id（含子类）
 * @return array<int,true>
 */
function mergeShortTypeIdSet()
{
    $set = [];
    foreach (mergeTypeMapStore() as $tid => $info) {
        if (!empty($info['kind']) && $info['kind'] === 'short') {
            $set[(int)$tid] = true;
            continue;
        }
        // 根分类是短剧时，子类一并跳过
        $rootId = isset($info['root_id']) ? (int)$info['root_id'] : 0;
        if ($rootId > 0) {
            $map = mergeTypeMapStore();
            if (isset($map[$rootId]['kind']) && $map[$rootId]['kind'] === 'short') {
                $set[(int)$tid] = true;
            }
        }
    }
    return $set;
}

/**
 * 扫描建议合并 + 存疑样例
 * 短剧整类跳过（同名不同片极多）
 * @param array $excludeIds vod_id => true，已在待执行队列中的 ID 跳过
 * @return array{suggest:list,unsure:list,stats:array}
 */
function mergeScanSuggest(PDO $pdo, $table, $metaSql, $cfg, $level, $limitSuggest, $nameFilter = '', array $excludeIds = [])
{
    // 先加载分类树，短剧/电影/电视剧等同名才能拆开
    mergeTypeMapStore(mergeLoadTypeMap($pdo, $table));
    $shortTypes = mergeShortTypeIdSet();

    $nameSql = "SELECT `vod_id`, `vod_name`, `type_id` FROM `{$table}`";
    $params = [];
    if ($nameFilter !== '') {
        $nameSql .= ' WHERE `vod_name` LIKE ?';
        $params[] = '%' . $nameFilter . '%';
    }
    $st = $pdo->prepare($nameSql);
    $st->execute($params);

    $byNorm = [];
    $skippedShort = 0;
    while ($row = $st->fetch(PDO::FETCH_ASSOC)) {
        $id = (int)$row['vod_id'];
        if (isset($excludeIds[$id])) {
            continue;
        }
        $tid = isset($row['type_id']) ? (int)$row['type_id'] : 0;
        if ($tid > 0 && isset($shortTypes[$tid])) {
            $skippedShort++;
            continue;
        }
        // 片名里自带短剧标记的也跳过
        if (mergeClassifyKindText((string)$row['vod_name']) === 'short') {
            $skippedShort++;
            continue;
        }
        $nk = mergeNormalizeTitle((string)$row['vod_name']);
        if ($nk === '' || $nk === '#part:full#') {
            continue;
        }
        if (!isset($byNorm[$nk])) {
            $byNorm[$nk] = [];
        }
        $byNorm[$nk][] = $id;
    }
    $st->closeCursor();

    $dupNorms = [];
    foreach ($byNorm as $nk => $ids) {
        if (count($ids) >= 2) {
            $dupNorms[] = $nk;
        }
    }

    $suggest = [];
    $unsure = [];
    $stats = [
        'dup_groups' => count($dupNorms),
        'suggest' => 0,
        'unsure_pairs' => 0,
        'block_pairs' => 0,
        'skipped_short' => $skippedShort,
    ];

    foreach ($dupNorms as $nk) {
        $ids = $byNorm[$nk];
        unset($byNorm[$nk]);
        $rows = mergeLoadByIds($pdo, $table, $metaSql, $ids);
        // 二次过滤：扩展分类/备注识别为短剧的也去掉
        $rows = array_values(array_filter($rows, function ($r) use (&$stats) {
            if (mergeIsShortDrama($r)) {
                $stats['skipped_short']++;
                return false;
            }
            return true;
        }));
        if (count($rows) < 2) {
            continue;
        }

        $n = count($rows);
        for ($i = 0; $i < $n; $i++) {
            for ($j = $i + 1; $j < $n; $j++) {
                $pairRows = [$rows[$i], $rows[$j]];
                if (mergeTouchesExclude($pairRows, $excludeIds)) {
                    continue;
                }
                $jdg = mergeJudgePair($rows[$i], $rows[$j], $cfg);
                if ($jdg['verdict'] === 'unsure') {
                    $stats['unsure_pairs']++;
                    mergeKeepTopByScore($unsure, mergeUiGroup($pairRows, $jdg['why'], $jdg['score'], 'unsure'), $limitSuggest);
                } elseif ($jdg['verdict'] === 'block') {
                    $stats['block_pairs']++;
                }
            }
        }

        $clusters = mergeClusterRows($rows, $cfg);
        foreach ($clusters as $cluster) {
            if (count($cluster) < 2) {
                continue;
            }
            if (mergeTouchesExclude($cluster, $excludeIds)) {
                continue;
            }
            $addPlans = [];
            if (!empty($cfg['require_strong'])) {
                if (mergeFullyCompatible($cluster, $cfg)) {
                    $j0 = mergeJudgePair($cluster[0], $cluster[1], $cfg);
                    $addPlans[] = ['rows' => $cluster, 'score' => $j0['score'], 'why' => $j0['why']];
                } else {
                    foreach (mergeExtractSafePairs($cluster, $cfg) as $p) {
                        $addPlans[] = $p;
                    }
                }
            } else {
                $j0 = mergeJudgePair($cluster[0], $cluster[1], $cfg);
                $addPlans[] = ['rows' => $cluster, 'score' => isset($j0['score']) ? $j0['score'] : 0, 'why' => isset($j0['why']) ? $j0['why'] : ''];
            }
            foreach ($addPlans as $p) {
                $chk = mergeJudgePair($p['rows'][0], $p['rows'][1], $cfg);
                // 封面不同等已被降为 unsure，不应进左侧「确定可合并」
                if ($chk['verdict'] !== 'merge') {
                    continue;
                }
                mergeKeepTopByScore($suggest, mergeUiGroup($p['rows'], $p['why'], $p['score'], 'suggest'), $limitSuggest);
            }
        }
        unset($rows, $clusters);
    }

    $stats['suggest'] = count($suggest);
    $stats['unsure_pairs'] = count($unsure);

    return ['suggest' => $suggest, 'unsure' => $unsure, 'stats' => $stats, 'level' => $level];
}

function mergeSearchName(PDO $pdo, $table, $metaSql, $name, $limit = 40)
{
    $name = trim($name);
    if ($name === '') {
        return [];
    }
    $st = $pdo->prepare("SELECT {$metaSql} FROM `{$table}` WHERE `vod_name` LIKE ? ORDER BY `vod_id` DESC LIMIT " . (int)$limit);
    $st->execute(['%' . $name . '%']);
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);
    // 按归一化名分组
    $groups = [];
    foreach ($rows as $r) {
        $nk = mergeNormalizeTitle((string)$r['vod_name']);
        if (!isset($groups[$nk])) {
            $groups[$nk] = [];
        }
        $groups[$nk][] = $r;
    }
    $out = [];
    foreach ($groups as $rowsG) {
        if (count($rowsG) < 1) {
            continue;
        }
        $out[] = [
            'title' => (string)$rowsG[0]['vod_name'],
            'count' => count($rowsG),
            'members' => array_map('mergeUiMember', $rowsG),
        ];
    }
    return $out;
}

function mergeApplyGroup(PDO $pdo, $table, $cols, $group)
{
    $ids = array_merge([(int)$group['keep_id']], array_map('intval', $group['remove_ids']));
    $ids = array_values(array_unique($ids));
    list($metaCols, $metaSql) = [null, null];
    // reload full rows for play url
    $want = [
        'vod_id', 'vod_name', 'type_id', 'vod_class', 'vod_year', 'vod_area', 'vod_lang',
        'vod_actor', 'vod_director', 'vod_remarks', 'vod_total',
        'vod_play_from', 'vod_play_url', 'vod_pic', 'vod_hits',
    ];
    $metaCols = array_values(array_intersect($want, $cols));
    $metaSql = implode(',', array_map(function ($c) {
        return '`' . $c . '`';
    }, $metaCols));
    $rows = mergeLoadByIds($pdo, $table, $metaSql, $ids);
    if (count($rows) < 2) {
        throw new RuntimeException('组内有效记录不足: ' . $group['title']);
    }
    // 按用户指定 keep
    $keepId = (int)$group['keep_id'];
    usort($rows, function ($a, $b) use ($keepId) {
        if ((int)$a['vod_id'] === $keepId) {
            return -1;
        }
        if ((int)$b['vod_id'] === $keepId) {
            return 1;
        }
        return mergeKeepScore($b) <=> mergeKeepScore($a);
    });
    $plan = mergeBuildPlan($rows);
    // 强制 keep_id
    $plan['keep_id'] = $keepId;
    $plan['remove_ids'] = [];
    foreach ($rows as $r) {
        if ((int)$r['vod_id'] !== $keepId) {
            $plan['remove_ids'][] = (int)$r['vod_id'];
        }
    }
    $merged = mergePlaySources($rows);
    $plan['play_from'] = $merged['from'];
    $plan['play_url'] = $merged['url'];

    $upd = $pdo->prepare("UPDATE `{$table}` SET `vod_play_from` = ?, `vod_play_url` = ? WHERE `vod_id` = ?");
    $upd->execute([$plan['play_from'], $plan['play_url'], $keepId]);

    // 补空字段
    $keep = null;
    foreach ($rows as $r) {
        if ((int)$r['vod_id'] === $keepId) {
            $keep = $r;
            break;
        }
    }
    if ($keep) {
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
            foreach ($rows as $m) {
                if ((int)$m['vod_id'] === $keepId) {
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
        if ($sets) {
            $vals[] = $keepId;
            $pdo->prepare('UPDATE `' . $table . '` SET ' . implode(',', $sets) . ' WHERE vod_id = ?')->execute($vals);
        }
    }

    if ($plan['remove_ids']) {
        $in = implode(',', array_map('intval', $plan['remove_ids']));
        $pdo->exec("DELETE FROM `{$table}` WHERE `vod_id` IN ({$in})");
    }
    return ['keep_id' => $keepId, 'deleted' => count($plan['remove_ids']), 'title' => $plan['title']];
}

function mergeQueuePath($dir)
{
    $bak = rtrim($dir, '/\\') . DIRECTORY_SEPARATOR . 'backups';
    if (!is_dir($bak)) {
        @mkdir($bak, 0755, true);
    }
    return $bak . DIRECTORY_SEPARATOR . 'merge_ui_queue.json';
}
