"""Pixabay 配图服务：好句配图。

配置从项目根目录 config/config.ini 读取（裸键值对格式）：
    PIXABAY_API_KEY=...   # https://pixabay.com/api/docs/ 申请（免费 100 请求/小时，支持中文关键词）

注意：新键必须加在 [deploy] 节之前，否则会被解析进 deploy 节读不到。
"""
import configparser
import random
from pathlib import Path

import requests

CONFIG_PATH = Path(__file__).resolve().parent.parent.parent / 'config' / 'config.ini'

# 配图失败时的兜底意境图（直链稳定可访问，无 API 额度消耗）
DEFAULT_IMAGE_URL = 'https://cdn.pixabay.com/photo/2019/02/21/11/43/forest-4012628_960_720.jpg'


def _api_key():
    try:
        raw = CONFIG_PATH.read_text(encoding='utf-8')
    except FileNotFoundError:
        return ''
    parser = configparser.ConfigParser()
    parser.read_string('[default]\n' + raw)
    return parser['default'].get('PIXABAY_API_KEY', '').strip()


def fetch_cover_url(keyword, exclude=None):
    """按关键词随机取一张横版图，返回 Pixabay 直链；未配置或失败返回空串。

    keyword: 搜索关键词；exclude: 最近已用过的图片 URL 集合（去重，避免重复出图）。
    Pixabay 支持中文关键词，图片质量高且免费额度充足。
    只在以下场景调用：
    - 每日好句首次生成（当天第一次请求）
    - 再来一条（每次请求新随机句子）

    历史好句直接返回 DB 中缓存的 image_url，不会调用此函数。
    """
    key = _api_key()
    if not key:
        return ''
    try:
        resp = requests.get(
            'https://pixabay.com/api/',
            params={
                'key': key,
                'q': keyword or '风景',
                'image_type': 'photo',
                'orientation': 'horizontal',
                # 单页多取几张再随机，避免每次都在同一小批图里打转
                'per_page': 30,
                'lang': 'zh',
            },
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()
        hits = data.get('hits') or []
        if not hits:
            return ''
        exclude = exclude or set()
        # 优先从未用过的图里随机选；偶尔全部撞车时退而随机选一张（低概率）
        pool = [h for h in hits if h.get('largeImageURL') not in exclude] or hits
        # largeImageURL: 1920px 宽，适合缩放到 800x600
        image_url = random.choice(pool).get('largeImageURL') or ''
    except (requests.RequestException, ValueError):
        return ''
    return image_url
