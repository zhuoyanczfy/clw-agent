"""高德地图 Web 服务客户端。

配置从项目根目录 config/config.ini 读取（裸键值对格式）：
    MAP_KEY=...                        # 高德开放平台 Web 服务 Key
    AMAP_BASE_URL=https://restapi.amap.com  # 可选，缺省官方地址

提供两类能力：
1. search_text：关键字搜索单家餐厅（AI 推荐结果真实性校验用）
2. iter_grid_pois：按区边界切网格做多边形搜索，批量拉取餐饮 POI（导入用）

坐标系说明：高德返回 GCJ-02 坐标，本模块提供 gcj02_to_wgs84 把坐标转为
WGS-84 后入库（数据库统一存 WGS-84，前端渲染时再转回 GCJ-02 贴合底图）。
"""
import math
import time
from pathlib import Path

import requests

from .llm import CONFIG_PATH

AMAP_BASE_URL = 'https://restapi.amap.com'
# 餐饮服务分类码（含中餐/西餐/快餐/休闲餐饮/咖啡厅/酒吧等全部子类）
FOOD_TYPES = '050000'
PAGE_SIZE = 25  # 高德分页上限
MAX_PAGE = 100  # 单次请求最多翻 100 页
GRID_STEP = 0.03  # 网格步长（度，约 3.3km），控制单格 POI 数量

GCJ_A = 6378245.0
GCJ_EE = 0.00669342162296594323


class AMAPError(Exception):
    """高德 API 调用失败（配置缺失、配额不足、网络错误等）。"""


def _read_config():
    try:
        raw = CONFIG_PATH.read_text(encoding='utf-8')
    except FileNotFoundError as exc:
        raise AMAPError(f'未找到配置文件 {CONFIG_PATH}') from exc
    import configparser
    parser = configparser.ConfigParser()
    parser.read_string('[default]\n' + raw)
    return parser['default']


def _api_key():
    cfg = _read_config()
    key = cfg.get('MAP_KEY', '').strip()
    if not key:
        raise AMAPError('config.ini 中缺少 MAP_KEY（高德开放平台 Web 服务 Key）')
    return key


def _out_of_china(lng, lat):
    return not (73.66 < lng < 135.05 and 3.86 < lat < 53.55)


def _transform_lat(lng, lat):
    ret = (-100.0 + 2.0 * lng + 3.0 * lat + 0.2 * lat * lat
           + 0.1 * lng * lat + 0.2 * math.sqrt(abs(lng))
           + (20.0 * math.sin(6.0 * lng * math.pi) + 20.0 * math.sin(2.0 * lng * math.pi)) * 2.0 / 3.0
           + (20.0 * math.sin(lat * math.pi) + 40.0 * math.sin(lat / 3.0 * math.pi)) * 2.0 / 3.0
           + (160.0 * math.sin(lat / 12.0 * math.pi) + 320 * math.sin(lat * math.pi / 30.0)) * 2.0 / 3.0)
    return ret


def _transform_lng(lng, lat):
    ret = (300.0 + lng + 2.0 * lat + 0.1 * lng * lng
           + 0.1 * lng * lat + 0.1 * math.sqrt(abs(lng))
           + (20.0 * math.sin(6.0 * lng * math.pi) + 20.0 * math.sin(2.0 * lng * math.pi)) * 2.0 / 3.0
           + (20.0 * math.sin(lng * math.pi) + 40.0 * math.sin(lng / 3.0 * math.pi)) * 2.0 / 3.0
           + (150.0 * math.sin(lng / 12.0 * math.pi) + 300.0 * math.sin(lng / 30.0 * math.pi)) * 2.0 / 3.0)
    return ret


def gcj02_to_wgs84(lng, lat):
    """GCJ-02(高德) -> WGS-84(标准)，与前端 wgs84ToGcj02 互为逆运算。"""
    if _out_of_china(lng, lat):
        return lng, lat
    d_lat = _transform_lat(lng - 105.0, lat - 35.0)
    d_lng = _transform_lng(lng - 105.0, lat - 35.0)
    rad_lat = lat / 180.0 * math.pi
    magic = math.sin(rad_lat)
    magic = 1 - GCJ_EE * magic * magic
    sqrt_magic = math.sqrt(magic)
    d_lat = (d_lat * 180.0) / ((GCJ_A * (1 - GCJ_EE)) / (magic * sqrt_magic) * math.pi)
    d_lng = (d_lng * 180.0) / ((GCJ_A / sqrt_magic) * math.cos(rad_lat) * math.pi)
    return lng - d_lng, lat - d_lat


def wgs84_to_gcj02(lng, lat):
    """WGS-84(标准) -> GCJ-02(高德)，静态地图等需要 GCJ 坐标的高德服务用。"""
    if _out_of_china(lng, lat):
        return lng, lat
    d_lat = _transform_lat(lng - 105.0, lat - 35.0)
    d_lng = _transform_lng(lng - 105.0, lat - 35.0)
    rad_lat = lat / 180.0 * math.pi
    magic = math.sin(rad_lat)
    magic = 1 - GCJ_EE * magic * magic
    sqrt_magic = math.sqrt(magic)
    d_lat = (d_lat * 180.0) / ((GCJ_A * (1 - GCJ_EE)) / (magic * sqrt_magic) * math.pi)
    d_lng = (d_lng * 180.0) / ((GCJ_A / sqrt_magic) * math.cos(rad_lat) * math.pi)
    return lng + d_lng, lat + d_lat


def _request(params):
    """带重试的 GET 请求，成功返回 JSON；失败抛 AMAPError。"""
    endpoint = params.pop('_endpoint')
    params = {'key': _api_key(), **params}
    for attempt in range(3):
        try:
            resp = requests.get(f'{AMAP_BASE_URL}/v3/place/{endpoint}', params=params, timeout=15)
            data = resp.json()
        except (requests.RequestException, ValueError) as exc:
            if attempt == 2:
                raise AMAPError(f'请求高德 API 失败: {exc}') from exc
            time.sleep(1.5)
            continue
        if data.get('status') != '1':
            if data.get('infocode') == '10021' and attempt < 2:
                # QPS 超限：退避后重试
                time.sleep(1.0 + attempt)
                continue
            raise AMAPError(f"高德 API 错误: {data.get('info')} (infocode={data.get('infocode')})")
        return data
    raise AMAPError('高德 API 请求重试失败')


def search_text(keywords, city='南京', page=1, offset=PAGE_SIZE):
    """关键字搜索 POI（AI 推荐校验用），返回 pois 列表。"""
    data = _request({
        '_endpoint': 'text',
        'keywords': keywords,
        'city': city,
        'citylimit': 'true',
        'offset': str(offset),
        'page': str(page),
        'extensions': 'all',
    })
    return data.get('pois') or []


def search_polygon(polygon, types=FOOD_TYPES, page=1, offset=PAGE_SIZE):
    """多边形搜索 POI（批量导入用）。polygon: [[lng, lat], ...] 至少 3 个点。"""
    poly_str = ';'.join(f'{lng:.6f},{lat:.6f}' for lng, lat in polygon)
    data = _request({
        '_endpoint': 'polygon',
        'polygon': poly_str,
        'types': types,
        'offset': str(offset),
        'page': str(page),
        'extensions': 'all',
    })
    return data.get('pois') or []


def iter_grid_pois(grid, limit_pages=None):
    """迭代拉取一个网格内的全部餐饮 POI（去重）。

    grid: (min_lng, min_lat, max_lng, max_lat)
    若单格超过 MAX_PAGE 页（数据过多），自动切成 4 个子格递归拉取。
    """
    seen = set()

    def _pull(g, pages_left):
        lng1, lat1, lng2, lat2 = g
        mid_lng, mid_lat = (lng1 + lng2) / 2, (lat1 + lat2) / 2
        polygon = [[lng1, lat1], [lng2, lat1], [lng2, lat2], [lng1, lat2]]
        page = 1
        while True:
            pois = search_polygon(polygon, page=page)
            new_pois = [p for p in pois if p.get('id') not in seen]
            for p in new_pois:
                seen.add(p['id'])
                yield p
            if limit_pages and page >= limit_pages:
                return
            if not pois or len(pois) < PAGE_SIZE:
                return
            if page >= MAX_PAGE:
                # 数据量超上限：切成 4 个子格，父格剩余页丢弃
                yield from _pull((lng1, lat1, mid_lng, mid_lat), pages_left)
                yield from _pull((mid_lng, lat1, lng2, mid_lat), pages_left)
                yield from _pull((lng1, mid_lat, mid_lng, lat2), pages_left)
                yield from _pull((mid_lng, mid_lat, lng2, lat2), pages_left)
                return
            page += 1
            time.sleep(0.45)

    yield from _pull(grid, None)


def point_in_polygon(lng, lat, polygon):
    """射线法判断点是否在多边形内（polygon: [[lng, lat], ...]）。"""
    inside = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        xi, yi = polygon[i]
        xj, yj = polygon[j]
        if ((yi > lat) != (yj > lat)) and (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside
