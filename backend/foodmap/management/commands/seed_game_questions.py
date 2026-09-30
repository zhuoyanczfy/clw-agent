# -*- coding: utf-8 -*-
"""导入双人小游戏内置题库（每日一问 / 二选一）。

用法：
    python manage.py seed_game_questions   # 全量 upsert（按题型+题干去重，可重复执行）
"""
from django.core.management.base import BaseCommand

from foodmap.models import GameQuestion

# 每日一问：双方各答各的，都答完互相揭晓（题目偏日常与美食，适合开启话题）
DAILY_QUESTIONS = [
    '今天有什么开心的小事，想第一个告诉 TA？',
    '如果明天可以一起去吃一家店，你会选哪家？',
    '最近有哪首歌，听起来就会想到对方？',
    '今天最想对 TA 说的一句暖心话是什么？',
    '如果用一道菜形容今天的心情，会是什么？',
    '最近对方做的哪件小事让你心里一暖？',
    '这个周末最想一起做什么？',
    '你觉得 TA 最可爱的瞬间是什么时候？',
    '如果一起养一只小动物，你希望是什么？',
    '今天有没有吃到什么好吃的，想安利给 TA？',
    '小时候最爱吃的一道菜是什么？为什么？',
    '如果可以立刻出发去旅行，你想去哪儿？',
    '对方哪一个小习惯让你觉得很有安全感？',
    '今天有没有一瞬间特别想 TA？是什么时候？',
    '你最期待和 TA 一起完成的下一件事是什么？',
    '压力大的时候，你希望 TA 怎么安慰你？',
    '你觉得我们最有默契的一次是什么时候？',
    '最近学到的有趣知识，想分享给 TA 的是什么？',
    '如果明天的晚餐 TA 全权负责，你最期待什么？',
    'TA 说过哪句话让你记到现在？',
    '下班/放学后最放松的时刻是什么？',
    '你想和 TA 一起培养的小习惯是什么？',
    '今天天空好看吗？看到什么风景想拍给 TA？',
    '如果给今天打个分（1~10 分），你打几分？为什么？',
    '最近有没有什么小愿望，说出来 TA 帮你实现？',
    '你觉得 TA 适合开一家什么店？为什么？',
    '两个人一起做饭的话，你想负责哪个环节？',
    '如果只能带三样东西去无人岛，你带什么？',
]

# 二选一：各自选完互相揭晓，看默契（美食为主，混搭生活趣味）
THIS_OR_THAT = [
    ('火锅', '烧烤'),
    ('奶茶', '咖啡'),
    ('米饭', '面条'),
    ('甜豆腐脑', '咸豆腐脑'),
    ('番茄炒蛋放糖', '番茄炒蛋不放糖'),
    ('早上吃包子', '早上吃煎饼'),
    ('火锅蘸麻酱', '火锅蘸油碟'),
    ('蛋糕', '冰淇淋'),
    ('烧烤加辣', '烧烤不加辣'),
    ('螺蛳粉', '酸辣粉'),
    ('饺子', '馄饨'),
    ('看电影', '看剧'),
    ('周末睡懒觉', '周末早起'),
    ('夏天吹空调', '夏天吹风扇'),
    ('旅行看海', '旅行爬山'),
    ('City Walk', '宅家躺平'),
    ('早上洗澡', '晚上洗澡'),
    ('甜月饼', '咸月饼'),
    ('薯条', '洋葱圈'),
    ('可乐', '雪碧'),
    ('吃辣', '不吃辣'),
    ('夜宵小龙虾', '夜宵炸鸡'),
    ('面包蘸酱', '面包空口吃'),
    ('喝热水', '喝冰水'),
    ('外卖到家', '出门堂食'),
    ('先吃喜欢的', '把喜欢的留最后'),
    ('逛超市', '逛菜市场'),
    ('手机竖屏刷视频', '手机横屏看大片'),
    ('可乐加冰', '可乐常温'),
    ('披萨边吃', '披萨边不吃'),
]


class Command(BaseCommand):
    help = '导入双人小游戏内置题库（按题型+题目 upsert，可重复执行）'

    def handle(self, *args, **options):
        created = updated = 0
        for idx, content in enumerate(DAILY_QUESTIONS):
            _, was_created = GameQuestion.objects.update_or_create(
                category='daily_question',
                content=content,
                defaults={'sort': idx, 'enabled': True},
            )
            created += was_created
            updated += not was_created

        for idx, (a, b) in enumerate(THIS_OR_THAT):
            title = f'{a} vs {b}'
            _, was_created = GameQuestion.objects.update_or_create(
                category='this_or_that',
                content=title,
                defaults={'option_a': a, 'option_b': b, 'sort': idx, 'enabled': True},
            )
            created += was_created
            updated += not was_created

        self.stdout.write(
            self.style.SUCCESS(
                f'导入完成：新建 {created} 题，更新 {updated} 题'
                f'（每日一问 {len(DAILY_QUESTIONS)} + 二选一 {len(THIS_OR_THAT)}）'
            )
        )
