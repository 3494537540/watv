<?php
/**
 * 苹果 CMS / App 通用视频解析中转
 *
 * 请求：
 *   GET /index.php?url=https://www.iqiyi.com/v_xxx.html
 *   GET /index.php?url=https://xxx.com/a.m3u8          （直链直接返回）
 *
 * 成功 JSON（CMS 播放器 / 自研 App 都可认）：
 *   {"code":200,"success":1,"msg":"ok","type":"m3u8","url":"https://...m3u8"}
 *
 * 失败：
 *   {"code":404,"success":0,"msg":"...","type":"","url":""}
 *
 * 后台配置（苹果 CMS）：
 *   视频 → 播放器 → 编辑 qiyi/qq/youku
 *   「是否解析」选 是
 *   「解析地址」填：https://你的域名/jiexi/index.php?url=
 */

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

$configFile = is_file(__DIR__ . '/config.php')
    ? __DIR__ . '/config.php'
    : __DIR__ . '/config.example.php';
/** @var array $config */
$config = require $configFile;

if (!empty($config['cors'])) {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, X-Jiexi-Key');
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
}

require __DIR__ . '/lib/Jiexi.php';

$jiexi = new Jiexi($config);

// 鉴权
$needKey = (string)($config['api_key'] ?? '');
if ($needKey !== '') {
    $got = (string)($_GET['key'] ?? $_SERVER['HTTP_X_JIEXI_KEY'] ?? '');
    if (!hash_equals($needKey, $got)) {
        echo json_encode($jiexi->fail('unauthorized', 401), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }
}

$rawUrl = (string)($_GET['url'] ?? $_POST['url'] ?? '');
if ($rawUrl === '' && isset($_GET['v'])) {
    $rawUrl = (string)$_GET['v'];
}
$rawUrl = trim($rawUrl);

$result = $jiexi->resolve($rawUrl);
echo json_encode($result, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
