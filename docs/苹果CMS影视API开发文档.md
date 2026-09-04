# 苹果 CMS V10 影视 API 开发文档

> 适用于 **MacCMS / 苹果 CMS V10** 开放资源接口（`provide`）与站外入库接口（`receive`）。  
> 客户端（App / 小程序 / 采集程序）对接影视数据时，以本文为准。

---

## 0. 本站信息（哇TV）

| 项 | 值 |
|----|----|
| 站点 | [哇TV](https://154.12.29.28/) |
| Base URL | `https://154.12.29.28` |
| 影视列表 | `https://154.12.29.28/api.php/provide/vod/?ac=list` |
| 影视详情 | `https://154.12.29.28/api.php/provide/vod/?ac=detail&ids={id}` |
| 探测时间 | 2026-08-30 |

### 当前状态：开放 API 已开启

实测（2026-08-30）：

```http
GET https://154.12.29.28/api.php/provide/vod/?ac=detail&pg=1
→ HTTP 200，JSON：code=1，含 vod_pic / vod_name 等
```

App 首页轮播已对接该接口（`MacCmsApi.fetchBannerMovies`）。

---

## 1. 概述

苹果 CMS 通过站点根目录下的 `api.php` 对外提供两类能力：

| 类型 | 路径前缀 | 用途 | 方法 |
|------|----------|------|------|
| **开放资源 API** | `/api.php/provide/...` | 对外提供分类、列表、详情（供采集或 App 拉取） | GET |
| **站外入库 API** | `/api.php/receive/...` | 第三方往本站写入视频/文章等 | POST |

本文重点覆盖 **影视（vod）**，并附带文章、演员等扩展模块。

### 1.1 基础约定

- **协议**：HTTP / HTTPS（本站强制 HTTPS，HTTP 会 301）
- **编码**：UTF-8
- **默认格式**：JSON；兼容老版 XML（加 `at=xml`）
- **成功标志**：`code == 1`
- **本站 Base URL**：`https://154.12.29.28`

```
https://154.12.29.28/api.php/provide/vod/?ac=list
```

部分资源站会提供专用线路，例如仅返回 m3u8：

```
https://154.12.29.28/api.php/provide/vod/m3u8/
```

具体以资源站说明为准。

---

## 2. 影视开放接口（核心）

### 2.1 接口地址

| 场景 | URL |
|------|-----|
| 列表（含分类） | `/api.php/provide/vod/?ac=list` |
| 详情 | `/api.php/provide/vod/?ac=detail` |
| XML 列表 | `/api.php/provide/vod/?at=xml&ac=list` |
| XML 详情 | `/api.php/provide/vod/?at=xml&ac=detail` |
| 路径风格 XML | `/api.php/provide/vod/at/xml/?ac=list` |

> 部分站点也支持 `ac=videolist`：返回带播放字段的列表（行为因版本/插件略有差异，优先用 `list` + `detail`）。

### 2.2 通用请求参数

| 参数 | 必填 | 示例 | 说明 |
|------|------|------|------|
| `ac` | 否 | `list` / `detail` | 模式；默认列表。详情必须配合 `ids` 或 `h` |
| `pg` | 否 | `1` | 页码，从 1 开始 |
| `t` | 否 | `1` | 分类 ID（`type_id`） |
| `wd` | 否 | `流浪地球` | 片名模糊搜索 |
| `h` | 否 | `24` | 最近 N 小时内更新的数据 |
| `ids` | 详情常用 | `123` 或 `123,456` | 视频 ID，多个用英文逗号分隔 |
| `at` | 否 | `xml` | 输出格式；缺省为 JSON |

#### 常见调用示例

```http
# 首页：最新列表 + 分类树
GET /api.php/provide/vod/?ac=list

# 某分类第 2 页
GET /api.php/provide/vod/?ac=list&t=6&pg=2

# 搜索
GET /api.php/provide/vod/?ac=list&wd=流浪地球

# 单部详情
GET /api.php/provide/vod/?ac=detail&ids=21

# 批量详情
GET /api.php/provide/vod/?ac=detail&ids=21,22,23

# 最近 24 小时更新（增量采集常用）
GET /api.php/provide/vod/?ac=detail&h=24&pg=1
```

### 2.3 列表响应（JSON）

`ac=list` 时通常包含：

- 分页元信息：`page` / `pagecount` / `limit` / `total`
- 当前页条目：`list[]`（摘要字段，一般无完整播放地址）
- 分类：`class[]`（部分站点在根级或同级返回）

```json
{
  "code": 1,
  "msg": "数据列表",
  "page": 1,
  "pagecount": 23,
  "limit": "20",
  "total": 449,
  "class": [
    { "type_id": 1, "type_pid": 0, "type_name": "电影" },
    { "type_id": 6, "type_pid": 1, "type_name": "动作片" }
  ],
  "list": [
    {
      "vod_id": 21,
      "vod_name": "测试1",
      "type_id": 6,
      "type_name": "动作片",
      "vod_en": "qingjian",
      "vod_time": "2018-03-29 20:50:19",
      "vod_remarks": "超清",
      "vod_play_from": "youku"
    }
  ]
}
```

#### 列表条目常用字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `vod_id` | int | 视频唯一 ID |
| `vod_name` | string | 片名 |
| `vod_en` | string | 拼音/英文标识 |
| `type_id` | int | 分类 ID |
| `type_name` | string | 分类名称 |
| `vod_time` | string | 更新时间 |
| `vod_remarks` | string | 备注（如「更新至12集」「超清」） |
| `vod_play_from` | string | 播放源标识（多源用 `,` 或 `$$$`，视站点而定） |
| `vod_pic` | string | 封面（部分 list 也返回） |

### 2.4 详情响应（JSON）

```json
{
  "code": 1,
  "msg": "数据列表",
  "page": 1,
  "pagecount": 1,
  "limit": "20",
  "total": 1,
  "list": [
    {
      "vod_id": 21,
      "vod_name": "测试1",
      "type_id": 6,
      "type_name": "动作片",
      "vod_en": "qingjian",
      "vod_time": "2018-03-29 20:50:19",
      "vod_remarks": "超清",
      "vod_play_from": "youku",
      "vod_pic": "https://example.com/poster.jpg",
      "vod_area": "大陆",
      "vod_lang": "国语",
      "vod_year": "2018",
      "vod_serial": "0",
      "vod_actor": "主演A,主演B",
      "vod_director": "导演名",
      "vod_content": "剧情简介……",
      "vod_play_url": "正片$https://cdn.example.com/1.m3u8#第2集$https://cdn.example.com/2.m3u8"
    }
  ]
}
```

#### 详情扩展字段

| 字段 | 说明 |
|------|------|
| `vod_pic` | 海报图 URL |
| `vod_area` | 地区 |
| `vod_lang` | 语言 |
| `vod_year` | 年份 |
| `vod_serial` | 连载状态相关（站点自定义） |
| `vod_actor` | 主演，逗号分隔 |
| `vod_director` | 导演 |
| `vod_content` | 简介（可能含 HTML） |
| `vod_play_from` | 播放器/线路编码 |
| `vod_play_url` | 播放地址串（见下节解析规则） |
| `vod_down_from` / `vod_down_url` | 下载线路（若开启） |

不同站点可能额外返回：`vod_score`、`vod_hits`、`vod_duration`、`vod_class`、`vod_tag` 等，客户端应按「有则用、无则忽略」解析。

---

## 3. 播放地址解析（必读）

苹果 CMS 的播放信息是 **字符串协议**，不是 JSON 数组。客户端必须本地拆分。

### 3.1 分隔符规则

| 层级 | 分隔符 | 含义 |
|------|--------|------|
| 多线路 / 多播放器 | `$$$` | 与 `vod_play_from` 按顺序一一对应 |
| 同一线路多集 | `#` | 分集列表 |
| 单集 | `名称$地址` | `$` 前为集名，后为播放 URL |

### 3.2 示例

**单线路、多集：**

```
vod_play_from = "m3u8"
vod_play_url  = "第01集$https://a.com/1.m3u8#第02集$https://a.com/2.m3u8"
```

**多线路：**

```
vod_play_from = "m3u8$$$qq$$$youku"
vod_play_url  =
  第01集$https://a.com/1.m3u8#第02集$https://a.com/2.m3u8$$$
  第01集$https://b.com/1.mp4$$$
  正片$https://c.com/full.m3u8
```

（实际为一行字符串，上例仅为可读换行。）

### 3.3 解析伪代码

```text
fromList = vod_play_from.split("$$$")
urlGroups = vod_play_url.split("$$$")

for i in 0 .. fromList.length-1:
  sourceName = fromList[i]
  episodes = []
  for item in urlGroups[i].split("#"):
    if item contains "$":
      name, url = item.split("$", 1)
      episodes.add({ name, url })
  sources.add({ sourceName, episodes })
```

### 3.4 Dart 参考实现（Flutter）

```dart
class VodEpisode {
  VodEpisode({required this.name, required this.url});
  final String name;
  final String url;
}

class VodSource {
  VodSource({required this.from, required this.episodes});
  final String from;
  final List<VodEpisode> episodes;
}

List<VodSource> parsePlaySources(String? from, String? url) {
  if (from == null || url == null || from.isEmpty || url.isEmpty) return [];
  final fromList = from.split('\$\$\$');
  final urlGroups = url.split('\$\$\$');
  final result = <VodSource>[];
  for (var i = 0; i < fromList.length; i++) {
    final group = i < urlGroups.length ? urlGroups[i] : '';
    final episodes = <VodEpisode>[];
    for (final item in group.split('#')) {
      if (item.isEmpty) continue;
      final idx = item.indexOf('\$');
      if (idx <= 0) continue;
      episodes.add(VodEpisode(
        name: item.substring(0, idx),
        url: item.substring(idx + 1),
      ));
    }
    result.add(VodSource(from: fromList[i], episodes: episodes));
  }
  return result;
}
```

### 3.5 播放注意点

- URL 可能是 **直链**（`.m3u8` / `.mp4`）或 **站内页**，需按播放器能力处理。
- 部分资源需 **解析接口 / 防盗链 Referer**，不在 CMS 标准 API 内，需业务侧单独配置。
- `vod_content` 常含 HTML，展示前建议去标签或用富文本组件。

---

## 4. 分类（class）说明

列表接口返回的 `class` 用于绑定栏目：

| 字段 | 说明 |
|------|------|
| `type_id` | 分类 ID（请求参数 `t` 使用此值） |
| `type_name` | 分类名称 |
| `type_pid` | 父级 ID；`0` 表示一级分类 |

```json
{ "type_id": 1, "type_pid": 0, "type_name": "电影" }
{ "type_id": 6, "type_pid": 1, "type_name": "动作片" }
```

**采集/对接建议：**

1. 先调 `ac=list` 拿到完整 `class`
2. 用二级 `type_id` 做栏目绑定（一级有时无片源）
3. 本站分类与资源站分类做 **映射表**，不要写死对方 ID

---

## 5. 推荐客户端调用流程

```text
启动 / 首页
  └─ GET ?ac=list
       ├─ 缓存 class（分类 Tab）
       └─ 展示 list（海报墙；若无 pic，再按需拉 detail）

分类浏览
  └─ GET ?ac=list&t={type_id}&pg={n}

搜索
  └─ GET ?ac=list&wd={keyword}&pg={n}

进入详情 / 播放
  └─ GET ?ac=detail&ids={vod_id}
       └─ 解析 vod_play_from + vod_play_url → 选源 → 播集

增量同步（采集端）
  └─ GET ?ac=detail&h=24&pg=1..N
```

### 5.1 HTTP 示例（curl）

```bash
curl -sk "https://154.12.29.28/api.php/provide/vod/?ac=list&pg=1"
curl -sk "https://154.12.29.28/api.php/provide/vod/?ac=detail&ids=21"
curl -sk --get "https://154.12.29.28/api.php/provide/vod/" \
  --data-urlencode "ac=list" \
  --data-urlencode "wd=变形金刚"
```

### 5.2 错误与空数据

| 情况 | 表现 | 建议 |
|------|------|------|
| 成功无结果 | `code=1` 且 `list` 为空 / `total=0` | 正常空态 |
| 接口关闭 | 正文为 `closed`，或 HTTP 403/404 / 非 JSON | 后台开启「开放 API」（见 §0） |
| 参数错误 | `code≠1` 或空 list | 校验 `ac`/`ids`/`t` |
| 超时 | 网络错误 | 重试 + 超时（建议 10–15s） |

---

## 6. 其他 provide 模块

路径结构与影视一致，仅资源名不同：

| 模块 | 列表 | 详情 |
|------|------|------|
| 文章 art | `/api.php/provide/art/?ac=list` | `?ac=detail` |
| 演员 actor | `/api.php/provide/actor/?ac=list` | `?ac=detail` |
| 角色 role | `/api.php/provide/role/?ac=list` | `?ac=detail` |
| 网址 website | `/api.php/provide/website/?ac=list` | `?ac=detail` |

通用参数同样支持：`t`、`pg`、`wd`、`h`、`ids`、`at=xml`。

---

## 7. 站外入库接口（receive）

用于火车头、自研采集器等 **向本站写入** 数据。

### 7.1 地址

| 模块 | 地址 |
|------|------|
| 视频 | `/api.php/receive/vod` |
| 文章 | `/api.php/receive/art` |
| 演员 | `/api.php/receive/actor` |
| 角色 | `/api.php/receive/role` |
| 网址 | `/api.php/receive/website` |

- **方法**：`POST`
- **Content-Type**：`multipart/form-data` 或 `application/x-www-form-urlencoded`
- **前置配置**：后台 → 站外入库 → 设置免登录密码、分类映射

### 7.2 通用必填

| 参数 | 说明 |
|------|------|
| `pass` | 入库密码 |
| `type_id` | 本站分类 ID |
| `vod_name`（等） | 名称字段必填 |

### 7.3 视频额外必填

| 参数 | 说明 |
|------|------|
| `vod_play_from` | 后台已存在的播放器编码（如 `dplayer`） |
| `vod_play_url` | 播放地址，格式同第 3 节 |

多播放组示例：

```text
vod_play_from = dplayer$$$videojs$$$ppvod
vod_play_url  =
  高清$http://1.com/a.mp4#高清$http://1.com/b.mp4$$$
  高清$http://2.com/a.mp4$$$
  高清$http://3.com/a.mp4
```

截图字段 `vod_pic_screenshot` 多图用 `#` 分隔。

**注意：** `vod_play_from` 必须是后台已配置的播放器编码，否则入库失败或无播放器。

---

## 8. XML 兼容说明

老客户端可使用 XML：

```http
GET /api.php/provide/vod/?at=xml&ac=list
GET /api.php/provide/vod/?at=xml&ac=detail&ids=21
```

列表节点大致对应：`list@page`、`video/id`、`name`、`type`、`dt`、`note` 等；详情额外含 `pic`、`actor`、`director`、`dl/dd`、`des`。新项目建议统一用 **JSON**。

---

## 9. 安全与后台配置

1. **开放 API**：后台开启对外 provide 服务；不需要对外时关闭或限制 IP。
2. **入库密码**：`receive` 的 `pass` 使用强密码，勿泄露到前端包。
3. **授权密钥**（若后台开启）：部分站点要求附加 `key` / `time` / `apikey`，以该站说明为准。
4. **联盟资源 ID**：资源标识用于分类绑定，勿随意改，否则采集分类错乱。
5. **客户端**：App 侧只调 `provide`；切勿把入库 `pass` 打进安装包。

---

## 10. 字段速查（vod）

| 字段 | list | detail | 说明 |
|------|:----:|:------:|------|
| `vod_id` | ✓ | ✓ | 主键 |
| `vod_name` | ✓ | ✓ | 片名 |
| `vod_en` | ✓ | ✓ | 英文/拼音 |
| `type_id` / `type_name` | ✓ | ✓ | 分类 |
| `vod_time` | ✓ | ✓ | 更新时间 |
| `vod_remarks` | ✓ | ✓ | 更新备注 |
| `vod_play_from` | ✓ | ✓ | 线路编码 |
| `vod_pic` | △ | ✓ | 封面 |
| `vod_area` / `vod_lang` / `vod_year` | △ | ✓ | 地区/语言/年份 |
| `vod_actor` / `vod_director` | △ | ✓ | 主演/导演 |
| `vod_content` | | ✓ | 简介 |
| `vod_play_url` | | ✓ | 播放串 |
| `vod_score` 等 | △ | △ | 扩展，视站点 |

`✓` 常见有，`△` 视站点/版本而定。

---

## 11. 对接检查清单

- [ ] Base URL 可访问：`/api.php/provide/vod/?ac=list`
- [ ] `code === 1` 且能拿到 `class` / `list`
- [ ] 分类映射表已配置（`type_id` ↔ 本端栏目）
- [ ] 详情能解析 `$$$` / `#` / `$` 三级结构
- [ ] 播放器支持目标格式（优先 m3u8）
- [ ] 搜索、分页、增量（`h`）路径已测通
- [ ] 生产环境 HTTPS、超时与空态处理完成
- [ ] 未在客户端暴露入库密码

---

## 12. 参考

- 苹果 CMS 官方采集说明：<http://www.maccms.la/apis/collect>
- MacCMS10 Wiki「入库接口说明」：<https://github.com/magicblack/maccms10/wiki>

---

## 附录 A：与本仓库 Flutter 模型的映射建议

当前 `lib/models/movie_models.dart` 为本地 mock，对接 CMS 时可按下列字段映射：

| App `Movie` | CMS 字段 |
|-------------|----------|
| `id` | `vod_id` |
| `title` | `vod_name` |
| `year` | `vod_year` |
| `score` | `vod_score`（若无则默认 0） |
| `genres` | `type_name` 或 `vod_class` 拆分 |
| `synopsis` | `vod_content`（去 HTML） |
| `episodes` | 解析 `vod_play_url` 后的集名列表 |
| `cast` | `vod_actor` 按逗号拆分 |
| 封面 URL | `vod_pic`（需扩展模型字段） |

列表页用 `ac=list`，点进详情/播放再 `ac=detail&ids=`，避免列表页全量拉播放地址。

---

## 附录 B：热门推荐 / 热榜搜索 / 更新日历怎么拿

> 重要结论：**官方 `provide/vod` 采集接口不支持按热度、推荐等级、星期筛选**。  
> 源码里列表固定按 `vod_time` 排序，只认 `ac/t/pg/wd/h/ids/year/isend/pagesize` 等参数。  
> 下面三类数据要靠「CMS 字段 + 站点页面/后台」或自建接口。

### B.1 热门推荐

| 能力 | CMS 机制 | provide 能否直接采 |
|------|----------|-------------------|
| 编辑推荐 | 字段 `vod_level`（1–9），后台影片编辑里设「推荐」 | 否（不能 `level=1` 过滤） |
| 点击热门 | `vod_hits` / `vod_hits_day` / `vod_hits_week` / `vod_hits_month` | 否（不能 `by=hits_week`） |
| 评分热门 | `vod_score` / `vod_douban_score` | 否 |

**站内模板怎么写（网页端）：**

```html
{maccms:vod num="10" level="1,2" order="desc" by="time"}
{maccms:vod num="10" type="1" order="desc" by="hits_week"}
```

标签参数说明见 [苹果 CMS v10 系统标签](https://www.maccms.cn/doc/v10/label.html)。

**采集站/资源站：**  
多数资源站只同步片名、封面、播放地址，**很少带 `vod_level`**。推荐位要在本站后台自己标，或用周/月点击当「热门」。

**App 可行方案（本站实测）：**

1. **周热门页（推荐）** — 与网页排行一致  
   - 电影：`/index.php/vod/show/id/1/by/hits_week.html`  
   - 电视剧：`/index.php/vod/show/id/2/by/hits_week.html`  
   - 总榜：`/index.php/label/rank.html`  
   - 解析 `vod/detail/id/{id}.html` → `ac=detail&ids=...`
2. **详情池客户端排序** — `ac=detail&t={分类}&pg=1..n`，按 `vod_hits_week` 排序（本站轮播兜底逻辑）
3. **自建 API** — 在 CMS 加插件/自定义 PHP：`by=hits_week&level=1` 返回 JSON

本站现状：`vod_level` 基本全是 `0`，靠点击量排行更靠谱。

### B.2 热榜搜索（热门搜索词）

| 来源 | 说明 |
|------|------|
| 模板写死 | 主题「热门搜索」列表（本站首页就是） |
| 后台配置 | 部分主题/插件有「搜索热词」配置项 |
| 搜索日志表 | `mac_vod_search` 一类表统计关键词（需查库或插件） |
| provide | **无热搜接口** |

本站首页 HTML 示例：

```text
/index.php/vod/search/wd/变形金刚.html
/index.php/vod/search/wd/火影忍者.html
...
```

**App 方案：**

1. 解析首页/搜索页「热门搜索」链接里的 `wd=`（最快）  
2. 后台维护一份热词 JSON（推荐生产用法）  
3. 自建接口读搜索统计表 Top N  

**不要指望采集站提供热搜**——热搜是「本站用户搜什么」，不是资源站字段。

### B.3 更新日历（追番表）

| 字段 | 含义 |
|------|------|
| `vod_weekday` | 更新周期，如 `一,二,三` 或 `周一` |
| `vod_serial` | 连载集数 |
| `vod_isend` | 是否完结 `0/1` |
| `vod_remarks` | 备注，如「更新至26集」 |
| `vod_time` | 最近更新时间 |

**站内模板：**

```html
{maccms:vod num="20" weekday="一" order="desc" by="time"}
{maccms:vod num="20" weekday="二" order="desc" by="time"}
```

**采集侧真相：**  
资源站入库多数 **不填 `vod_weekday`**。本站探测国产剧样本里该字段为空，日历若直接读库会是空的。

**怎么补齐日历数据：**

1. **后台人工**：影片编辑 → 节目周期  
2. **采集规则**：火车头/采集插件映射「更新日」到 `vod_weekday`（源站有才行）  
3. **推断**：用 `vod_time` 的星期几近似「今日更新」（粗糙但可用）  
4. **App**：`h=24/48` 拉最近更新 + `vod_isend=0` 未完结，按星期分组做成日历

**provide 没有 weekday 参数**，日历接口需自建，例如：

```text
GET /api.php/provide/vod/?ac=detail&h=72   → 客户端按 weekday 或更新日分组
```

或自定义：

```text
GET /addon/api/calendar.php?week=1
```

### B.4 对照表（采什么、怎么接 App）

| 产品模块 | CMS 有没有 | provide 够不够 | 建议接法 |
|----------|------------|----------------|----------|
| 热门推荐 | `vod_level` + 点击字段 | 不够 | 周热门页解析 / 客户端按 hits 排序 / 自建 API |
| 热榜 | 站点 `/by/hits_week` | 不够 | 同热门；区分日/周/月用不同 `by` 页 |
| 热搜词 | 模板或搜索统计 | 无 | 解析首页热搜 / 后台配置 JSON |
| 更新日历 | `vod_weekday` | 无筛选 | 先补字段；否则用最近更新 + 星期推断 |

### B.5 本站现成 URL（哇TV）

```text
# 周热门电影 / 电视剧（App 轮播已用）
https://154.12.29.28/index.php/vod/show/id/1/by/hits_week.html
https://154.12.29.28/index.php/vod/show/id/2/by/hits_week.html

# 总排行
https://154.12.29.28/index.php/label/rank.html

# 搜索（wd 关键词）
https://154.12.29.28/index.php/vod/search/wd/{关键词}.html

# 详情数据（含 hits / level / weekday 字段）
https://154.12.29.28/api.php/provide/vod/?ac=detail&ids=3185
```

---

*文档版本：2026-08-30 · 面向苹果 CMS V10 通用 JSON 接口*
