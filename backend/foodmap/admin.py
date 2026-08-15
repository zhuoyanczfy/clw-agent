from django.contrib import admin

from .models import (
    AppConfig,
    DailyMeal,
    DiningRecord,
    Dish,
    District,
    Divination,
    FavoriteDish,
    Pet,
    PetEvent,
    PetPhoto,
    Quote,
    Restaurant,
    SplashImage,
    WishlistItem,
)


@admin.register(Dish)
class DishAdmin(admin.ModelAdmin):
    """每日美食库：改完 APP 下次拉取即生效，无需重新打包。"""

    list_display = ('name', 'category', 'enabled', 'sort', 'has_content')
    list_filter = ('category', 'enabled')
    search_fields = ('name', 'description')
    list_editable = ('enabled', 'sort')

    @admin.display(boolean=True, description='内容完整')
    def has_content(self, obj):
        return bool(obj.description and obj.ingredients and obj.steps and obj.image_url)


@admin.register(FavoriteDish)
class FavoriteDishAdmin(admin.ModelAdmin):
    """美食收藏（单用户）：APP 收藏的菜，云端为准。"""

    list_display = ('dish', 'created_at')
    search_fields = ('dish__name',)


class PetEventInline(admin.TabularInline):
    model = PetEvent
    extra = 0
    fields = ('kind', 'title', 'date', 'due_date', 'weight', 'note')
    show_change_link = True


class PetPhotoInline(admin.TabularInline):
    model = PetPhoto
    extra = 0
    fields = ('image', 'caption')
    show_change_link = True


@admin.register(Pet)
class PetAdmin(admin.ModelAdmin):
    """宠物档案（猫咪名片）。"""

    list_display = ('name', 'breed', 'gender', 'birthday', 'adopt_date')
    search_fields = ('name', 'breed')
    inlines = [PetPhotoInline, PetEventInline]


@admin.register(District)
class DistrictAdmin(admin.ModelAdmin):
    list_display = ('name', 'adcode')
    search_fields = ('name',)


class DiningRecordInline(admin.TabularInline):
    model = DiningRecord
    extra = 0
    fields = ('date', 'rating', 'per_capita', 'mood')
    show_change_link = True


@admin.register(Restaurant)
class RestaurantAdmin(admin.ModelAdmin):
    list_display = ('name', 'district', 'address', 'record_count')
    list_filter = ('district',)
    search_fields = ('name', 'address')
    inlines = [DiningRecordInline]


@admin.register(DiningRecord)
class DiningRecordAdmin(admin.ModelAdmin):
    list_display = ('restaurant', 'date', 'rating', 'per_capita', 'mood')
    list_filter = ('rating', 'date')
    search_fields = ('restaurant__name', 'comment')
    date_hierarchy = 'date'


@admin.register(WishlistItem)
class WishlistItemAdmin(admin.ModelAdmin):
    list_display = ('name', 'district', 'status', 'source', 'per_capita', 'created_at')
    list_filter = ('status', 'source')
    search_fields = ('name', 'reason')


@admin.register(AppConfig)
class AppConfigAdmin(admin.ModelAdmin):
    """APP 云端配置（改完 APP 下次启动自动生效，无需重打包）。"""

    list_display = ('key', 'value', 'description')
    search_fields = ('key', 'description')
    ordering = ['id']


@admin.register(SplashImage)
class SplashImageAdmin(admin.ModelAdmin):
    list_display = ('id', 'title', 'enabled', 'created_at')
    list_filter = ('enabled',)
    list_editable = ('enabled',)


@admin.register(Divination)
class DivinationAdmin(admin.ModelAdmin):
    """每日占卜缓存：当天首次占卜生成，可在后台查看或删除后重新生成。"""

    list_display = ('date', 'card_name', 'orientation', 'lucky', 'created_at')
    search_fields = ('card_name', 'reading')
    date_hierarchy = 'date'


@admin.register(Quote)
class QuoteAdmin(admin.ModelAdmin):
    """好句好段缓存：按日期记录，可在后台查看历史或删除后重新拉取。"""

    list_display = ('date', 'author', 'source', 'category', 'text_preview')
    list_filter = ('category', 'date')
    search_fields = ('text', 'author', 'source')
    date_hierarchy = 'date'
    readonly_fields = ('uuid', 'detail_url')

    @admin.display(description='金句预览')
    def text_preview(self, obj):
        return obj.text[:50] + '…' if len(obj.text) > 50 else obj.text


@admin.register(DailyMeal)
class DailyMealAdmin(admin.ModelAdmin):
    """每日菜单缓存：当天首次访问自动生成，删除后下次访问重新抽一道。"""

    list_display = ('date', 'name', 'category', 'created_at')
    search_fields = ('name', 'description')
    date_hierarchy = 'date'
