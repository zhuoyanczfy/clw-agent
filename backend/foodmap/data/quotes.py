"""hitokoto.cn（一言）API 客户端：开源句子数据源。

接口文档：https://developer.hitokoto.cn/sentence/
使用条款：MIT 协议，可自由使用；建议附加一言链接（hitokoto.cn?uuid=[uuid]）。
"""

import random

import requests

API_URL = 'https://v1.hitokoto.cn/'
# 文学(d) + 哲学(k) + 网易云(j) + 诗词(i) + 影视(h) + 抖机灵(l)，
# 治愈系为主、适当轻松幽默，符合"好句好段"定位
CATEGORIES = ['d', 'k', 'i', 'j', 'h', 'l']
# 句子长度：适合展示，太短没内容，太长不适合推送
MIN_LENGTH = 15
MAX_LENGTH = 80

# 分类码 → 中文名 + Pixabay 配图候选关键词（每类多个，拉句时随机选一个，
# 避免同一分类反复搜同一关键词导致配图高度重复）
CATEGORY_MAP = {
    'a': ('动画', ['anime scenery', 'anime wallpaper', 'cartoon landscape', 'japan anime']),
    'b': ('漫画', ['manga art', 'comic art', 'illustration art', 'manga']),
    'c': ('游戏', ['game landscape', 'fantasy landscape', 'gaming', 'pixel art']),
    'd': ('文学', ['library books', 'old books', 'books reading', 'vintage books', 'bookstore', 'literature']),
    'e': ('原创', ['writing journal', 'notebook pen', 'diary writing', 'handwritten']),
    'f': ('来自网络', ['digital art', 'network technology', 'internet', 'abstract digital']),
    'g': ('其他', ['abstract art', 'colorful abstract', 'minimal art', 'texture art']),
    'h': ('影视', ['cinema film', 'film camera', 'movie theater', 'retro cinema']),
    'i': ('诗词', ['poetry ink', 'ink painting', 'chinese painting', 'calligraphy brush']),
    'j': ('网易云', ['music notes', 'piano keys', 'vinyl record', 'headphones music']),
    'k': ('哲学', ['zen meditation', 'zen garden', 'misty mountains', 'quiet lake',
                   'forest light', 'starry sky', 'moonlight night']),
    'l': ('抖机灵', ['funny creative', 'playful color', 'creative art']),
}
# 未知分类的兜底候选关键词
_DEFAULT_KEYWORDS = ['nature landscape', 'mountain sunset', 'sky clouds', 'green forest']


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
    entry = CATEGORY_MAP.get(type_code)
    if entry is None:
        category_name, keywords = '其他', _DEFAULT_KEYWORDS
    else:
        category_name, keywords = entry
    # 同类句子每次随机换一个配图关键词，扩大配图来源
    image_keyword = random.choice(keywords)

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
