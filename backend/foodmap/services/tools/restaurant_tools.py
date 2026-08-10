"""真实餐厅检索工具：AI 推荐前查询本地真实餐厅库（高德导入数据）。"""
import json

from foodmap.models import Restaurant


def search_restaurants(keyword: str, district: str = '') -> str:
    """按名称关键词（+可选区名）搜索本地真实餐厅库，返回 JSON 字符串列表。

    结果按高德评分降序取前 10 家，字段：id/name/address/district/rating/amap_id。
    无命中返回空数组 []（调用方应诚实告知用户）。
    """
    qs = Restaurant.objects.filter(name__icontains=keyword)
    if district:
        qs = qs.filter(district__name=district)
    qs = qs.order_by('-rating', 'name')[:10]
    results = [
        {
            'id': r.pk,
            'name': r.name,
            'address': r.address or '',
            'district': r.district.name if r.district else '',
            'rating': r.rating,
            'amap_id': r.amap_id or '',
        }
        for r in qs
    ]
    return json.dumps(results, ensure_ascii=False)
