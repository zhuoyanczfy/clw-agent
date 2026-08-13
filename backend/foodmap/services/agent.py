"""轻量 Agent 层：MD 定义的推荐官 + function calling 工具轮编排。

借鉴 ops-auto-agent 的模式（MD 定义 agent + 工具注册表），但不引入 CrewAI：
- foodmap/agents/recommender/agent.md：推荐官定义（frontmatter + H2 分节），
  改文件即生效（mtime 指纹缓存重建）
- 执行协议：第一轮非流式带 tools 调 DeepSeek -> 拿到 tool_calls 后执行注册表
  中的工具函数 -> 组装 role=tool 消息交给第二轮（流式）出最终回复
"""
import json
import logging
import os

import yaml

from foodmap.services.tools.registry import TOOL_REGISTRY

logger = logging.getLogger(__name__)

AGENTS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'agents')

# agent.md 加载失败时的兜底 system prompt（保持旧版行为）
_FALLBACK_SYSTEM_PROMPT = """你是"南京美食推荐官"，一位熟悉南京餐饮的资深本地美食向导，正在和一位记录南京美食足迹的用户对话。

用户的历史用餐画像：
---
{profile}
---

行为准则：
1. 根据用户画像与对话需求，推荐南京真实存在的餐厅，默认每次给出 2-3 家，不要推荐用户已去过的餐厅。
2. 回复亲切自然，可追问偏好（口味/预算/区/人数），但一次最多问 2 个问题。
3. 每当给出具体餐厅推荐时，在回复末尾用 ```json 代码块输出结构化卡片，格式：
   [{{"name": "餐厅名", "district": "区名", "reason": "一句推荐理由", "per_capita": 人均数字,
     "rating": 评分, "address": "地址", "amap_id": "高德POI ID", "restaurant_id": 数据库ID,
     "photos": [], "tags": [], "image": ""}}]
   per_capita 未知时填 0；photos/tags/image 从工具返回原样带回，没有则给空数组或空字符串。
4. 不确定的信息要诚实说明，不要编造离谱的价格或地址。
5. 全程使用简体中文。"""

_SECTION_MAP = {
    'goal': 'goal',
    'backstory': 'backstory',
    'task template': 'task_template',
    'expected output': 'expected_output',
}

_CACHE = {}  # path -> (mtime, dict)


def _split_frontmatter(text):
    """拆分 YAML frontmatter 与正文，返回 (frontmatter_dict, body_str)。"""
    if text.startswith('---'):
        parts = text.split('---', 2)
        if len(parts) >= 3:
            try:
                front = yaml.safe_load(parts[1]) or {}
            except yaml.YAMLError:
                front = {}
            return front, parts[2]
    return {}, text


def _parse_sections(body):
    """按 `## ` 标题把正文切成 {规范化标题: 内容} 字典。"""
    sections = {}
    current_key = None
    buffer = []
    for line in body.splitlines():
        if line.startswith('## '):
            if current_key is not None:
                sections[current_key] = '\n'.join(buffer).strip()
            current_key = line[3:].strip().lower()
            buffer = []
        elif current_key is not None:
            buffer.append(line)
    if current_key is not None:
        sections[current_key] = '\n'.join(buffer).strip()
    return sections


def _load_agent_md():
    """读取并解析 recommender/agent.md，带 mtime 缓存；失败返回 None。"""
    path = os.path.join(AGENTS_DIR, 'recommender', 'agent.md')
    try:
        mtime = os.path.getmtime(path)
    except OSError:
        logger.warning('未找到 agent 定义文件: %s', path)
        return None
    cached = _CACHE.get(path)
    if cached and cached[0] == mtime:
        return cached[1]
    try:
        with open(path, 'r', encoding='utf-8') as f:
            text = f.read()
    except OSError as exc:
        logger.warning('读取 agent.md 失败: %s', exc)
        return None
    front, body = _split_frontmatter(text)
    sections = _parse_sections(body)
    definition = {
        'name': front.get('name') or 'recommender',
        'role': front.get('role', ''),
        'tools': front.get('tools') or [],
    }
    for heading, value in sections.items():
        attr = _SECTION_MAP.get(heading)
        if attr:
            definition[attr] = value
    _CACHE[path] = (mtime, definition)
    return definition


def build_system_prompt(profile: str, task: str) -> str:
    """构建 system prompt：Goal + Backstory + Task Template（注入画像与当前任务）。

    agent.md 加载失败时回退到内置常量，保证服务不中断。
    """
    definition = _load_agent_md()
    if not definition or not definition.get('task_template'):
        return _FALLBACK_SYSTEM_PROMPT.format(profile=profile)

    parts = []
    if definition.get('goal'):
        parts.append(definition['goal'].replace('{profile}', profile))
    if definition.get('backstory'):
        parts.append(definition['backstory'])
    template = definition['task_template'].replace('{profile}', profile).replace('{task}', task)
    parts.append(template)
    return '\n\n'.join(parts)


def execute_tool_calls(tool_calls):
    """执行 assistant 返回的 tool_calls，返回 role=tool 的结果消息列表。

    tool_calls: [{'id': ..., 'type': 'function', 'function': {'name': ..., 'arguments': 'json'}}]
    """
    results = []
    for tc in tool_calls or []:
        fn = tc.get('function') or {}
        name = fn.get('name', '')
        try:
            args = json.loads(fn.get('arguments') or '{}')
            if not isinstance(args, dict):
                args = {}
        except ValueError:
            args = {}
        func = TOOL_REGISTRY.get(name)
        if func is None:
            content = json.dumps({'error': f'未知工具: {name}'}, ensure_ascii=False)
        else:
            try:
                content = func(**args)
            except Exception as exc:  # 工具异常回传给模型，不让整轮对话崩溃
                logger.exception('工具 %s 执行失败', name)
                content = json.dumps({'error': f'工具执行失败: {exc}'}, ensure_ascii=False)
        results.append({
            'role': 'tool',
            'tool_call_id': tc.get('id', ''),
            'content': content,
        })
    return results
