# MacCMS 运维小工具

上传到站点目录，例如：`/www/wwwroot/你的域名/maccms-tools/`  
**用完请删除敏感 php 文件，或改密钥。**

---

## 0. 灰火扩展控制台（通知 / 双端更新 / 安装包 / 更新记录）

文件：`huihuo_panel.php` + `mac_bootstrap.php`  
密钥：`huihuo_panel_2026`

### 后台自定义菜单

```text
灰火扩展,/maccms-tools/huihuo_panel.php?key=huihuo_panel_2026
行分隔符,###
```

### App 公开接口

```text
/maccms-tools/huihuo_panel.php?api=notify_list
/maccms-tools/huihuo_panel.php?api=app_update&platform=android
/maccms-tools/huihuo_panel.php?api=app_update&platform=ios
/maccms-tools/huihuo_panel.php?api=app_config
/maccms-tools/huihuo_panel.php?api=update_report   # POST JSON
```

### 双端更新规则

- Android / iOS **各自**配置 `version` + `version_code` + 下载地址（可上传 apk/ipa）
- App 本地 `ApiConfig.appVersionCode` **小于** 服务器才算有新版本
- **强制更新**勾选：启动弹窗；不勾选：只在「设置→检查更新」出现
- 用户点「复制下载链接」或已升到新版本会上报，后台「更新记录」可见

安装包目录：`/static/app/releases/`（需 PHP 可写；大文件请调大 `upload_max_filesize`）

表：`mac_huihuo_notify` / `mac_huihuo_app_update` / `mac_huihuo_update_log` / `mac_huihuo_kv`

---

## 1. 分类导出 / 一键导入（重装 CMS 用）

文件：`type_backup.php`  
密钥：`huihuo_type_2026`

### 重装前（必做）

1. 把 **`type_backup.php`**、**`mac_bootstrap.php`** 上传到 **`maccms-tools/`**（两个 php 同级）
2. JSON 备份放到 **`maccms-tools/backups/`**
3. 浏览器打开：

```text
https://你的域名/maccms-tools/type_backup.php?key=huihuo_type_2026&mode=export
```

---

## 2. 影视合并可视化台（推荐）

上传这三个文件到 `maccms-tools/`：

- `merge_vod_ui.php`
- `merge_lib.php`
- `mac_bootstrap.php`

密钥：`huihuo_merge_2026`

### 打开

```text
https://你的域名/maccms-tools/merge_vod_ui.php?key=huihuo_merge_2026
```

### 怎么用

1. 点 **扫描两侧列表**（库大可能要几分钟）——**不会清空**底部待执行队列
2. 布局：**左**「确定可合并（最匹配优先，封面相同）」· **右**「待确认（封面不同/存疑）」· **底**「待执行」
3. 每行会标明 **相同 / 不同 / 缺字段**；封面不同不会进左侧，需右侧人工确认
4. 加入待执行后会 **自动刷新**左右列表（跳过已选 ID）
5. 「手动搜索」可搜片名勾选加入
6. 队列自动存 `backups/merge_ui_queue.json` + 浏览器 localStorage
7. 核对完再点 **确认执行合并**

语言/地区只作参考。**短剧整类跳过**（重名太多）。合并前会读 CMS **分类树**：电影 / 电视剧 / 综艺 / 动漫等形态不同 → **禁止合并**。**（上）（下）** 与未标分卷视为不同片。国语版≠默认版。默认宁可少并，不可误并。

文本预览版仍可用：`merge_vod.php?key=huihuo_merge_2026&mode=dry&level=safe`

---

## 3. 影视库粗清理（旧版）

文件：`dedupe_vod.php`  
密钥：`huihuo_dedupe_2026`

```text
https://你的域名/maccms-tools/dedupe_vod.php?key=huihuo_dedupe_2026&mode=clean
```
