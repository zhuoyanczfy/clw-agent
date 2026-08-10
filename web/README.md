# 南京美食足迹 🍜

用 Django 打造的个人美食回忆地图：记录吃过的每一家餐厅、每一次用餐的点评与心情，在南京分区地图上留下自己的足迹。

## 功能

- **分区地图主界面**：南京 11 个区可点击（多边形高亮，颜色深浅表示去过几家店），去过餐厅以 🍽️ 标记在地图上，点击查看回忆
- **底部导航**：不点地图也能直接通过底部的横滑区选择条 / 区列表切换
- **用餐记录**：餐厅 + 日期 + 星星评分 + 人均消费 + 心情标签 + 点评正文，支持增删改
- **两种录入方式**：选择已有餐厅，或直接新建餐厅（自动归入所选区）
- **AI 智能推荐**：底部导航第 4 个页签，与"南京美食推荐官"多轮对话（DeepSeek）。推荐官由 `foodmap/agents/recommender/agent.md` 定义（改文件即生效），通过 function calling 调用工具查询本地真实餐厅库，只从查询结果中推荐（查无结果会诚实说明），推荐卡片展示真实评分/地址并一键收藏到待尝清单
- **真实餐厅数据**：一键从高德导入南京全部真实餐饮 POI（名称/地址/坐标/评分），AI 推荐直接关联数据库真实餐厅（按高德 POI ID），未关联的卡片才走高德在线校验兜底
- **Django Admin 后台**：随时补录/管理数据

## 技术栈

- Django 4.2 LTS + Python 3.10 + SQLite（零外部依赖）
- Leaflet + 阿里 DataV 南京区划 GeoJSON（无需申请任何地图 API Key）
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
python manage.py runserver
```

访问 http://127.0.0.1:8000

## 数据管理

- 后台管理：先 `python manage.py createsuperuser` 创建管理员，再访问 http://127.0.0.1:8000/admin
- 命令行播种：见上（`seed_demo`）

## 局域网/公网分享（给 TA 用）

```powershell
python manage.py runserver 0.0.0.0:8000
```

- **同一 WiFi 下**：手机浏览器访问 `http://你的局域网IP:8000`（用 `ipconfig` 查看 IPv4 地址）
- **不在同一网络**：用内网穿透工具（如 cpolar / natapp / frp）将 8000 端口映射到公网，把公网链接发给对方

## 项目结构

```
├── manage.py
├── requirements.txt
├── config/                  # Django 项目配置 + config.ini（API Key 等自定义配置）
├── foodmap/                 # 业务应用
│   ├── models.py            # 行政区 / 餐厅 / 用餐记录 / 待尝清单
│   ├── forms.py             # 用餐记录表单（选餐厅 or 新建）
│   ├── views.py             # 页面视图 + AI 推荐 SSE 对话 / 待尝 API
│   ├── agents/recommender/agent.md   # 推荐官定义（frontmatter + Goal/Backstory/Task Template/Expected Output）
│   ├── services/            # llm.py（DeepSeek 客户端）+ profile.py（口味画像）
│   │   ├── agent.py         # agent.md 解析（mtime 缓存）+ system prompt 构建 + 工具轮编排
│   │   └── tools/           # 工具注册表 registry.py + search_restaurants 实现
│   ├── geodata/             # 南京区划 GeoJSON
│   ├── management/commands/seed_demo.py
│   └── templates/foodmap/   # 页面模板
└── static/css/style.css     # 移动端优先样式
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
