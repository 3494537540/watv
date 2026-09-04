# App 远程配置 / 直播源对接说明

把下列文件放到 CMS 站点可访问目录（推荐）：

```
/static/app/app_config.json   ← 底栏、策划栏、直播源、BT 解析
/static/app/live.m3u          ← IPTV / CCTV 直播列表
```

示例见同目录：

- `app_config.example.json`
- `live.m3u.example`

## 底栏 tabs

| id | 页面 |
|----|------|
| home | 首页 |
| filter | 筛选 |
| news | 资讯（CMS 文章） |
| profile | 我的 |

兼容：远程若仍配置 `short` / `sports` / `live` 会去掉；旧 `tasks`（功能）自动映射为 `news`（资讯）。

`enabled: false` 可隐藏某一项。顺序即底栏顺序。

## 策划栏 nav

`action` 支持：`short_drama` / `commentary` / `cloud` / `bt` / `art` / `live` / `live_import` / `sports`

## 直播源优先级

1. App 内「导入」的 M3U / `name,url` 文本  
2. `app_config.json` → `live_sources`  
3. `live_m3u_url` 或 `/static/app/live.m3u`  
4. CMS `provide/website` 中带 m3u8/live 的跳转链接  

## BT / 磁力

配置 `torrent_parse_api`，例如：

`https://域名/jiexi/torrent.php?url=`

接口需返回 JSON：`{"url":"https://...m3u8","name":"可选标题"}`  
App 拿到直链后用内置播放器播放。

## 体育分类

默认 `sports_type_id=48`，`sports_event_type_id=84`，可按后台实际 ID 修改。
