# 三张牌阵升级：Divination 单卡字段改为 cards JSON 数组
# 旧单卡缓存数据无历史价值（每日占卜零点即刷新），直接清空后重新抽牌。

from django.db import migrations, models


def clear_old_divinations(apps, schema_editor):
    Divination = apps.get_model('foodmap', 'Divination')
    Divination.objects.all().delete()


class Migration(migrations.Migration):

    dependencies = [
        ('foodmap', '0016_chatsession'),
    ]

    operations = [
        migrations.RunPython(clear_old_divinations, migrations.RunPython.noop),
        migrations.RemoveField(
            model_name='divination',
            name='card_name',
        ),
        migrations.RemoveField(
            model_name='divination',
            name='keyword',
        ),
        migrations.RemoveField(
            model_name='divination',
            name='orientation',
        ),
        migrations.AddField(
            model_name='divination',
            name='cards',
            field=models.JSONField(default=list, verbose_name='三张牌'),
        ),
    ]
