<?php
/**
 * 解析接口配置
 * 复制为 config.php 后修改。
 *
 * 说明：
 * - 直链 .m3u8 / .mp4 会直接返回，不走上游
 * - 爱奇艺/腾讯/优酷等网页地址，需填写你自己可用的「上游解析」
 * - 本仓库不内置破解官源的逻辑，只做 CMS 兼容的中转与标准化 JSON
 */
return [
    // 接口访问密钥（可选）。非空则要求 ?key=xxx 或 Header: X-Jiexi-Key
    'api_key' => '',

    // 允许解析的主机（空数组 = 不限制）。建议填官源域名，防被滥用成开放代理
    'allow_hosts' => [
        'www.iqiyi.com',
        'iqiyi.com',
        'www.iq.com',
        'v.qq.com',
        'qq.com',
        'v.youku.com',
        'youku.com',
        'www.mgtv.com',
        'mgtv.com',
        'www.bilibili.com',
        'bilibili.com',
        'www.ixigua.com',
    ],

    // 已经是直链时直接放行的后缀/特征
    'passthrough_ext' => ['m3u8', 'mp4', 'flv', 'mkv', 'ts'],

    // 上游解析（按顺序尝试，直到成功）
    // 每个上游会请求： upstream_url + urlencode(目标地址)
    // 并按 response 规则从 JSON 里取播放地址
    'upstreams' => [
        // 示例（请换成你自己可用的解析；失效需自行更换）
        // [
        //     'name' => 'demo',
        //     'url'  => 'https://example.com/api/?url=',
        //     'timeout' => 12,
        //     // JSON 路径：支持 code / data.url / url 等常见字段，见 Jiexi::extractPlayUrl
        // ],
    ],

    // 本地缓存秒数（0=关闭）。同一网页地址短时间重复解析会打缓存
    'cache_ttl' => 600,
    'cache_dir' => __DIR__ . '/cache',

    // CORS（给 App / 网页调试用）
    'cors' => true,

    // 调试：true 时失败会多返回 upstream 错误信息（生产请 false）
    'debug' => false,
];
