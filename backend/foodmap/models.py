from django.db import models


class District(models.Model):
    """南京市辖区（鼓楼区、玄武区等），adcode 用于与 GeoJSON 多边形匹配。"""

    name = models.CharField('区名', max_length=50, unique=True)
    adcode = models.CharField('行政区代码', max_length=10, unique=True)

    class Meta:
        verbose_name = '行政区'
        verbose_name_plural = '行政区'
        ordering = ['id']

    def __str__(self):
        return self.name


class Restaurant(models.Model):
    """餐厅，隶属某个区；lat/lng 可选，有坐标时在地图上标记。"""

    name = models.CharField('餐厅名称', max_length=100)
    district = models.ForeignKey(
        District, on_delete=models.CASCADE, related_name='restaurants', verbose_name='所属区'
    )
    address = models.CharField('地址', max_length=200, blank=True)
    lat = models.FloatField('纬度', null=True, blank=True)
    lng = models.FloatField('经度', null=True, blank=True)
    amap_id = models.CharField('高德POI ID', max_length=50, null=True, blank=True, unique=True)
    rating = models.FloatField('高德评分', null=True, blank=True)

    class Meta:
        verbose_name = '餐厅'
        verbose_name_plural = '餐厅'
        ordering = ['name']

    def __str__(self):
        return self.name

    @property
    def record_count(self):
        return self.records.count()

    @property
    def latest_record(self):
        return self.records.order_by('-date').first()


class AppConfig(models.Model):
    """APP 云端配置：键值对，Admin 修改后 APP 启动自动拉取生效（无需重打包）。"""

    key = models.CharField('配置键', max_length=50, unique=True)
    value = models.CharField('配置值', max_length=1000, blank=True, default='')
    description = models.CharField('说明', max_length=200, blank=True, default='')

    class Meta:
        verbose_name = 'APP配置'
        verbose_name_plural = 'APP配置'
        ordering = ['id']

    def __str__(self):
        return f'{self.key} = {self.value}'


class SplashImage(models.Model):
    """APP 启动加载页图片：每天随机展示一张，相邻两天不重复（由 SplashState 记录）。"""

    title = models.CharField('标题', max_length=100, blank=True)
    image = models.ImageField('图片', upload_to='splash/')
    enabled = models.BooleanField('启用', default=True)
    created_at = models.DateTimeField('上传时间', auto_now_add=True)

    class Meta:
        verbose_name = '加载页图片'
        verbose_name_plural = '加载页图片'
        ordering = ['id']

    def __str__(self):
        return self.title or f'加载页图片 #{self.pk}'


class SplashState(models.Model):
    """加载页展示状态（单例）：记录最近一次展示的日期与图片，保证相邻两天不重复。"""

    last_date = models.CharField('上次展示日期', max_length=10, blank=True)
    last_id = models.IntegerField('上次展示图片ID', null=True, blank=True)

    class Meta:
        verbose_name = '加载页状态'
        verbose_name_plural = '加载页状态'

    def __str__(self):
        return f'{self.last_date} → 图片 #{self.last_id}'


class DiningRecord(models.Model):
    """一次用餐记录：时间、评分、点评正文与回忆。"""

    RATING_CHOICES = [(i, f'{i} 星') for i in range(1, 6)]

    restaurant = models.ForeignKey(
        Restaurant, on_delete=models.CASCADE, related_name='records', verbose_name='餐厅'
    )
    date = models.DateField('用餐日期')
    rating = models.PositiveSmallIntegerField('评分', choices=RATING_CHOICES, default=4)
    comment = models.TextField('点评/回忆', blank=True)
    per_capita = models.PositiveIntegerField('人均消费(元)', null=True, blank=True)
    mood = models.CharField('心情标签', max_length=50, blank=True)
    created_at = models.DateTimeField('创建时间', auto_now_add=True)
    updated_at = models.DateTimeField('更新时间', auto_now=True)

    class Meta:
        verbose_name = '用餐记录'
        verbose_name_plural = '用餐记录'
        ordering = ['-date', '-id']

    def __str__(self):
        return f'{self.restaurant.name} · {self.date}'


class DiningRecordPhoto(models.Model):
    """用餐记录的照片，一条记录可上传多张。"""

    record = models.ForeignKey(
        DiningRecord, on_delete=models.CASCADE, related_name='photos', verbose_name='用餐记录'
    )
    image = models.ImageField('照片', upload_to='record_photos/%Y/%m/')
    created_at = models.DateTimeField('上传时间', auto_now_add=True)

    class Meta:
        verbose_name = '用餐照片'
        verbose_name_plural = '用餐照片'
        ordering = ['id']

    def __str__(self):
        return f'{self.record} 的照片 #{self.pk}'


class WishlistItem(models.Model):
    """待尝清单：AI 推荐或手动收藏的餐厅，吃过之后标记已尝。"""

    STATUS_CHOICES = [
        ('pending', '待尝'),
        ('eaten', '已尝'),
    ]
    SOURCE_CHOICES = [
        ('ai', 'AI 推荐'),
        ('manual', '手动添加'),
    ]

    name = models.CharField('餐厅名称', max_length=100)
    amap_id = models.CharField('高德POI ID', max_length=50, null=True, blank=True)
    district = models.ForeignKey(
        District, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='wishlist_items', verbose_name='所属区',
    )
    reason = models.CharField('推荐理由', max_length=300, blank=True)
    per_capita = models.PositiveIntegerField('人均消费(元)', null=True, blank=True)
    status = models.CharField('状态', max_length=10, choices=STATUS_CHOICES, default='pending')
    source = models.CharField('来源', max_length=10, choices=SOURCE_CHOICES, default='ai')
    created_at = models.DateTimeField('收藏时间', auto_now_add=True)

    class Meta:
        verbose_name = '待尝餐厅'
        verbose_name_plural = '待尝餐厅'
        ordering = ['-created_at']

    def __str__(self):
        return self.name
