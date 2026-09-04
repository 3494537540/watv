# 苹果 CMS 视频解析接口（PHP）

把「网页播放地址」（爱奇艺 / 腾讯 / 优酷等）转成 App / 播放器能播的 **m3u8/mp4 直链 JSON**。

> 重要：本接口是 **中转 + 标准化**，不内置破解官源。  
> 直链 `.m3u8` / `.mp4` 会直接返回；网页地址需要你在 `config.php` 里配置可用的上游解析。

## 部署

> 兼容 **PHP 7.2+**（不依赖 PHP 8 的 `str_contains` / `str_ends_with`）。

1. 把整个 `maccms-jiexi` 目录上传到服务器，例如：  
   `https://154.12.29.28/jiexi/`
2. 复制配置：

```bash
cp config.example.php config.php
```

3. 编辑 `config.php`：
   - 填写 `upstreams`（你自己的解析源）
   - 建议设置 `api_key`
   - `cache` 目录需可写

4. 测试：

```text
# 直链应直接成功
https://你的域名/jiexi/index.php?url=https://example.com/a/index.m3u8

# 网页地址（需已配置上游）
https://你的域名/jiexi/index.php?url=https://www.iqiyi.com/v_xxx.html
```

成功示例：

```json
{
  "code": 200,
  "success": 1,
  "msg": "ok",
  "type": "m3u8",
  "url": "https://cdn.xxx.com/index.m3u8"
}
```

## 苹果 CMS 后台怎么填

1. **视频 → 播放器** → 编辑 `qiyi` / `qq` / `youku`（或你采集到的编码）
2. **是否解析**：是  
3. **解析地址**：

```text
https://你的域名/jiexi/index.php?url=
```

若开了 `api_key`：

```text
https://你的域名/jiexi/index.php?key=你的密钥&url=
```

保存后清缓存，再播一条官源地址验证。

## 和 Flutter App

App 当前 `video_player` 只播直链。两种接法：

1. **推荐**：采集继续用 m3u8 资源站（魔都/茅台等），App 不用解析  
2. 若必须播官源：App 先请求本接口拿 `url`，再把返回的 m3u8 交给播放器

## 上游解析怎么填

`config.php`：

```php
'upstreams' => [
    [
        'name' => 'myparse',
        'url'  => 'https://你的上游/?url=',
        'timeout' => 12,
    ],
],
```

上游应返回 JSON（或纯文本 URL），本接口会尝试读取 `url` / `data.url` / `play` 等字段。

## 目录

| 文件 | 作用 |
|------|------|
| `index.php` | 入口 |
| `config.example.php` | 配置模板 |
| `lib/Jiexi.php` | 核心逻辑 |
| `cache/` | 解析缓存（自动创建） |
