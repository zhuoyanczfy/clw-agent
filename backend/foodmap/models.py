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

    name = models.CharField('餐厅名称', max_length=100, db_index=True)
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


class Pet(models.Model):
    """宠物档案（猫咪名片）：生日、领养纪念日、品种等基本信息。

    单用户设计（为她家的猫定制），但模型支持多条，UI 按单猫直进详情。
    """

    GENDER_CHOICES = [
        ('male', '公'),
        ('female', '母'),
    ]

    name = models.CharField('名字', max_length=30)
    breed = models.CharField('品种', max_length=50, blank=True)
    gender = models.CharField('性别', max_length=10, choices=GENDER_CHOICES, blank=True)
    birthday = models.DateField('生日', null=True, blank=True)
    adopt_date = models.DateField('来家纪念日', null=True, blank=True)
    avatar = models.ImageField('头像', upload_to='pet_avatars/', null=True, blank=True)
    notes = models.TextField('备注', blank=True)
    created_at = models.DateTimeField('创建时间', auto_now_add=True)
    updated_at = models.DateTimeField('更新时间', auto_now=True)

    class Meta:
        verbose_name = '宠物档案'
        verbose_name_plural = '宠物档案'
        ordering = ['id']

    def __str__(self):
        return self.name


class PetPhoto(models.Model):
    """宠物照片（成长相册），一张宠物可上传多张。"""

    pet = models.ForeignKey(
        Pet, on_delete=models.CASCADE, related_name='photos', verbose_name='宠物'
    )
    image = models.ImageField('照片', upload_to='pet_photos/%Y/%m/')
    caption = models.CharField('说明', max_length=100, blank=True)
    created_at = models.DateTimeField('上传时间', auto_now_add=True)

    class Meta:
        verbose_name = '宠物照片'
        verbose_name_plural = '宠物照片'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.pet.name} 的照片 #{self.pk}'


class PetEvent(models.Model):
    """宠物事项记录：疫苗 / 驱虫 / 体重 / 其他（绝育、体检等）。

    due_date 记录下次到期时间（疫苗、驱虫），APP 到期前 7 天本地通知提醒。
    weight 仅 kind=weight 时使用（单位 kg）。
    """

    KIND_CHOICES = [
        ('vaccine', '疫苗'),
        ('deworm', '驱虫'),
        ('weight', '体重'),
        ('other', '其他'),
    ]

    pet = models.ForeignKey(
        Pet, on_delete=models.CASCADE, related_name='events', verbose_name='宠物'
    )
    kind = models.CharField('类型', max_length=10, choices=KIND_CHOICES)
    title = models.CharField('标题', max_length=100)
    date = models.DateField('日期')
    due_date = models.DateField('下次到期', null=True, blank=True)
    weight = models.FloatField('体重(kg)', null=True, blank=True)
    note = models.TextField('备注', blank=True)
    created_at = models.DateTimeField('记录时间', auto_now_add=True)

    class Meta:
        verbose_name = '宠物事项'
        verbose_name_plural = '宠物事项'
        ordering = ['-date', '-id']

    def __str__(self):
        return f'{self.pet.name} · {self.get_kind_display()} · {self.title}'


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


class Divination(models.Model):
    """每日占卜结果：按日期缓存，当天多次打开返回同一次抽牌与解读，零点自动刷新。"""

    date = models.DateField('占卜日期', unique=True)
    card_name = models.CharField('塔罗牌', max_length=50)
    orientation = models.CharField('牌向', max_length=10)  # 正位 / 逆位
    keyword = models.CharField('关键词', max_length=100, blank=True)
    reading = models.TextField('今日解读', blank=True)
    lucky = models.CharField('幸运指引', max_length=200, blank=True)
    created_at = models.DateTimeField('生成时间', auto_now_add=True)

    class Meta:
        verbose_name = '每日占卜'
        verbose_name_plural = '每日占卜'
        ordering = ['-date']

    def __str__(self):
        return f'{self.date} {self.card_name}（{self.orientation}）'


class Quote(models.Model):
    """好句好段：按日期缓存当日句子，数据源为 hitokoto.cn（一言）。"""

    date = models.DateField('日期', unique=True)
    text = models.CharField('金句', max_length=300)
    author = models.CharField('作者', max_length=50)
    source = models.CharField('出处', max_length=100)
    category = models.CharField('分类', max_length=20, blank=True)
    image_keyword = models.CharField('配图关键词', max_length=50, blank=True)
    image_url = models.CharField('配图链接', max_length=300, blank=True)
    uuid = models.CharField('一言UUID', max_length=36, blank=True)
    detail_url = models.CharField('详情链接', max_length=200, blank=True)
    created_at = models.DateTimeField('创建时间', auto_now_add=True)

    class Meta:
        verbose_name = '好句好段'
        verbose_name_plural = '好句好段'
        ordering = ['-date']

    def __str__(self):
        return f'{self.date} {self.author}《{self.source}》'


class DailyMeal(models.Model):
    """每日菜单：按日期从菜谱池（HowToCook 开源菜谱）随机选一道并缓存。

    当天首次访问时生成并落库，之后同一天返回同一道菜；
    ingredients / steps 以 JSON 数组字符串存储，APP 端按数组渲染。
    """

    date = models.DateField('日期', unique=True)
    name = models.CharField('菜名', max_length=50)
    category = models.CharField('分类', max_length=20, blank=True)
    description = models.TextField('简介', blank=True)
    ingredients = models.TextField('材料', blank=True, help_text='JSON 数组字符串')
    steps = models.TextField('步骤', blank=True, help_text='JSON 数组字符串')
    image_url = models.CharField('成品图', max_length=300, blank=True, help_text='相对路径 /media/meals/...')
    created_at = models.DateTimeField('生成时间', auto_now_add=True)

    class Meta:
        verbose_name = '每日菜单'
        verbose_name_plural = '每日菜单'
        ordering = ['-date']

    def __str__(self):
        return f'{self.date} {self.name}'


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
        indexes = [
            models.Index(fields=['restaurant', 'date'], name='record_rest_date_idx'),
            models.Index(fields=['-date'], name='record_date_idx'),
        ]

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

    name = models.CharField('餐厅名称', max_length=100, db_index=True)
    amap_id = models.CharField('高德POI ID', max_length=50, null=True, blank=True)
    district = models.ForeignKey(
        District, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='wishlist_items', verbose_name='所属区',
    )
    reason = models.CharField('推荐理由', max_length=300, blank=True)
    per_capita = models.PositiveIntegerField('人均消费(元)', null=True, blank=True)
    status = models.CharField('状态', max_length=10, choices=STATUS_CHOICES, default='pending', db_index=True)
    source = models.CharField('来源', max_length=10, choices=SOURCE_CHOICES, default='ai')
    created_at = models.DateTimeField('收藏时间', auto_now_add=True)

    class Meta:
        verbose_name = '待尝餐厅'
        verbose_name_plural = '待尝餐厅'
        ordering = ['-created_at']

    def __str__(self):
        return self.name
