"""真实餐厅检索工具：AI 推荐前查询本地真实餐厅库（高德导入数据）。

返回字段除基础信息外，还包含推荐卡片所需的图文素材：
- photos：高德门店照片（title/url 数组）
- tags：特色菜标签
- cost：人均消费
- image：主图 URL（photos 第一张，无照片时用高德静态地图兜底）

数据来源：餐厅导入时存了基础字段，photos/tag/cost 采取「推荐时增量回填」
——只对即将被推荐的餐厅实时查询高德补全，避免全库 2.5 万家的海量调用。
"""
import json
import logging
import time

from foodmap.models import Restaurant
from foodmap.services import amap
from foodmap.services.amap import wgs84_to_gcj02

logger = logging.getLogger(__name__)

# 每次推荐最多实时补查的餐厅数（按评分从高到低取，控制工具耗时与高德 QPS）
ENRICH_LIMIT = 3


def _parse_photos(raw):
    """photos 存 TextField JSON，解析失败返回 []。"""
    try:
        data = json.loads(raw) if raw else []
        return data if isinstance(data, list) else []
    except ValueError:
        return []


def _static_map_url(lng, lat):
    """高德静态地图（无门店照片时的兜底图），坐标需转 GCJ-02。"""
    if lng is None or lat is None:
        return ''
    try:
        key = amap._api_key()
    except amap.AMAPError:
        return ''
    glng, glat = wgs84_to_gcj02(lng, lat)
    return (
        f'{amap.AMAP_BASE_URL}/v3/staticmap?location={glng:.6f},{glat:.6f}'
        f'&zoom=16&size=600*360&markers=mid,0xE0528A,A:{glng:.6f},{glat:.6f}'
        f'&key={key}'
    )


def _enrich(restaurants, limit=ENRICH_LIMIT):
    """对缺照片的候选餐厅实时补查高德（按店名搜索匹配 amap_id），回填数据库。

    单次最多补查 limit 家（按评分降序），失败静默降级，不影响推荐流程。
    """
    enriched = 0
    for r in restaurants:
        if enriched >= limit:
            break
        if _parse_photos(r.photos):
            continue  # 已有照片，无需补查
        if not r.amap_id:
            continue
        try:
            pois = amap.search_text(r.name, city='南京')
        except amap.AMAPError as exc:
            logger.warning('补查 %s 照片失败: %s', r.name, exc)
            continue
        match = next((p for p in pois if p.get('id') == r.amap_id), None)
        if match is None:
            continue
        photos = [
            {'title': ph.get('title') or '', 'url': ph.get('url') or ''}
            for ph in (match.get('photos') or [])
            if ph.get('url')
        ]
        biz = match.get('biz_ext') or {}
        cost = None
        try:
            cost = float(biz.get('cost') or '') or None
        except (TypeError, ValueError):
            cost = None
        tag = (match.get('tag') or '')[:300]
        if not photos and not tag and cost is None:
            continue  # 高德也没数据，不写库
        r.photos = json.dumps(photos, ensure_ascii=False)
        r.tag = tag
        r.cost = cost
        r.save(update_fields=['photos', 'tag', 'cost'])
        enriched += 1
        time.sleep(0.4)  # 控制高德 QPS
    return restaurants


def search_restaurants(keyword: str, district: str = '') -> str:
    """按名称关键词（+可选区名）搜索本地真实餐厅库，返回 JSON 字符串列表。

    结果按高德评分降序取前 10 家，字段：
    id/name/address/district/rating/amap_id/photos/tags/cost/image。
    无命中返回空数组 []（调用方应诚实告知用户）。
    """
    qs = Restaurant.objects.filter(name__icontains=keyword)
    if district:
        qs = qs.filter(district__name=district)
    qs = qs.order_by('-rating', 'name')[:10]
    restaurants = _enrich(list(qs))
    results = [
        {
            'id': r.pk,
            'name': r.name,
            'address': r.address or '',
            'district': r.district.name if r.district else '',
            'rating': r.rating,
            'amap_id': r.amap_id or '',
            'photos': _parse_photos(r.photos),
            'tags': [t for t in (r.tag or '').split(',') if t.strip()],
            'cost': r.cost,
            'image': (_parse_photos(r.photos) or [{}])[0].get('url')
            or _static_map_url(r.lat, r.lng),
        }
        for r in restaurants
    ]
    return json.dumps(results, ensure_ascii=False)
