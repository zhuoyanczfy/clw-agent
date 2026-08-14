"""Unsplash 官方 API 客户端：好句配图。

配置从项目根目录 config/config.ini 读取（裸键值对格式）：
    UNSPLASH_ACCESS_KEY=...   # https://unsplash.com/developers 申请（免费 50 请求/小时）

注意：新键必须加在 [deploy] 节之前，否则会被解析进 deploy 节读不到。
"""
import configparser
from pathlib import Path

import requests

CONFIG_PATH = Path(__file__).resolve().parent.parent.parent / 'config' / 'config.ini'


def _access_key():
    try:
        raw = CONFIG_PATH.read_text(encoding='utf-8')
    except FileNotFoundError:
        return ''
    parser = configparser.ConfigParser()
    parser.read_string('[default]\n' + raw)
    return parser['default'].get('UNSPLASH_ACCESS_KEY', '').strip()


def fetch_cover_url(keyword, width=800, height=600):
    """按关键词随机取一张横版图，返回 images.unsplash.com 直链；未配置或失败返回空串。"""
    key = _access_key()
    if not key:
        return ''
    try:
        resp = requests.get(
            'https://api.unsplash.com/photos/random',
            params={'query': keyword or 'landscape', 'orientation': 'landscape'},
            headers={'Authorization': f'Client-ID {key}'},
            timeout=10,
        )
        resp.raise_for_status()
        urls = (resp.json().get('urls') or {})
        raw = urls.get('raw') or urls.get('regular') or ''
    except (requests.RequestException, ValueError):
        return ''
    if not raw:
        return ''
    return f'{raw}&w={width}&h={height}&fit=crop&q=80'
