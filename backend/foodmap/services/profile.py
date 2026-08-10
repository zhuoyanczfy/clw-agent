"""从本地数据库生成用户口味画像文本，注入 AI 对话的 system prompt。"""
from django.db.models import Avg, Count, Q

from foodmap.models import DiningRecord, District, Restaurant


def build_taste_profile() -> str:
    """汇总历史用餐数据，生成一段中文画像描述。"""
    lines = []

    # 足迹统计必须基于用餐记录（DiningRecord），而不是 Restaurant 表行数：
    # Restaurant 是约 2.5 万家的真实餐厅库（高德导入），不等于用户去过的数量。
    # 注意 filter(records__isnull=False) 会产生 JOIN 重复行（一家店多条记录），
    # 必须 distinct() 按餐厅去重后再 count。
    total_visited = Restaurant.objects.filter(records__isnull=False).distinct().count()
    total_records = DiningRecord.objects.count()
    lines.append(f'用户目前在南京共去过 {total_visited} 家餐厅，留下 {total_records} 条用餐记录。')

    # 区足迹同样按餐厅去重：Count('restaurants', filter=...) 统计「该区有记录的餐厅数」
    district_stats = (
        District.objects.annotate(
            visited_count=Count(
                'restaurants', distinct=True,
                filter=Q(restaurants__records__isnull=False),
            )
        )
        .filter(visited_count__gt=0)
        .order_by('-visited_count')
    )
    visited = [f'{d.name}({d.visited_count}家)' for d in district_stats]
    if visited:
        lines.append('各区足迹分布：' + '、'.join(visited) + '。')

    avg_per_capita = DiningRecord.objects.filter(per_capita__isnull=False).aggregate(avg=Avg('per_capita'))['avg']
    if avg_per_capita:
        lines.append(f'人均消费平均约 {avg_per_capita:.0f} 元。')

    high = Restaurant.objects.filter(records__rating__gte=4).distinct().select_related('district')
    high_names = [f'{r.name}({r.district.name})' for r in high]
    if high_names:
        lines.append('用户评价较高(4星及以上)的餐厅：' + '、'.join(high_names) + '。')

    low = Restaurant.objects.filter(records__rating__lte=2).distinct().select_related('district')
    low_names = [f'{r.name}({r.district.name})' for r in low]
    if low_names:
        lines.append('用户评价较低(2星及以下)的餐厅：' + '、'.join(low_names) + '。')

    comments = [
        r.comment.strip()
        for r in DiningRecord.objects.exclude(comment='').order_by('-date')[:10]
        if r.comment.strip()
    ]
    if comments:
        lines.append('用户最近的点评（供口味参考）：' + '；'.join(comments) + '。')

    return '\n'.join(lines)
