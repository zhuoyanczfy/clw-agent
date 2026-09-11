# Generated for 花坛：多株种草组合成一日游园计划（赏花日 + 时段 + 顺序）
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('foodmap', '0021_bucketitem_intensity'),
    ]

    operations = [
        migrations.CreateModel(
            name='PlantBed',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('title', models.CharField(max_length=100, verbose_name='花坛名称')),
                ('visit_date', models.DateField(blank=True, help_text='约好去把坛里的都赏一遍的日期', null=True, verbose_name='赏花日')),
                ('created_at', models.DateTimeField(auto_now_add=True, verbose_name='创建时间')),
                ('updated_at', models.DateTimeField(auto_now=True, verbose_name='更新时间')),
            ],
            options={
                'verbose_name': '花坛',
                'verbose_name_plural': '花坛',
                'ordering': ['visit_date', '-created_at'],
            },
        ),
        migrations.CreateModel(
            name='PlantBedItem',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('sort_order', models.IntegerField(default=0, help_text='游园顺序，小的在前', verbose_name='顺序')),
                ('time_note', models.CharField(blank=True, help_text='如：早上/中午/下午', max_length=20, verbose_name='时段')),
                ('bed', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='bed_items', to='foodmap.plantbed', verbose_name='所属花坛')),
                ('item', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='in_beds', to='foodmap.bucketitem', verbose_name='植物园条目')),
            ],
            options={
                'verbose_name': '花坛植物',
                'verbose_name_plural': '花坛植物',
                'ordering': ['sort_order', 'id'],
                'unique_together': {('bed', 'item')},
            },
        ),
    ]
