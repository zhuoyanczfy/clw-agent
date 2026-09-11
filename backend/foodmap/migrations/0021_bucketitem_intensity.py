# Generated for 植物园「想实现程度」分级（种草/种花/种树）

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('foodmap', '0020_bucketitem_bucketphoto'),
    ]

    operations = [
        migrations.AddField(
            model_name='bucketitem',
            name='intensity',
            field=models.IntegerField(
                default=1, help_text='1~3：种草/种花/种树，越大越想要', verbose_name='想实现程度'
            ),
        ),
        migrations.AlterModelOptions(
            name='bucketitem',
            options={
                'ordering': ['-intensity', 'sort_order', '-created_at'],
                'verbose_name': '植物园',
                'verbose_name_plural': '植物园',
            },
        ),
    ]
