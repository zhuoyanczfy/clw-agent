# -*- coding: utf-8 -*-
"""收藏快照化：FavoriteDish 从强关联菜库改为「关联可选 + 内容快照」。

每日菜单（菜谱池）的菜不在 Dish 表里，收藏时存快照字段以便展示；
存量行迁移时从关联菜库补齐快照（slug = 菜库 slug）。
"""
from django.db import migrations, models
import django.db.models.deletion


def backfill_snapshot(apps, schema_editor):
    """存量收藏行：从关联菜库菜品补齐快照字段。"""
    FavoriteDish = apps.get_model('foodmap', 'FavoriteDish')
    for fav in FavoriteDish.objects.select_related('dish').iterator():
        dish = fav.dish
        if dish is None:
            continue
        fav.slug = dish.slug
        fav.name = dish.name
        fav.category = dish.category
        fav.description = dish.description
        fav.ingredients = dish.ingredients
        fav.steps = dish.steps
        fav.image_url = dish.image_url
        fav.save(update_fields=[
            'slug', 'name', 'category', 'description',
            'ingredients', 'steps', 'image_url',
        ])


class Migration(migrations.Migration):

    dependencies = [
        ('foodmap', '0017_divination_three_cards'),
    ]

    operations = [
        migrations.AlterField(
            model_name='favoritedish',
            name='dish',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='favorite',
                to='foodmap.dish',
                verbose_name='关联菜库菜品',
            ),
        ),
        migrations.AddField(
            model_name='favoritedish',
            name='slug',
            field=models.CharField(blank=True, max_length=100, verbose_name='收藏标识'),
        ),
        migrations.AddField(
            model_name='favoritedish',
            name='name',
            field=models.CharField(blank=True, max_length=100, verbose_name='菜名'),
        ),
        migrations.AddField(
            model_name='favoritedish',
            name='category',
            field=models.CharField(blank=True, max_length=50, verbose_name='菜系/分类'),
        ),
        migrations.AddField(
            model_name='favoritedish',
            name='description',
            field=models.TextField(blank=True, verbose_name='专属文案'),
        ),
        migrations.AddField(
            model_name='favoritedish',
            name='ingredients',
            field=models.TextField(blank=True, verbose_name='材料用量'),
        ),
        migrations.AddField(
            model_name='favoritedish',
            name='steps',
            field=models.TextField(blank=True, verbose_name='制作方法'),
        ),
        migrations.AddField(
            model_name='favoritedish',
            name='image_url',
            field=models.CharField(blank=True, max_length=500, verbose_name='成品图'),
        ),
        migrations.RunPython(backfill_snapshot, migrations.RunPython.noop),
        migrations.AlterField(
            model_name='favoritedish',
            name='slug',
            field=models.CharField(max_length=100, unique=True, verbose_name='收藏标识'),
        ),
    ]
