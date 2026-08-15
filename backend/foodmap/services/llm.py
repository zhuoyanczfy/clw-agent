"""DeepSeek Chat API 客户端。

配置从项目根目录 config/config.ini 读取（裸键值对格式）：
    DEEPSEEK_API_KEY=...
    DEEPSEEK_BASE_URL=https://api.deepseek.com
    DEEPSEEK_MODEL=deepseek-chat   # 可选，缺省 deepseek-chat
"""
import configparser
from pathlib import Path

import requests

CONFIG_PATH = Path(__file__).resolve().parent.parent.parent / 'config' / 'config.ini'
DEFAULT_BASE_URL = 'https://api.deepseek.com'
DEFAULT_MODEL = 'deepseek-chat'


class LLMError(Exception):
    """LLM 调用失败（配置缺失、网络错误、API 错误等）。"""


def _read_config():
    try:
        raw = CONFIG_PATH.read_text(encoding='utf-8')
    except FileNotFoundError as exc:
        raise LLMError(f'未找到配置文件 {CONFIG_PATH}') from exc
    parser = configparser.ConfigParser()
    parser.read_string('[default]\n' + raw)
    return parser['default']


def _headers():
    cfg = _read_config()
    key = cfg.get('DEEPSEEK_API_KEY', '').strip()
    if not key:
        raise LLMError('config.ini 中缺少 DEEPSEEK_API_KEY')
    return {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {key}',
    }


def api_base_url():
    cfg = _read_config()
    return cfg.get('DEEPSEEK_BASE_URL', DEFAULT_BASE_URL).strip().rstrip('/') or DEFAULT_BASE_URL


def api_model():
    cfg = _read_config()
    return cfg.get('DEEPSEEK_MODEL', DEFAULT_MODEL).strip() or DEFAULT_MODEL


def chat(messages, temperature=0.8, timeout=60):
    """非流式调用，返回完整回复文本。

    messages: [{'role': 'system'|'user'|'assistant', 'content': str}, ...]
    """
    payload = {
        'model': api_model(),
        'messages': messages,
        'temperature': temperature,
    }
    try:
        resp = requests.post(
            f'{api_base_url()}/chat/completions',
            json=payload,
            headers=_headers(),
            timeout=timeout,
        )
        resp.raise_for_status()
        data = resp.json()
        return data['choices'][0]['message']['content']
    except LLMError:
        raise
    except requests.RequestException as exc:
        raise LLMError(f'请求 DeepSeek API 失败: {exc}') from exc
    except (KeyError, IndexError, ValueError) as exc:
        raise LLMError(f'DeepSeek API 响应格式异常: {exc}') from exc


def chat_tool_round(messages, tools, temperature=0.8, timeout=60):
    """非流式工具轮：带 tools 参数请求，返回完整 message dict。

    返回 OpenAI 兼容的 message：{'role': 'assistant', 'content': str|None,
    'tool_calls': [...]}。调用方拿到 tool_calls 后执行工具并组装第二轮请求。
    """
    payload = {
        'model': api_model(),
        'messages': messages,
        'temperature': temperature,
        'tools': tools,
    }
    try:
        resp = requests.post(
            f'{api_base_url()}/chat/completions',
            json=payload,
            headers=_headers(),
            timeout=timeout,
        )
        resp.raise_for_status()
        data = resp.json()
        return data['choices'][0]['message']
    except LLMError:
        raise
    except requests.RequestException as exc:
        raise LLMError(f'请求 DeepSeek API 失败: {exc}') from exc
    except (KeyError, IndexError, ValueError) as exc:
        raise LLMError(f'DeepSeek API 响应格式异常: {exc}') from exc


def chat_stream(messages, tools=None, temperature=0.8, timeout=120):
    """流式调用，yield (content_delta, tool_calls_delta) 二元组。

    content_delta 为文本增量（可能为空字符串）；tool_calls_delta 为原始工具调用增量
    （None 表示本轮 chunk 无工具调用）。模型在流中发出工具调用时，两者可能交错出现，
    调用方需按 index 合并 tool_calls 增量。
    """
    payload = {
        'model': api_model(),
        'messages': messages,
        'temperature': temperature,
        'stream': True,
    }
    if tools:
        payload['tools'] = tools
    try:
        resp = requests.post(
            f'{api_base_url()}/chat/completions',
            json=payload,
            headers=_headers(),
            timeout=timeout,
            stream=True,
        )
        resp.raise_for_status()
        for line in resp.iter_lines(decode_unicode=True):
            if not line or not line.startswith('data:'):
                continue
            data = line[len('data:'):].strip()
            if data == '[DONE]':
                break
            import json
            try:
                delta = json.loads(data)['choices'][0].get('delta') or {}
            except (KeyError, IndexError, ValueError):
                continue
            content = delta.get('content')
            tcs = delta.get('tool_calls')
            if content or tcs:
                yield content or '', tcs
    except LLMError:
        raise
    except requests.RequestException as exc:
        raise LLMError(f'请求 DeepSeek API 失败: {exc}') from exc
