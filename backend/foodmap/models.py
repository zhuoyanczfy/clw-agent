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
    photos = models.TextField('门店照片', blank=True, help_text='JSON 数组 [{"title","url"}]，推荐官卡片用')
    tag = models.CharField('特色菜标签', max_length=300, blank=True, help_text='高德 tag 字段，逗号分隔')
    cost = models.FloatField('人均消费(元)', null=True, blank=True)

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


class Dish(models.Model):
    """每日美食库：菜名、菜系、专属文案、材料用量、制作方法与成品图。

    slug 对应旧内置库的 id（如 tomato-beef），APP 收藏按 slug 存储，迁移后保持稳定。
    ingredients / steps 每行一条，APP 端按行渲染。
    """

    slug = models.SlugField('标识', max_length=50, unique=True)
    name = models.CharField('菜名', max_length=50)
    category = models.CharField('菜系/分类', max_length=20, db_index=True)
    description = models.TextField('专属文案', blank=True)
    ingredients = models.TextField('材料用量', blank=True, help_text='每行一条，如「牛腩 500 克」')
    steps = models.TextField('制作方法', blank=True, help_text='每行一步')
    image_url = models.URLField('成品图', max_length=500, blank=True)
    sort = models.IntegerField('排序', default=0, help_text='数字越小越靠前，决定每日轮换顺序')
    enabled = models.BooleanField('启用', default=True)

    class Meta:
        verbose_name = '每日美食'
        verbose_name_plural = '每日美食'
        ordering = ['sort', 'id']

    def __str__(self):
        return self.name


class FavoriteDish(models.Model):
    """每日美食收藏：APP 内收藏想吃的菜（单用户，一道菜一条记录）。

    旧版收藏存 APP 本地（SharedPreferences），本模型上云后 APP 启动时把
    本地收藏迁到云端，后续云端为准、本地仅做离线缓存。
    """

    dish = models.OneToOneField(
        Dish, on_delete=models.CASCADE, related_name='favorite', verbose_name='菜品'
    )
    created_at = models.DateTimeField('收藏时间', auto_now_add=True)

    class Meta:
        verbose_name = '美食收藏'
        verbose_name_plural = '美食收藏'
        ordering = ['-created_at']

    def __str__(self):
        return self.dish.name


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
