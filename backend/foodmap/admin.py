import json
import re

from django.contrib import admin
from django.http import JsonResponse
from django.shortcuts import render
from django.urls import path
from django.utils import timezone

from .models import (
    AppConfig,
    BucketItem,
    BucketPhoto,
    ChatSession,
    DailyMeal,
    DiningRecord,
    Dish,
    District,
    Divination,
    FavoriteDish,
    GameQuestion,
    GameSession,
    Pet,
    PetEvent,
    PetPhoto,
    PlantBed,
    PlantBedItem,
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


class BucketPhotoInline(admin.TabularInline):
    model = BucketPhoto
    extra = 0
    fields = ('image',)
    show_change_link = True


@admin.register(BucketItem)
class BucketItemAdmin(admin.ModelAdmin):
    """植物园：想一起做的事（种草/种花/种树）。"""

    list_display = ('title', 'plant', 'category', 'is_completed', 'completed_at', 'sort_order', 'created_at')
    list_filter = ('is_completed', 'intensity', 'category')
    search_fields = ('title', 'description', 'memory_text')
    list_editable = ('sort_order', 'is_completed')
    inlines = [BucketPhotoInline]

    @admin.display(description='程度', ordering='intensity')
    def plant(self, obj):
        return {1: '🌱 种草', 2: '🌻 种花', 3: '🌳 种树'}.get(obj.intensity, '🌱 种草')


class PlantBedItemInline(admin.TabularInline):
    model = PlantBedItem
    extra = 0
    fields = ('item', 'time_note', 'sort_order')
    ordering = ('sort_order',)


@admin.register(PlantBed)
class PlantBedAdmin(admin.ModelAdmin):
    """花坛：多株种草组合的一日游园计划（赏花日）。"""

    list_display = ('title', 'visit_date', 'member_count', 'harvested', 'created_at')
    list_filter = ('visit_date',)
    search_fields = ('title',)
    inlines = [PlantBedItemInline]

    @admin.display(description='株数')
    def member_count(self, obj):
        return obj.bed_items.count()

    @admin.display(description='已收获', boolean=True)
    def harvested(self, obj):
        members = list(obj.bed_items.select_related('item'))
        return bool(members) and all(m.item.is_completed for m in members)


@admin.register(ChatSession)
class ChatSessionAdmin(admin.ModelAdmin):
    list_display = ('title', 'message_count', 'created_at', 'updated_at')
    search_fields = ('title',)

    @admin.display(description='消息数')
    def message_count(self, obj):
        return len(obj.messages or [])


@admin.register(AppConfig)
class AppConfigAdmin(admin.ModelAdmin):
    """APP 云端配置（改完 APP 下次启动自动生效，无需重打包）。"""

    list_display = ('key', 'value', 'description')
    search_fields = ('key', 'description')
    ordering = ['id']

    # ---------- 星语编辑器（可视化编辑碎碎念，不用手写 JSON） ----------

    STAR_NOTES_KEY = 'secret_notes'

    def get_urls(self):
        urls = super().get_urls()
        custom = [
            path(
                'star-notes/',
                self.admin_site.admin_view(self.star_notes_editor),
                name='foodmap_appconfig_star_notes',
            ),
        ]
        return custom + urls

    @staticmethod
    def _read_star_notes():
        """与 api_config 相同的合并逻辑，保证编辑器里看到的就是实际生效的内容。"""
        from .views import APP_CONFIG_DEFAULTS

        config = dict(APP_CONFIG_DEFAULTS)
        config.update(dict(AppConfig.objects.values_list('key', 'value')))
        try:
            data = json.loads(config.get(AppConfigAdmin.STAR_NOTES_KEY, '[]') or '[]')
        except ValueError:
            return []
        return [n for n in data if isinstance(n, dict)] if isinstance(data, list) else []

    def star_notes_editor(self, request):
        """星语碎碎念可视化编辑器：GET 打开页面，POST 保存整份列表。"""
        if request.method == 'POST':
            return self._save_star_notes(request)

        context = {
            **self.admin_site.each_context(request),
            'title': '星语编辑器',
            'opts': self.model._meta,
            'editor_data': {
                'notes': self._read_star_notes(),
                'today': timezone.localdate().isoformat(),
            },
        }
        return render(request, 'admin/foodmap/appconfig/star_notes_edit.html', context)

    def _save_star_notes(self, request):
        try:
            payload = json.loads(request.body.decode('utf-8'))
        except ValueError:
            return JsonResponse({'ok': False, 'error': '提交的数据不是合法 JSON'}, status=400)

        raw_notes = payload.get('notes') if isinstance(payload, dict) else None
        if not isinstance(raw_notes, list):
            return JsonResponse({'ok': False, 'error': '数据格式不对'}, status=400)

        notes = []
        seen = set()
        for index, item in enumerate(raw_notes, start=1):
            if not isinstance(item, dict):
                continue
            text = str(item.get('text', '')).strip()
            if not text:
                continue
            nid = str(item.get('id', '')).strip() or f'n{int(timezone.now().timestamp() * 1000)}{index}'
            while nid in seen:
                nid += 'x'
            seen.add(nid)
            date = str(item.get('date', '')).strip()
            if date and not re.match(r'^\d{4}-\d{2}-\d{2}$', date):
                date = ''
            notes.append({'id': nid, 'text': text, 'date': date})

        if not notes:
            return JsonResponse({'ok': False, 'error': '至少要保留一条碎碎念'}, status=400)

        AppConfig.objects.update_or_create(
            key=self.STAR_NOTES_KEY,
            defaults={
                'value': json.dumps(notes, ensure_ascii=False),
                'description': '星语碎碎念（建议用「星语编辑器」维护）',
            },
        )
        return JsonResponse({'ok': True, 'count': len(notes)})

    # ---------- 星语编辑器（可视化编辑碎碎念，不用手写 JSON） ----------

    STAR_NOTES_KEY = 'secret_notes'

    def get_urls(self):
        urls = super().get_urls()
        custom = [
            path(
                'star-notes/',
                self.admin_site.admin_view(self.star_notes_editor),
                name='foodmap_appconfig_star_notes',
            ),
        ]
        return custom + urls

    @staticmethod
    def _read_star_notes():
        """与 api_config 相同的合并逻辑，保证编辑器里看到的就是实际生效的内容。"""
        from .views import APP_CONFIG_DEFAULTS

        config = dict(APP_CONFIG_DEFAULTS)
        config.update(dict(AppConfig.objects.values_list('key', 'value')))
        try:
            data = json.loads(config.get(AppConfigAdmin.STAR_NOTES_KEY, '[]') or '[]')
        except ValueError:
            return []
        return [n for n in data if isinstance(n, dict)] if isinstance(data, list) else []

    def star_notes_editor(self, request):
        """星语碎碎念可视化编辑器：GET 打开页面，POST 保存整份列表。"""
        if request.method == 'POST':
            return self._save_star_notes(request)

        context = {
            **self.admin_site.each_context(request),
            'title': '星语编辑器',
            'opts': self.model._meta,
            'editor_data': {
                'notes': self._read_star_notes(),
                'today': timezone.localdate().isoformat(),
            },
        }
        return render(request, 'admin/foodmap/appconfig/star_notes_edit.html', context)

    def _save_star_notes(self, request):
        try:
            payload = json.loads(request.body.decode('utf-8'))
        except ValueError:
            return JsonResponse({'ok': False, 'error': '提交的数据不是合法 JSON'}, status=400)

        raw_notes = payload.get('notes') if isinstance(payload, dict) else None
        if not isinstance(raw_notes, list):
            return JsonResponse({'ok': False, 'error': '数据格式不对'}, status=400)

        notes = []
        seen = set()
        for index, item in enumerate(raw_notes, start=1):
            if not isinstance(item, dict):
                continue
            text = str(item.get('text', '')).strip()
            if not text:
                continue
            nid = str(item.get('id', '')).strip() or f'n{int(timezone.now().timestamp() * 1000)}{index}'
            while nid in seen:
                nid += 'x'
            seen.add(nid)
            date = str(item.get('date', '')).strip()
            if date and not re.match(r'^\d{4}-\d{2}-\d{2}$', date):
                date = ''
            notes.append({'id': nid, 'text': text, 'date': date})

        if not notes:
            return JsonResponse({'ok': False, 'error': '至少要保留一条碎碎念'}, status=400)

        AppConfig.objects.update_or_create(
            key=self.STAR_NOTES_KEY,
            defaults={
                'value': json.dumps(notes, ensure_ascii=False),
                'description': '星语碎碎念（建议用「星语编辑器」维护）',
            },
        )
        return JsonResponse({'ok': True, 'count': len(notes)})


@admin.register(SplashImage)
class SplashImageAdmin(admin.ModelAdmin):
    list_display = ('id', 'title', 'enabled', 'created_at')
    list_filter = ('enabled',)
    list_editable = ('enabled',)


@admin.register(Divination)
class DivinationAdmin(admin.ModelAdmin):
    """每日占卜缓存：当天首次占卜生成，可在后台查看或删除后重新生成。"""

    list_display = ('date', 'cards_preview', 'lucky', 'created_at')
    search_fields = ('reading',)
    date_hierarchy = 'date'

    @admin.display(description='三张牌')
    def cards_preview(self, obj):
        parts = [
            f"{c.get('position', '')}·{c.get('name', '')}({c.get('orientation', '')})"
            for c in (obj.cards or [])
        ]
        return ' | '.join(parts)


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


@admin.register(GameQuestion)
class GameQuestionAdmin(admin.ModelAdmin):
    """双人小游戏题库：改完 APP 下次开局即生效；可用 seed_game_questions 命令导入内置题。"""

    list_display = ('category', 'content_preview', 'option_a', 'option_b', 'enabled', 'sort')
    list_filter = ('category', 'enabled')
    list_editable = ('enabled', 'sort')
    search_fields = ('content', 'option_a', 'option_b')

    @admin.display(description='题目 / 题干')
    def content_preview(self, obj):
        text = obj.content or f'{obj.option_a} vs {obj.option_b}'
        return text[:40] + '…' if len(text) > 40 else text


@admin.register(GameSession)
class GameSessionAdmin(admin.ModelAdmin):
    """双人小游戏会话：只读排查用（双盲答案/笔画等状态看原始 JSON）。"""

    list_display = ('id', 'game_type', 'status', 'date', 'created_at', 'updated_at')
    list_filter = ('game_type', 'status')
    readonly_fields = ('game_type', 'date', 'state', 'status', 'created_at', 'updated_at')

    def has_add_permission(self, request):
        return False
