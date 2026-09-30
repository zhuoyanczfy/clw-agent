# AppConfig.value 扩为 TextField：容纳「星语」彩蛋等较长的 JSON 配置

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('foodmap', '0022_plantbed_plantbeditem'),
    ]

    operations = [
        migrations.AlterField(
            model_name='appconfig',
            name='value',
            field=models.TextField(blank=True, default='', verbose_name='配置值'),
        ),
    ]
