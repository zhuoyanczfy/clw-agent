# 南京美食足迹 · Django API 后端 🍜

「专属美食关怀」APP 的数据中枢：南京真实餐厅库、用餐记录、待尝清单、AI 推荐官全部由本后端提供，APP 通过 REST API 调用获取数据。

## 功能

- **纯 REST API**：区 / 餐厅 / 用餐记录（含照片）/ 待尝清单 / AI 推荐官全部端点化，供 Flutter APP 调用（无网页视图）
- **每日美食推荐**：`/api/dish/today/` 按日期轮换（与 APP 内置算法一致）
- **分区地图数据**：`/api/districts.geojson` 下发南京 11 区划（APP 用 flutter_map 分区高亮），`/api/districts/` 附带各区餐厅数/足迹数
- **用餐记录**：餐厅 + 日期 + 星星评分 + 人均消费 + 心情标签 + 点评正文 + 照片，支持增删改（multipart 上传）
- **两种录入方式**：选择已有餐厅，或直接新建餐厅（自动归入所选区）
- **AI 智能推荐**：与"南京美食推荐官"多轮对话（DeepSeek，SSE 流式）。推荐官由 `foodmap/agents/recommender/agent.md` 定义（改文件即生效），通过 function calling 调用工具查询本地真实餐厅库，只从查询结果中推荐（查无结果会诚实说明），推荐卡片展示真实评分/地址并一键收藏到待尝清单
- **真实餐厅数据**：一键从高德导入南京全部真实餐饮 POI（名称/地址/坐标/评分），AI 推荐直接关联数据库真实餐厅（按高德 POI ID），未关联的卡片才走高德在线校验兜底
- **Django Admin 后台**：随时补录/管理数据

## 技术栈

- Django 4.2 LTS + Python 3.10 + SQLite（零外部依赖）
- 纯 JSON API（`JsonResponse` + `csrf_exempt`，无 DRF 依赖）
- 阿里 DataV 南京区划 GeoJSON（无需申请任何地图 API Key）
- DeepSeek Chat API（OpenAI 兼容，流式 SSE 输出），配置见 `config/config.ini`（`DEEPSEEK_API_KEY` / `DEEPSEEK_BASE_URL`）
- 轻量 Agent 层：MD 定义 Agent（`foodmap/agents/recommender/agent.md`）+ 工具注册表（`foodmap/services/tools/`）+ OpenAI 兼容 function calling，不引入 CrewAI
- 高德地图 Web 服务 API（POI 搜索，个人免费 Key），配置见 `config/config.ini`（`MAP_KEY`）

## 快速开始

```powershell
# 1. 创建并激活虚拟环境（Python 3.10）
py -3.10 -m venv .venv
.\.venv\Scripts\activate

# 2. 安装依赖
pip install -r requirements.txt

# 3. 初始化数据库（可选：播种演示数据）
python manage.py migrate
python manage.py seed_demo            # 11 区 + 19 家示例餐厅 + 20 条记录
python manage.py seed_demo --flush    # 清空餐厅/记录后重新播种

# 4. 导入真实餐厅数据（可选，需 config.ini 配好 MAP_KEY）
python manage.py import_amap_poi            # 全量导入南京 11 区餐饮 POI
python manage.py import_amap_poi --districts 鼓楼区,玄武区   # 只导入指定区
python manage.py import_amap_poi --limit-per-grid 2 --dry-run  # 快速试跑（不写库）

# 5. 启动
python manage.py runserver 0.0.0.0:8000
```

- 健康检查：`http://127.0.0.1:8000/api/health/`
- 今日美食：`http://127.0.0.1:8000/api/dish/today/`

## 数据管理

- 后台管理：先 `python manage.py createsuperuser` 创建管理员，再访问 http://127.0.0.1:8000/admin
- 命令行播种：见上（`seed_demo`）

## 让 APP 连接后端

1. 电脑跑起服务：`python manage.py runserver 0.0.0.0:8000`
2. 手机连同一 WiFi，在 APP「设置」页 → 后端服务填 `http://<电脑局域网IP>:8000`（用 `ipconfig` 查看 IPv4 地址），测试连接通过后保存
3. 足迹页 / 推荐官 / 待尝清单自动走后端数据

- **不在同一网络**：用内网穿透工具（如 cpolar / natapp / frp）将 8000 端口映射到公网，或部署到公网服务器（见下文生产部署），把公网地址填进 APP 设置页即可，APP 无需重新打包

## 项目结构

```
├── manage.py
├── requirements.txt
├── config/                  # Django 项目配置 + config.ini（API Key 等自定义配置）
├── foodmap/                 # 业务应用（纯 REST API）
│   ├── models.py            # 行政区 / 餐厅 / 用餐记录 / 待尝清单
│   ├── views.py             # 全部 API 视图（JsonResponse + SSE 流式聊天）
│   ├── urls.py              # 17 个 /api/ 路由（见根 README 主要 API 表）
│   ├── dishes_data.py       # 40 道美食库（每日推荐数据源，与 APP 内置一致）
│   ├── agents/recommender/agent.md   # 推荐官定义（frontmatter + Goal/Backstory/Task Template/Expected Output）
│   ├── services/            # llm.py（DeepSeek 客户端）+ profile.py（口味画像）
│   │   ├── agent.py         # agent.md 解析（mtime 缓存）+ system prompt 构建 + 工具轮编排
│   │   └── tools/           # 工具注册表 registry.py + search_restaurants 实现
│   ├── geodata/             # 南京区划 GeoJSON
│   ├── management/commands/seed_demo.py
│   └── migrations/          # 数据库迁移
├── media/                   # 用户上传的用餐照片（不入库）
└── deploy/                  # 生产部署（Nginx + Gunicorn + MySQL）
```

## Agent 架构（AI 推荐）

```
用户消息 → chat 视图
         ├─ 第 1 轮（非流式 + tools 参数）→ DeepSeek 决定是否调工具
         │     ├─ 返回 tool_calls → 执行 search_restaurants（查本地 Restaurant 表）
         │     │                    → 组装 role=tool 消息 → 第 2 轮流式出最终回复
         │     └─ 直接回答（寒暄/追问偏好）→ 一次性下发
         └─ 会话历史只存 user/assistant 文本轮，工具轮消息不入 session
```

- **Agent 定义与提示词解耦**：人设/行为准则写在 `foodmap/agents/recommender/agent.md`，改完即生效（mtime 指纹缓存），无需改代码
- **工具注册表**：`foodmap/services/tools/registry.py` 一行登记一个新工具；`search_restaurants(keyword, district)` 按名称模糊查询真实餐厅库，按评分取 top 10，返回 JSON（含 rating/address/amap_id）
- **强制真实**：Task Template 要求必须先用工具查询、只从结果中推荐；结果为空时 AI 诚实说明；卡片自带 `amap_id` 直接展示真实评分/地址，前端仅在缺 `amap_id` 时调高德在线校验兜底

## 生产部署

见 [`deploy/`](deploy/) 目录：

- `deploy.sh` — Ubuntu 22.04 一键部署（Nginx + Gunicorn + MySQL + Let's Encrypt）
- `nginx.conf` / `gunicorn.service` — 站点与守护进程模板（注意 SSE 需 `proxy_buffering off`）
- `backup.sh` — 每日备份（mysqldump + media + config.ini，保留 14 份）

部署要点：

1. 生产环境在 `config/config.ini` 的 `[deploy]` 节配置：`env=prod`、`secret_key`、`allowed_hosts`（域名）、MySQL 连接参数；本地开发保持 `env=dev`（SQLite）互不影响
2. 数据库迁移：本地 `dumpdata` 导出 → 服务器 `migrate` + `loaddata` 导入，`media/` 目录整体同步
3. 高德 `MAP_KEY` 需在控制台把服务器公网 IP 加入白名单

## 后续可做

- 餐厅经纬度批量补全（可用高德 API 按地址反查坐标，让 marker 更全）
- 数据统计（各区探店数、口味偏好）
- 双人模式：共享空间一起攒回忆
