# -*- coding: utf-8 -*-
"""把完整菜库（dishes_full.py）导入数据库。

用法：
    python manage.py seed_dishes            # 默认 80 道全量导入（upsert，可重复执行）
    python manage.py seed_dishes --count 40 # 只导前 40 道
"""
from django.core.management.base import BaseCommand, CommandError

from foodmap.models import Dish


class Command(BaseCommand):
    help = '从 dishes_full.py 导入每日美食库到数据库（按 slug upsert）'

    def add_arguments(self, parser):
        parser.add_argument('--count', type=int, default=0, help='只导入前 N 道（0 = 全部）')

    def handle(self, *args, **options):
        try:
            from foodmap.dishes_full import DISHES_FULL
        except ImportError as exc:
            raise CommandError(f'找不到 dishes_full.py：{exc}')

        count = options['count']
        dishes = DISHES_FULL if not count else DISHES_FULL[:count]

        created = updated = 0
        for idx, item in enumerate(dishes):
            dish, was_created = Dish.objects.update_or_create(
                slug=item['slug'],
                defaults={
                    'name': item['name'],
                    'category': item['category'],
                    'description': item.get('description', ''),
                    'ingredients': item.get('ingredients', ''),
                    'steps': item.get('steps', ''),
                    'image_url': item.get('image_url', ''),
                    'sort': idx,
                    'enabled': True,
                },
            )
            if was_created:
                created += 1
            else:
                updated += 1

        self.stdout.write(
            self.style.SUCCESS(f'导入完成：新建 {created} 道，更新 {updated} 道，共 {len(dishes)} 道')
        )
