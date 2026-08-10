from django.contrib import admin

from .models import DiningRecord, District, Restaurant, WishlistItem


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
