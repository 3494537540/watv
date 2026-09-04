<?php
/**
 * 灰火 H5 跨域代理（独立小文件，上传到 /maccms-tools/cms_cors_proxy.php 即可）
 *
 * 例：
 *   /maccms-tools/cms_cors_proxy.php?target=vod&ac=list&pg=1
 *   /maccms-tools/cms_cors_proxy.php?target=art&ac=detail&pg=1
 *   /maccms-tools/cms_cors_proxy.php?target=website&ac=detail&pg=1
 */
declare(strict_types=1);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Cookie');
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

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
unset($q['target']);
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
        'header' => "Accept: application/json\r\nUser-Agent: HuiHuoCmsCorsProxy/1.0\r\n",
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
    echo json_encode(['code' => 0, 'msg' => 'proxy failed', 'url' => $url], JSON_UNESCAPED_UNICODE);
    exit;
}

header('Content-Type: application/json; charset=utf-8');
echo $body;
