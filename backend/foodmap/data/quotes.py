"""hitokoto.cn（一言）API 客户端：开源句子数据源。

接口文档：https://developer.hitokoto.cn/sentence/
使用条款：MIT 协议，可自由使用；建议附加一言链接（hitokoto.cn?uuid=[uuid]）。
"""

import requests

API_URL = 'https://v1.hitokoto.cn/'
# 文学(d) + 哲学(k) 分类，符合"好句好段"定位
CATEGORIES = ['d', 'k']
# 句子长度：适合展示，太短没内容，太长不适合推送
MIN_LENGTH = 15
MAX_LENGTH = 80

# 分类码 → 中文名 + Unsplash 配图关键词
CATEGORY_MAP = {
    'a': ('动画', 'anime scenery'),
    'b': ('漫画', 'manga art'),
    'c': ('游戏', 'game landscape'),
    'd': ('文学', 'library books'),
    'e': ('原创', 'writing journal'),
    'f': ('来自网络', 'digital world'),
    'g': ('其他', 'abstract art'),
    'h': ('影视', 'cinema film'),
    'i': ('诗词', 'poetry ink'),
    'j': ('网易云', 'music notes'),
    'k': ('哲学', 'zen meditation'),
    'l': ('抖机灵', 'funny creative'),
}


def fetch_hitokoto():
    """从 hitokoto.cn 拉取一条随机句子。

    返回 dict：
        text / author / source / category / image_keyword / uuid / detail_url
    失败时返回 None。
    """
    params = {
        'c': CATEGORIES,
        'min_length': MIN_LENGTH,
        'max_length': MAX_LENGTH,
        'encode': 'json',
        'charset': 'utf-8',
    }
    try:
        resp = requests.get(API_URL, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()
    except (requests.RequestException, ValueError):
        return None

    type_code = data.get('type', 'g')
    category_name, image_keyword = CATEGORY_MAP.get(
        type_code, ('其他', 'abstract art')
    )

    author = (data.get('from_who') or '').strip()
    source = (data.get('from') or '').strip()

    # 有些句子没有作者或出处，用默认值
    if not author and not source:
        author = '佚名'
        source = '网络'

    return {
        'text': data.get('hitokoto', ''),
        'author': author or '佚名',
        'source': source or '未知出处',
        'category': category_name,
        'image_keyword': image_keyword,
        'uuid': data.get('uuid', ''),
        'detail_url': f'https://hitokoto.cn?uuid={data.get("uuid", "")}',
    }
