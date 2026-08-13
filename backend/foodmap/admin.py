from django.contrib import admin

from .models import (
    AppConfig,
    DiningRecord,
    Dish,
    District,
    FavoriteDish,
    Pet,
    PetEvent,
    PetPhoto,
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
