<?php
declare(strict_types=1);

/**
 * 解析核心：直链透传 + 上游解析聚合 + 缓存
 * 兼容 PHP 7.2+（不使用 str_contains / str_ends_with）
 */
final class Jiexi
{
    /** @var array */
    private $config;

    /** @param array $config */
    public function __construct(array $config)
    {
        $this->config = $config;
    }

    /** @return array */
    public function fail($msg, $code = 404)
    {
        return [
            'code' => (int)$code,
            'success' => 0,
            'msg' => (string)$msg,
            'type' => '',
            'url' => '',
        ];
    }

    /** @return array */
    public function ok($playUrl, $type = '', $msg = 'ok')
    {
        $playUrl = (string)$playUrl;
        $type = (string)$type;
        if ($type === '') {
            $type = $this->guessType($playUrl);
        }
        return [
            'code' => 200,
            'success' => 1,
            'msg' => (string)$msg,
            'type' => $type,
            'url' => $playUrl,
            'data' => $playUrl,
            'play' => $playUrl,
        ];
    }

    /** @return array */
    public function resolve($rawUrl)
    {
        $rawUrl = (string)$rawUrl;
        if ($rawUrl === '') {
            return $this->fail('缺少 url 参数');
        }

        $url = $this->normalizeUrl($rawUrl);
        if ($url === null) {
            return $this->fail('url 无效');
        }

        // 已是直链：优先放行
        if ($this->isDirectMedia($url)) {
            return $this->ok($url, $this->guessType($url), 'passthrough');
        }

        if (!$this->hostAllowed($url)) {
            return $this->fail('域名不在 allow_hosts 白名单');
        }

        $cached = $this->cacheGet($url);
        if (is_array($cached) && !empty($cached['url'])) {
            $cached['msg'] = 'cache';
            return $cached;
        }

        $upstreams = isset($this->config['upstreams']) ? $this->config['upstreams'] : [];
        if (!is_array($upstreams) || $upstreams === []) {
            return $this->fail(
                '未配置上游解析（config.php → upstreams）。直链 m3u8 可直接播；网页地址需要可用的解析源。'
            );
        }

        $errors = [];
        foreach ($upstreams as $up) {
            if (!is_array($up) || empty($up['url'])) {
                continue;
            }
            $name = isset($up['name']) ? (string)$up['name'] : 'upstream';
            $timeout = isset($up['timeout']) ? (int)$up['timeout'] : 12;
            $endpoint = (string)$up['url'] . rawurlencode($url);
            try {
                $body = $this->httpGet($endpoint, $timeout);
                $play = $this->extractPlayUrl($body);
                if ($play !== null && $this->looksLikeMedia($play)) {
                    $out = $this->ok($play, $this->guessType($play), $name);
                    $this->cacheSet($url, $out);
                    return $out;
                }
                $errors[] = $name . ': empty play url';
            } catch (Exception $e) {
                $errors[] = $name . ': ' . $e->getMessage();
            } catch (Throwable $e) {
                $errors[] = $name . ': ' . $e->getMessage();
            }
        }

        $msg = '全部上游解析失败';
        if (!empty($this->config['debug'])) {
            $msg .= ' | ' . implode('; ', $errors);
        }
        return $this->fail($msg);
    }

    /** @return string|null */
    private function normalizeUrl($raw)
    {
        $u = trim((string)$raw);
        $flags = defined('ENT_HTML5') ? (ENT_QUOTES | ENT_HTML5) : ENT_QUOTES;
        $u = html_entity_decode($u, $flags, 'UTF-8');
        for ($i = 0; $i < 2; $i++) {
            $decoded = rawurldecode($u);
            if ($decoded === $u) {
                break;
            }
            $u = $decoded;
        }
        if (!preg_match('#^https?://#i', $u)) {
            return null;
        }
        if (filter_var($u, FILTER_VALIDATE_URL) === false) {
            return null;
        }
        return $u;
    }

    private function hostAllowed($url)
    {
        $allow = isset($this->config['allow_hosts']) ? $this->config['allow_hosts'] : [];
        if (!is_array($allow) || $allow === []) {
            return true;
        }
        $host = strtolower((string)parse_url($url, PHP_URL_HOST));
        if ($host === '') {
            return false;
        }
        foreach ($allow as $h) {
            $h = strtolower(trim((string)$h));
            if ($h === '') {
                continue;
            }
            if ($host === $h || $this->strEndsWith($host, '.' . $h)) {
                return true;
            }
        }
        if ($this->isDirectMedia($url)) {
            return true;
        }
        return false;
    }

    private function isDirectMedia($url)
    {
        $path = strtolower((string)parse_url($url, PHP_URL_PATH));
        $exts = isset($this->config['passthrough_ext']) ? $this->config['passthrough_ext'] : ['m3u8', 'mp4'];
        if (!is_array($exts)) {
            $exts = ['m3u8', 'mp4'];
        }
        $urlLower = strtolower($url);
        foreach ($exts as $ext) {
            $ext = strtolower((string)$ext);
            if ($ext === '') {
                continue;
            }
            if ($this->strEndsWith($path, '.' . $ext) || $this->strContains($path, '.' . $ext . '?')) {
                return true;
            }
            if (preg_match('/\.' . preg_quote($ext, '/') . '(\?|$|#)/i', $urlLower)) {
                return true;
            }
        }
        return (bool)preg_match('/\.m3u8(\?|$|#)/i', $url)
            || (bool)preg_match('/\.mp4(\?|$|#)/i', $url);
    }

    private function looksLikeMedia($url)
    {
        if (!preg_match('#^https?://#i', $url)) {
            return false;
        }
        return $this->isDirectMedia($url)
            || $this->strContains($url, 'm3u8')
            || $this->strContains($url, 'mp4')
            || $this->strContains($url, '/play/')
            || $this->strContains($url, 'video');
    }

    private function guessType($url)
    {
        $u = strtolower($url);
        if ($this->strContains($u, '.m3u8') || $this->strContains($u, 'm3u8')) {
            return 'm3u8';
        }
        if ($this->strContains($u, '.mp4')) {
            return 'mp4';
        }
        if ($this->strContains($u, '.flv')) {
            return 'flv';
        }
        return 'auto';
    }

    /** @return string|null */
    private function extractPlayUrl($body)
    {
        $body = trim((string)$body);
        if ($body === '') {
            return null;
        }

        if (preg_match('#^https?://\S+#i', $body, $m)) {
            return trim($m[0]);
        }

        $json = json_decode($body, true);
        if (!is_array($json)) {
            if (preg_match('/https?:\/\/[^\s"\'<>]+?\.(?:m3u8|mp4)[^\s"\'<>]*/i', $body, $m)) {
                $flags = defined('ENT_HTML5') ? (ENT_QUOTES | ENT_HTML5) : ENT_QUOTES;
                return html_entity_decode($m[0], $flags, 'UTF-8');
            }
            return null;
        }

        $candidates = [
            isset($json['url']) ? $json['url'] : null,
            isset($json['play']) ? $json['play'] : null,
            isset($json['data']) ? $json['data'] : null,
            isset($json['video']) ? $json['video'] : null,
            isset($json['src']) ? $json['src'] : null,
            isset($json['media']) ? $json['media'] : null,
        ];
        if (isset($json['data']) && is_array($json['data'])) {
            $candidates[] = isset($json['data']['url']) ? $json['data']['url'] : null;
            $candidates[] = isset($json['data']['play']) ? $json['data']['play'] : null;
            $candidates[] = isset($json['data']['src']) ? $json['data']['src'] : null;
        }
        if (isset($json['result']) && is_array($json['result'])) {
            $candidates[] = isset($json['result']['url']) ? $json['result']['url'] : null;
        }

        foreach ($candidates as $c) {
            if (is_string($c) && preg_match('#^https?://#i', $c)) {
                return $c;
            }
        }
        return null;
    }

    private function httpGet($url, $timeout)
    {
        $timeout = (int)$timeout;
        if (function_exists('curl_init')) {
            $ch = curl_init($url);
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_CONNECTTIMEOUT => min(8, $timeout),
                CURLOPT_TIMEOUT => $timeout,
                CURLOPT_SSL_VERIFYPEER => false,
                CURLOPT_SSL_VERIFYHOST => false,
                CURLOPT_USERAGENT => 'MacCMS-Jiexi/1.0',
                CURLOPT_HTTPHEADER => [
                    'Accept: application/json,text/plain,*/*',
                ],
            ]);
            $body = curl_exec($ch);
            $errno = curl_errno($ch);
            $err = curl_error($ch);
            $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            if ($body === false || $errno) {
                throw new RuntimeException($err !== '' ? $err : 'curl error');
            }
            if ($code >= 400) {
                throw new RuntimeException('HTTP ' . $code);
            }
            return (string)$body;
        }

        $ctx = stream_context_create([
            'http' => [
                'timeout' => $timeout,
                'header' => "User-Agent: MacCMS-Jiexi/1.0\r\nAccept: application/json,*/*\r\n",
            ],
            'ssl' => [
                'verify_peer' => false,
                'verify_peer_name' => false,
            ],
        ]);
        $body = @file_get_contents($url, false, $ctx);
        if ($body === false) {
            throw new RuntimeException('http get failed');
        }
        return $body;
    }

    private function cacheKey($url)
    {
        return hash('sha256', (string)$url);
    }

    /** @return array|null */
    private function cacheGet($url)
    {
        $ttl = isset($this->config['cache_ttl']) ? (int)$this->config['cache_ttl'] : 0;
        if ($ttl <= 0) {
            return null;
        }
        $dir = isset($this->config['cache_dir'])
            ? (string)$this->config['cache_dir']
            : (__DIR__ . '/../cache');
        $file = $dir . '/' . $this->cacheKey($url) . '.json';
        if (!is_file($file)) {
            return null;
        }
        if (filemtime($file) + $ttl < time()) {
            @unlink($file);
            return null;
        }
        $raw = @file_get_contents($file);
        if ($raw === false) {
            return null;
        }
        $data = json_decode($raw, true);
        return is_array($data) ? $data : null;
    }

    /** @param array $data */
    private function cacheSet($url, array $data)
    {
        $ttl = isset($this->config['cache_ttl']) ? (int)$this->config['cache_ttl'] : 0;
        if ($ttl <= 0) {
            return;
        }
        $dir = isset($this->config['cache_dir'])
            ? (string)$this->config['cache_dir']
            : (__DIR__ . '/../cache');
        if (!is_dir($dir)) {
            @mkdir($dir, 0755, true);
        }
        $file = $dir . '/' . $this->cacheKey($url) . '.json';
        @file_put_contents($file, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    private function strContains($haystack, $needle)
    {
        $haystack = (string)$haystack;
        $needle = (string)$needle;
        if ($needle === '') {
            return true;
        }
        return strpos($haystack, $needle) !== false;
    }

    private function strEndsWith($haystack, $needle)
    {
        $haystack = (string)$haystack;
        $needle = (string)$needle;
        if ($needle === '') {
            return true;
        }
        $len = strlen($needle);
        if ($len === 0) {
            return true;
        }
        return substr($haystack, -$len) === $needle;
    }
}
