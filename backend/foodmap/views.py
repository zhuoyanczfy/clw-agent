# -*- coding: utf-8 -*-
"""纯 API 视图：为 Flutter APP 提供数据接口（网页版已移除）。"""
import configparser
import datetime
import hashlib
import json
import os
import random
import re
from pathlib import Path

from django import forms
from django.db import IntegrityError
from django.db.models import Count
from django.http import JsonResponse, StreamingHttpResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from .auth import require_api_token
from .models import (
    AppConfig,
    ChatSession,
    DailyMeal,
    DiningRecord,
    DiningRecordPhoto,
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
    SplashState,
    WishlistItem,
)
from .services.agent import build_system_prompt, execute_tool_calls
from .services.llm import LLMError, chat, chat_stream, chat_tool_round
from .services.profile import build_taste_profile
from .services.tools.registry import tools_schema

GEOJSON_PATH = Path(__file__).parent / 'geodata' / 'nanjing_districts.json'

# ============ 基础与每日推荐 ============


def api_health(request):
    """健康检查：APP 启动时探测后端是否可达。"""
    return JsonResponse({'ok': True, 'service': 'clw-agent backend'})


def _dish_json(d):
    """菜品序列化（与 APP Dish.fromJson 字段对应）。"""
    return {
        'id': d.slug,
        'name': d.name,
        'category': d.category,
        'description': d.description,
        'ingredients': d.ingredients,
        'steps': d.steps,
        'image_url': d.image_url,
    }


def dish_for_date(date_str):
    """按日期从数据库菜库取一道菜（md5(日期) 取模，与 APP 内置算法一致）。"""
    dishes = list(Dish.objects.filter(enabled=True).order_by('sort', 'id'))
    if not dishes:
        return None
    seed = int(hashlib.md5(date_str.encode()).hexdigest()[:8], 16)
    return dishes[seed % len(dishes)]


@require_api_token
def api_dishes(request):
    """全部启用菜品（每日推荐数据源）。"""
    dishes = [
        _dish_json(d)
        for d in Dish.objects.filter(enabled=True).order_by('sort', 'id')
    ]
    return JsonResponse({'total': len(dishes), 'dishes': dishes})


@require_api_token
def api_dish_today(request):
    """今日推荐（与 APP 内置算法一致：md5(日期) 取模）。"""
    today = timezone.localdate().isoformat()
    dish = dish_for_date(today)
    return JsonResponse(
        {'date': today, 'dish': _dish_json(dish) if dish else None}
    )


@require_api_token
def api_dish_by_date(request, date):
    """指定日期的推荐，date 形如 2026-08-10。"""
    try:
        datetime.date.fromisoformat(date)
    except ValueError:
        return JsonResponse({'error': '日期格式错误，应为 YYYY-MM-DD'}, status=400)
    dish = dish_for_date(date)
    return JsonResponse(
        {'date': date, 'dish': _dish_json(dish) if dish else None}
    )


# ============ 美食收藏 ============


@require_api_token
@csrf_exempt
@require_http_methods(['GET', 'POST'])
def api_favorites(request):
    """收藏的菜：GET 列表（按收藏时间倒序）；POST 添加，body {"slug": "tomato-beef"}。"""
    if request.method == 'GET':
        favs = FavoriteDish.objects.select_related('dish').order_by('-created_at')
        return JsonResponse({'favorites': [_dish_json(f.dish) for f in favs]})

    try:
        data = json.loads(request.body or b'{}')
    except ValueError:
        return JsonResponse({'error': '请求体不是合法 JSON'}, status=400)
    slug = (data.get('slug') or '').strip()
    if not slug:
        return JsonResponse({'error': '缺少菜品标识 slug'}, status=400)
    dish = Dish.objects.filter(slug=slug, enabled=True).first()
    if not dish:
        return JsonResponse({'error': '菜品不存在'}, status=404)
    FavoriteDish.objects.get_or_create(dish=dish)
    return JsonResponse({'ok': True})


@require_api_token
@csrf_exempt
@require_http_methods(['DELETE'])
def api_favorite_delete(request, slug):
    """取消收藏，slug 形如 tomato-beef。"""
    FavoriteDish.objects.filter(dish__slug=slug).delete()
    return JsonResponse({'ok': True})


# ============ 区与餐厅 ============


def _district_stats():
    return District.objects.annotate(
        rest_count=Count('restaurants', distinct=True),
        visited_count=Count('restaurants__records', distinct=True),
    ).order_by('id')


@require_api_token
def api_districts(request):
    """全部区（含区内餐厅库数量 / 去过餐厅数）。"""
    data = [
        {
            'id': d.id, 'name': d.name, 'adcode': d.adcode,
            'restaurant_count': d.rest_count, 'visited_count': d.visited_count,
        }
        for d in _district_stats()
    ]
    return JsonResponse({'districts': data})


@require_api_token
def api_districts_geojson(request):
    """南京区划 GeoJSON（flutter_map 分区高亮用），附加区内统计。

    GeoJSON 文件不常变，用 mtime 指纹缓存避免每次请求都读磁盘；
    餐厅/足迹统计每次实时查询（数据量小，保证准确）。
    """
    geojson = _cached_geojson()
    stats = {
        d.adcode: (
            d.restaurants.count(),
            d.restaurants.filter(records__isnull=False).distinct().count(),
        )
        for d in District.objects.prefetch_related('restaurants')
    }
    for feature in geojson['features']:
        props = feature['properties']
        adcode = str(props.get('adcode'))
        props['adcode'] = adcode
        props['restaurant_count'], props['visited_count'] = stats.get(adcode, (0, 0))
    return JsonResponse(geojson)


_geojson_cache = {'mtime': None, 'data': None}


def _cached_geojson():
    """按 mtime 缓存 GeoJSON，文件变更后自动失效。"""
    mtime = GEOJSON_PATH.stat().st_mtime
    if _geojson_cache['mtime'] != mtime or _geojson_cache['data'] is None:
        with GEOJSON_PATH.open(encoding='utf-8') as f:
            _geojson_cache['data'] = json.load(f)
        _geojson_cache['mtime'] = mtime
    return _geojson_cache['data']


def _restaurant_json(r, with_records=False):
    data = {
        'id': r.pk,
        'name': r.name,
        'district_id': r.district_id,
        'district': r.district.name,
        'address': r.address,
        'lat': r.lat,
        'lng': r.lng,
        'amap_id': r.amap_id,
        'rating': r.rating,
        'record_count': getattr(r, 'rec_count', r.records.count()),
    }
    if with_records:
        data['records'] = [
            {
                'id': rec.pk,
                'date': rec.date.isoformat(),
                'rating': rec.rating,
                'comment': rec.comment,
                'per_capita': rec.per_capita,
                'mood': rec.mood,
            }
            for rec in r.records.all()
        ]
    return data


@require_api_token
def api_restaurants(request):
    """餐厅列表。

    ?district=区名 过滤；?visited=1 只看去过（地图标记用）；
    ?q=关键词 按名称模糊搜索（带 q 时最多返回 50 条，供记录页选餐厅用）。
    """
    qs = Restaurant.objects.select_related('district').annotate(rec_count=Count('records'))
    district = request.GET.get('district')
    q = (request.GET.get('q') or '').strip()
    visited = request.GET.get('visited') == '1'
    if q:
        qs = qs.filter(name__icontains=q)
    if district:
        qs = qs.filter(district__name=district)
    if visited:
        qs = qs.filter(rec_count__gt=0)
    qs = qs.order_by('-rec_count', '-rating', 'name')
    if q:
        qs = qs[:50]
    elif not (district or visited):
        # 无任何过滤条件时兜底限 200 条，避免拉全库 2.5 万条（足迹页用 visited=1 不受影响）
        qs = qs[:200]
    return JsonResponse({'restaurants': [_restaurant_json(r) for r in qs]})


@require_api_token
def api_restaurant_detail(request, restaurant_id):
    """餐厅详情 + 全部用餐记录。"""
    restaurant = get_object_or_404(
        Restaurant.objects.select_related('district').prefetch_related('records'),
        pk=restaurant_id,
    )
    return JsonResponse({'restaurant': _restaurant_json(restaurant, with_records=True)})


# ============ 用餐记录 ============


def _photo_json(photo):
    return {'id': photo.pk, 'url': photo.image.url}


def _record_json(record, with_photos=True):
    data = {
        'id': record.pk,
        'restaurant_id': record.restaurant_id,
        'restaurant': record.restaurant.name,
        'district': record.restaurant.district.name,
        'date': record.date.isoformat(),
        'rating': record.rating,
        'comment': record.comment,
        'per_capita': record.per_capita,
        'mood': record.mood,
        # USE_TZ=True 时 auto_now 存 UTC，输出前转本地时间（Asia/Shanghai）
        'created_at': timezone.localtime(record.created_at).strftime('%Y-%m-%d %H:%M'),
    }
    if with_photos:
        data['photos'] = [_photo_json(p) for p in record.photos.all()]
    return data


def _record_from_data(data, record=None):
    """从 JSON body 组装/更新记录：支持选已有餐厅或新建餐厅（restaurant_name + district_id）。"""
    fields = {}
    restaurant_id = data.get('restaurant_id')
    if restaurant_id:
        fields['restaurant'] = get_object_or_404(Restaurant, pk=restaurant_id)
    else:
        name = (data.get('restaurant_name') or '').strip()
        if not name:
            raise ValueError('请选择已有餐厅，或填写新餐厅名称')
        district = None
        district_id = data.get('district_id')
        if district_id:
            district = District.objects.filter(pk=district_id).first()
        if not district:
            raise ValueError('新餐厅必须选择所属区')
        fields['restaurant'] = Restaurant.objects.create(name=name, district=district)

    for key in ('rating', 'per_capita'):
        value = data.get(key, 4 if key == 'rating' else None)
        if key == 'rating':
            try:
                value = int(value)
            except (TypeError, ValueError):
                value = 4
            if not 1 <= value <= 5:
                raise ValueError('评分需在 1-5 之间')
        else:  # per_capita
            try:
                value = int(value) if value else None
            except (TypeError, ValueError):
                value = None
        fields[key] = value

    for key in ('date', 'comment', 'mood'):
        fields[key] = data.get(key, '')
        if key == 'date':
            if not fields[key]:
                raise ValueError('用餐日期不能为空')
            try:
                fields[key] = datetime.date.fromisoformat(fields[key])
            except ValueError:
                raise ValueError('用餐日期格式应为 YYYY-MM-DD')
    if record:
        for k, v in fields.items():
            setattr(record, k, v)
        return record
    return DiningRecord(**fields)


@require_api_token
@csrf_exempt
@require_http_methods(['GET', 'POST'])
def api_records(request):
    """记录列表（?restaurant=餐厅id 过滤）或新建记录。"""
    if request.method == 'GET':
        qs = (
            DiningRecord.objects.select_related('restaurant__district')
            .prefetch_related('photos')
            .order_by('-date', '-id')
        )
        restaurant_id = request.GET.get('restaurant')
        if restaurant_id:
            qs = qs.filter(restaurant_id=restaurant_id)
        return JsonResponse({'records': [_record_json(r) for r in qs]})

    try:
        data = json.loads(request.body or b'{}')
    except ValueError:
        return JsonResponse({'error': '请求体不是合法 JSON'}, status=400)
    try:
        record = _record_from_data(data)
    except ValueError as exc:
        return JsonResponse({'error': str(exc)}, status=400)
    record.save()
    return JsonResponse({'ok': True, 'record': _record_json(record)}, status=201)


@require_api_token
@csrf_exempt
@require_http_methods(['GET', 'PUT', 'DELETE'])
def api_record_detail(request, record_id):
    """记录详情 / 编辑 / 删除。"""
    record = get_object_or_404(
        DiningRecord.objects.select_related('restaurant__district').prefetch_related('photos'),
        pk=record_id,
    )
    if request.method == 'GET':
        return JsonResponse({'record': _record_json(record)})

    if request.method == 'DELETE':
        # 先删数据库行，再删磁盘文件（Django 不会自动清理）
        for photo in record.photos.all():
            path = photo.image.path
            photo.delete()
            try:
                os.remove(path)
            except (FileNotFoundError, OSError):
                pass
        record.delete()
        return JsonResponse({'ok': True})

    try:
        data = json.loads(request.body or b'{}')
    except ValueError:
        return JsonResponse({'error': '请求体不是合法 JSON'}, status=400)
    try:
        record = _record_from_data(data, record=record)
    except ValueError as exc:
        return JsonResponse({'error': str(exc)}, status=400)
    record.save()
    return JsonResponse({'ok': True, 'record': _record_json(record)})


@require_api_token
@csrf_exempt
@require_http_methods(['POST'])
def api_photo_upload(request, record_id):
    """上传用餐照片（multipart，字段名 photos，可多张）。"""
    record = get_object_or_404(DiningRecord, pk=record_id)
    photo_field = forms.ImageField()
    saved = []
    for f in request.FILES.getlist('photos'):
        if f.size > 5 * 1024 * 1024:
            return JsonResponse({'error': f'照片「{f.name}」超过 5MB，请压缩后再传'}, status=400)
        try:
            photo_field.clean(f)
        except forms.ValidationError as exc:
            return JsonResponse({'error': f'照片「{f.name}」无效：{exc}'}, status=400)
        photo = DiningRecordPhoto.objects.create(record=record, image=f)
        saved.append(_photo_json(photo))
    return JsonResponse({'ok': True, 'photos': saved})


@require_api_token
@csrf_exempt
@require_http_methods(['DELETE'])
def api_photo_delete(request, photo_id):
    """删除单张照片（数据库行 + 磁盘文件）。"""
    photo = get_object_or_404(DiningRecordPhoto, pk=photo_id)
    path = photo.image.path
    photo.delete()
    try:
        os.remove(path)
    except (FileNotFoundError, OSError):
        pass
    return JsonResponse({'ok': True})


# ============ 待尝清单 ============


def _wishlist_json(item):
    return {
        'id': item.pk,
        'name': item.name,
        'amap_id': item.amap_id,
        'district_id': item.district_id,
        'district': item.district.name if item.district else '',
        'reason': item.reason,
        'per_capita': item.per_capita,
        'status': item.status,
        'source': item.source,
        'created_at': timezone.localtime(item.created_at).strftime('%Y-%m-%d %H:%M'),
    }


def _parse_per_capita(value):
    try:
        if value:
            parsed = int(value)
            return parsed if parsed > 0 else None
    except (TypeError, ValueError):
        pass
    return None


@require_api_token
@csrf_exempt
@require_http_methods(['GET', 'POST'])
def api_wishlist(request):
    """待尝清单列表（?status=pending|eaten）或添加。"""
    if request.method == 'GET':
        qs = WishlistItem.objects.select_related('district').order_by('-created_at')
        status = request.GET.get('status')
        if status:
            qs = qs.filter(status=status)
        return JsonResponse({'items': [_wishlist_json(i) for i in qs]})

    try:
        data = json.loads(request.body or b'{}')
    except ValueError:
        return JsonResponse({'error': '请求体不是合法 JSON'}, status=400)

    name = (data.get('name') or '').strip()
    if not name:
        return JsonResponse({'error': '餐厅名称不能为空'}, status=400)

    # 优先按高德 POI ID 关联已导入的真实餐厅（区也以它为准）
    amap_id = (data.get('amap_id') or '').strip() or None
    district = None
    if amap_id:
        existing = Restaurant.objects.filter(amap_id=amap_id).first()
        if existing:
            district = existing.district
    if not district:
        district_id = data.get('district_id')
        district = District.objects.filter(pk=district_id).first() if district_id else None
    if not district:
        district_name = (data.get('district') or '').strip()
        district = District.objects.filter(name=district_name).first() if district_name else None

    existed = WishlistItem.objects.filter(name__iexact=name, status='pending').first()
    if existed:
        return JsonResponse({'ok': True, 'existed': True, 'item': _wishlist_json(existed)})

    item = WishlistItem.objects.create(
        name=name,
        amap_id=amap_id,
        district=district,
        reason=(data.get('reason') or '')[:300],
        per_capita=_parse_per_capita(data.get('per_capita')),
        source=data.get('source') if data.get('source') in ('ai', 'manual') else 'ai',
    )
    return JsonResponse({'ok': True, 'item': _wishlist_json(item)}, status=201)


@require_api_token
@csrf_exempt
@require_http_methods(['POST'])
def api_wishlist_eaten(request, item_id):
    """标记待尝为已尝。"""
    item = get_object_or_404(WishlistItem, pk=item_id)
    item.status = 'eaten'
    item.save(update_fields=['status'])
    return JsonResponse({'ok': True, 'item': _wishlist_json(item)})


@require_api_token
@csrf_exempt
@require_http_methods(['DELETE'])
def api_wishlist_delete(request, item_id):
    """删除待尝项。"""
    item = get_object_or_404(WishlistItem, pk=item_id)
    item.delete()
    return JsonResponse({'ok': True})


# ============ 宠物名片 ============


def _parse_date(value):
    """解析 YYYY-MM-DD，空串/非法返回 None。"""
    s = (value or '').strip()
    if not s:
        return None
    try:
        return datetime.date.fromisoformat(s)
    except ValueError:
        return None


def _pet_json(p):
    return {
        'id': p.pk,
        'name': p.name,
        'breed': p.breed,
        'gender': p.gender,
        'birthday': p.birthday.isoformat() if p.birthday else '',
        'adopt_date': p.adopt_date.isoformat() if p.adopt_date else '',
        'avatar': p.avatar.url if p.avatar else '',
        'notes': p.notes,
    }


def _pet_photo_json(ph):
    return {
        'id': ph.pk,
        'image': ph.image.url,
        'caption': ph.caption,
        'created_at': timezone.localtime(ph.created_at).strftime('%Y-%m-%d'),
    }


def _pet_event_json(e):
    return {
        'id': e.pk,
        'kind': e.kind,
        'title': e.title,
        'date': e.date.isoformat(),
        'due_date': e.due_date.isoformat() if e.due_date else '',
        'weight': e.weight,
        'note': e.note,
    }


def _clean_image(field, f, label):
    """校验上传图片，失败返回错误信息字符串，成功返回 None。"""
    try:
        field.clean(f)
    except forms.ValidationError as exc:
        return f'{label}「{f.name}」无效：{exc}'
    return None


@require_api_token
@csrf_exempt
@require_http_methods(['GET', 'POST'])
def api_pets(request):
    """宠物列表或创建（POST multipart：name 必填，avatar 图片可选）。"""
    if request.method == 'GET':
        pets = Pet.objects.all()
        return JsonResponse({'pets': [_pet_json(p) for p in pets]})

    name = (request.POST.get('name') or '').strip()
    if not name:
        return JsonResponse({'error': '宠物名字不能为空'}, status=400)
    avatar = request.FILES.get('avatar')
    if avatar:
        err = _clean_image(forms.ImageField(), avatar, '头像')
        if err:
            return JsonResponse({'error': err}, status=400)
    pet = Pet.objects.create(
        name=name[:30],
        breed=(request.POST.get('breed') or '').strip()[:50],
        gender=(request.POST.get('gender') or '').strip()[:10],
        birthday=_parse_date(request.POST.get('birthday')),
        adopt_date=_parse_date(request.POST.get('adopt_date')),
        avatar=avatar,
        notes=(request.POST.get('notes') or '').strip(),
    )
    return JsonResponse({'ok': True, 'pet': _pet_json(pet)}, status=201)


@require_api_token
@csrf_exempt
@require_http_methods(['POST', 'DELETE'])
def api_pet_detail(request, pet_id):
    """宠物档案更新（POST multipart 全字段，含头像）或删除（含磁盘文件清理）。

    注意：不用 PUT——Django 只在 POST 时解析 multipart 表单，PUT 取不到字段与文件。
    """
    pet = get_object_or_404(Pet, pk=pet_id)
    if request.method == 'DELETE':
        old_avatar = pet.avatar.path if pet.avatar else None
        photo_paths = [p.image.path for p in pet.photos.all()]
        pet.delete()
        for path in ([old_avatar] + photo_paths):
            if path:
                try:
                    os.remove(path)
                except (FileNotFoundError, OSError):
                    pass
        return JsonResponse({'ok': True})

    name = (request.POST.get('name') or '').strip()
    if not name:
        return JsonResponse({'error': '宠物名字不能为空'}, status=400)
    avatar = request.FILES.get('avatar')
    if avatar:
        err = _clean_image(forms.ImageField(), avatar, '头像')
        if err:
            return JsonResponse({'error': err}, status=400)
    pet.name = name[:30]
    pet.breed = (request.POST.get('breed') or '').strip()[:50]
    pet.gender = (request.POST.get('gender') or '').strip()[:10]
    pet.birthday = _parse_date(request.POST.get('birthday'))
    pet.adopt_date = _parse_date(request.POST.get('adopt_date'))
    pet.notes = (request.POST.get('notes') or '').strip()
    if avatar:
        old = pet.avatar
        if old:
            # 先删旧文件再换新。注意 FieldFile.delete 会把实例内存字段置 None，
            # 因此必须先删旧、后赋值保存，否则响应里 avatar 会是空的。
            old.delete(save=False)
        pet.avatar = avatar
        pet.save()
    else:
        pet.save()
    return JsonResponse({'ok': True, 'pet': _pet_json(pet)})


@require_api_token
@csrf_exempt
@require_http_methods(['GET', 'POST'])
def api_pet_photos(request, pet_id):
    """宠物照片列表或上传（POST multipart，字段名 images 可多张，caption 可选）。"""
    pet = get_object_or_404(Pet, pk=pet_id)
    if request.method == 'GET':
        return JsonResponse({'photos': [_pet_photo_json(p) for p in pet.photos.all()]})

    photo_field = forms.ImageField()
    caption = (request.POST.get('caption') or '').strip()[:100]
    saved = []
    for f in request.FILES.getlist('images'):
        err = _clean_image(photo_field, f, '照片')
        if err:
            return JsonResponse({'error': err}, status=400)
        saved.append(PetPhoto.objects.create(pet=pet, image=f, caption=caption))
    if not saved:
        return JsonResponse({'error': '缺少图片字段 images'}, status=400)
    return JsonResponse(
        {'ok': True, 'photos': [_pet_photo_json(p) for p in saved]}, status=201
    )


@require_api_token
@csrf_exempt
@require_http_methods(['DELETE'])
def api_pet_photo_delete(request, photo_id):
    """删除单张宠物照片（数据库行 + 磁盘文件）。"""
    photo = get_object_or_404(PetPhoto, pk=photo_id)
    path = photo.image.path
    photo.delete()
    try:
        os.remove(path)
    except (FileNotFoundError, OSError):
        pass
    return JsonResponse({'ok': True})


@require_api_token
@csrf_exempt
@require_http_methods(['GET', 'POST'])
def api_pet_events(request, pet_id):
    """宠物事项列表或添加（POST JSON：kind/title/date 必填，due_date/weight/note 可选）。"""
    pet = get_object_or_404(Pet, pk=pet_id)
    if request.method == 'GET':
        return JsonResponse({'events': [_pet_event_json(e) for e in pet.events.all()]})

    try:
        data = json.loads(request.body or b'{}')
    except ValueError:
        return JsonResponse({'error': '请求体不是合法 JSON'}, status=400)
    kind = (data.get('kind') or '').strip()
    if kind not in dict(PetEvent.KIND_CHOICES):
        return JsonResponse({'error': '事项类型无效'}, status=400)
    title = (data.get('title') or '').strip()
    date = _parse_date(data.get('date'))
    if not title or not date:
        return JsonResponse({'error': '标题与日期必填'}, status=400)
    weight = None
    if kind == 'weight':
        try:
            weight = float(data.get('weight') or '')
        except (TypeError, ValueError):
            return JsonResponse({'error': '体重数字无效'}, status=400)
        if weight <= 0:
            return JsonResponse({'error': '体重数字无效'}, status=400)
    event = PetEvent.objects.create(
        pet=pet,
        kind=kind,
        title=title[:100],
        date=date,
        due_date=_parse_date(data.get('due_date')),
        weight=weight,
        note=(data.get('note') or '').strip(),
    )
    return JsonResponse({'ok': True, 'event': _pet_event_json(event)}, status=201)


@require_api_token
@csrf_exempt
@require_http_methods(['DELETE'])
def api_pet_event_delete(request, event_id):
    """删除一条宠物事项。"""
    event = get_object_or_404(PetEvent, pk=event_id)
    event.delete()
    return JsonResponse({'ok': True})


# ============ AI 智能推荐 ============

MAX_HISTORY = 20
TOOLS_SCHEMA = tools_schema()


@require_api_token
@csrf_exempt
@require_http_methods(['POST'])
def api_recommend_verify(request):
    """校验 AI 推荐卡片是否真实存在（高德搜索）。body: {"items": [{"name","district"?}]}"""
    try:
        data = json.loads(request.body or b'{}')
    except ValueError:
        return JsonResponse({'error': '请求体不是合法 JSON'}, status=400)

    from .services.amap import AMAPError, search_text
    results = []
    for item in data.get('items') or []:
        name = (item.get('name') or '').strip()
        district_hint = (item.get('district') or '').strip()
        result = {'name': name, 'ok': False}
        if not name:
            results.append(result)
            continue
        try:
            pois = search_text(name)
        except AMAPError as exc:
            return JsonResponse({'error': str(exc)}, status=502)

        best = None
        for poi in pois:
            poi_name = (poi.get('name') or '').strip()
            name_ok = poi_name == name or poi_name in name or name in poi_name
            if not name_ok:
                continue
            if not district_hint or poi.get('adname') == district_hint:
                best = poi
                break
            if best is None:
                best = poi
        if best:
            biz_ext = best.get('biz_ext') or {}
            try:
                rating = float(biz_ext.get('rating'))
            except (TypeError, ValueError):
                rating = None
            result.update({
                'ok': True,
                'amap_id': best.get('id'),
                'name': best.get('name'),
                'address': best.get('address'),
                'district': best.get('adname') or '',
                'rating': rating,
            })
        results.append(result)
    return JsonResponse({'ok': True, 'items': results})


# ============ 推荐官会话（历史保存） ============


def _chat_session_json(session):
    """会话摘要（列表用，不含 messages）。"""
    return {
        'id': session.pk,
        'title': session.title,
        'message_count': len(session.messages or []),
        'created_at': timezone.localtime(session.created_at).strftime('%Y-%m-%d %H:%M'),
        'updated_at': timezone.localtime(session.updated_at).strftime('%Y-%m-%d %H:%M'),
    }


@require_api_token
@csrf_exempt
@require_http_methods(['GET', 'POST'])
def api_chat_sessions(request):
    """推荐官会话列表（GET）或保存/新建（POST，整体 upsert）。

    POST body: {"session_id": 可选, "title": 可选, "messages": [{role, content}]}
    """
    if request.method == 'GET':
        qs = ChatSession.objects.order_by('-updated_at')[:50]
        return JsonResponse({'sessions': [_chat_session_json(s) for s in qs]})

    try:
        data = json.loads(request.body or b'{}')
    except ValueError:
        return JsonResponse({'error': '请求体不是合法 JSON'}, status=400)
    if not isinstance(data, dict):
        return JsonResponse({'error': '请求体必须是 JSON 对象'}, status=400)

    raw = data.get('messages') or []
    if not isinstance(raw, list):
        return JsonResponse({'error': 'messages 必须是数组'}, status=400)
    for m in raw:
        if not isinstance(m, dict):
            return JsonResponse({'error': '消息项必须是对象'}, status=400)
        role = m.get('role')
        content = m.get('content')
        if role not in ('user', 'assistant') or not isinstance(content, str) or not content.strip():
            return JsonResponse({'error': '消息 role/content 非法'}, status=400)
    messages = [{'role': m.get('role'), 'content': m.get('content').strip()} for m in raw]
    session_id = data.get('session_id')
    if session_id is not None and not isinstance(session_id, int):
        return JsonResponse({'error': 'session_id 无效'}, status=400)
    if session_id:
        session = ChatSession.objects.filter(pk=session_id).first()
        if not session:
            return JsonResponse({'error': '会话不存在'}, status=404)
    else:
        session = ChatSession()

    title = (data.get('title') or '').strip()
    if not title:
        title = next((m['content'] for m in messages if m['role'] == 'user'), '')[:30]
    session.title = title
    session.messages = messages
    session.save()
    return JsonResponse({'session': _chat_session_json(session)})


@require_api_token
@csrf_exempt
@require_http_methods(['GET', 'DELETE'])
def api_chat_session_detail(request, session_id):
    """单会话：GET 返回详情（含 messages），DELETE 删除。"""
    session = get_object_or_404(ChatSession, pk=session_id)
    if request.method == 'DELETE':
        session.delete()
        return JsonResponse({'ok': True})
    data = _chat_session_json(session)
    data['messages'] = session.messages or []
    return JsonResponse({'session': data})


@require_api_token
@csrf_exempt
@require_http_methods(['POST'])
def api_chat(request):
    """SSE 流式对话接口（无状态：历史由客户端传入）。

    POST body: {"message": "...", "history": [{"role": "user|assistant", "content": "..."}]}
    响应为 text/event-stream，每行 data: {delta}，结束行 data: [DONE]。
    """
    try:
        data = json.loads(request.body or b'{}')
    except ValueError:
        return JsonResponse({'error': '请求体不是合法 JSON'}, status=400)

    message = (data.get('message') or '').strip()
    if not message:
        return JsonResponse({'error': '消息不能为空'}, status=400)

    # 客户端传入的历史（只保留 user/assistant 文本轮）
    history = [m for m in (data.get('history') or []) if m.get('role') in ('user', 'assistant')]
    history = history[-MAX_HISTORY:]
    history.append({'role': 'user', 'content': message})

    # system prompt 由 agent.md 定义（backend/foodmap/agents/recommender/agent.md）
    system_msg = {'role': 'system', 'content': build_system_prompt(profile=build_taste_profile(), task=message)}
    messages_payload = [system_msg] + history

    def _merge_tool_calls(parts):
        """合并流式 tool_calls 增量（按 index 组装），返回完整 tool_calls 列表。"""
        calls = {}
        for part in parts:
            for tc in part or []:
                idx = tc.get('index', 0)
                c = calls.setdefault(idx, {
                    'id': '',
                    'type': 'function',
                    'function': {'name': '', 'arguments': ''},
                })
                if tc.get('id'):
                    c['id'] = tc['id']
                fn = tc.get('function') or {}
                if fn.get('name'):
                    c['function']['name'] = fn['name']
                if fn.get('arguments'):
                    c['function']['arguments'] += fn['arguments']
        return list(calls.values())

    def sse_generator():
        try:
            messages = messages_payload
            # 第 1 轮（非流式带 tools）：决定是否调用工具
            tool_round = chat_tool_round(messages, TOOLS_SCHEMA)
            tool_calls = tool_round.get('tool_calls') or []
            if not tool_calls:
                # 无工具调用（寒暄/追问/直接回答）：一次性下发
                content = tool_round.get('content') or ''
                yield f'data: {json.dumps({"delta": content}, ensure_ascii=False)}\n\n'
                yield 'data: [DONE]\n\n'
                return

            # 后续轮流式（带 tools）：边输出边检测是否再次调用工具，最多再 2 轮
            for _ in range(2):
                messages = messages + [
                    {
                        'role': 'assistant',
                        'content': tool_round.get('content') or '',
                        'tool_calls': tool_calls,
                    },
                ] + execute_tool_calls(tool_calls)
                tc_parts = []
                for content, tcs in chat_stream(messages, tools=TOOLS_SCHEMA):
                    if tcs:
                        tc_parts.append(tcs)
                        continue  # 工具调用增量：不发给客户端
                    if content:
                        yield f'data: {json.dumps({"delta": content}, ensure_ascii=False)}\n\n'
                if not tc_parts:
                    break  # 本轮无工具调用，正常结束
                tool_calls = _merge_tool_calls(tc_parts)
                tool_round = {'role': 'assistant', 'content': '', 'tool_calls': tool_calls}
                if not tool_calls:
                    break
            yield 'data: [DONE]\n\n'
        except LLMError as exc:
            yield f'data: {json.dumps({"error": str(exc)}, ensure_ascii=False)}\n\n'
            yield 'data: [DONE]\n\n'
        except Exception as exc:
            # 非 LLM 异常（网络超时、工具执行失败等）兜底，避免流异常终止
            import logging
            logging.getLogger(__name__).exception('SSE 流式聊天异常')
            yield f'data: {json.dumps({"error": f"推荐官暂时开小差了：{exc}"}, ensure_ascii=False)}\n\n'
            yield 'data: [DONE]\n\n'

    response = StreamingHttpResponse(sse_generator(), content_type='text/event-stream')
    response['Cache-Control'] = 'no-cache'
    response['X-Accel-Buffering'] = 'no'
    return response


# ============ APP 云端配置 ============

# 配置默认值：Admin 添加同名 AppConfig 条目即覆盖（APP 启动自动拉取，无需重打包）
APP_CONFIG_DEFAULTS = {
    # 专属信息
    'her_name': '陈隶文',
    'meet_date': '2026-07-23',
    'greeting': '今天也要好好吃饭呀',
    'daily_dish_title': '今天想带你吃',
    # 通知文案（{herName} / {dishName} 会被替换）
    'water_title': '亲爱的，该喝水啦～',
    'water_body': '喝一口温水，今天也要水润润的 {herName}',
    'night_title': '夜深了，早点休息',
    'night_body': '晚安，好梦。明天见，{herName}',
    'dish_title': '今日美食推荐',
    'dish_body': '今天想带你吃「{dishName}」，点开看看',
    # 通知默认时间
    'water_times': '10:00,14:00,17:00',
    'night_time': '22:30',
    'dish_time': '12:00',
    # 通知开关（1 开 / 0 关）
    'water_enabled': '1',
    'night_enabled': '1',
    'dish_enabled': '1',
    # 天气关怀提醒（{dayWeather} / {dayTemp} 会被替换）
    'weather_enabled': '1',
    'weather_time': '08:00',
    'weather_title': '今日天气关怀',
    'weather_rain_body': '今天{dayWeather}，出门记得带伞 ⭐',
    'weather_cold_body': '今天降温到 {dayTemp}°，记得多穿一点 ⭐',
}


@require_api_token
def api_config(request):
    """APP 云端配置：后端默认值 + Admin 覆盖值合并返回。"""
    overrides = dict(AppConfig.objects.values_list('key', 'value'))
    config = dict(APP_CONFIG_DEFAULTS)
    config.update(overrides)
    return JsonResponse({'config': config})


# ============ 天气预报 ============


@require_api_token
def api_weather(request):
    """天气查询：代理高德（实况 30min / 预报 3h 进程内缓存），
    供首页天气展示与天气关怀提醒使用。"""
    from .services.amap import AMAPError
    from .services.weather import get_weather

    try:
        return JsonResponse(get_weather())
    except AMAPError as exc:
        return JsonResponse({'error': str(exc)}, status=502)


# ============ 加载页图片 ============


def _upload_token():
    """读取 config.ini 默认节的上传令牌（UPLOAD_TOKEN），供内容上传接口鉴权。"""
    from config.settings import BASE_DIR
    parser = configparser.ConfigParser()
    parser.read_string(
        '[default]\n'
        + (BASE_DIR / 'config' / 'config.ini').read_text(encoding='utf-8')
    )
    return parser.get('default', 'upload_token', fallback='').strip()


def _splash_json(img):
    return {'id': img.pk, 'title': img.title, 'url': img.image.url}


@require_api_token
def api_splash(request):
    """当日加载页图片：同一天内固定一张，次日随机换一张（保证相邻两天不重复）。"""
    images = list(SplashImage.objects.filter(enabled=True))
    if not images:
        return JsonResponse({'error': '还没有加载页图片，请先在后台或上传接口添加'}, status=404)

    today = timezone.localdate().isoformat()
    state, _ = SplashState.objects.get_or_create(pk=1)
    # 当天已展示过：继续用同一张（避免同一天多次打开来回闪图）
    if state.last_date == today and state.last_id:
        cached = next((i for i in images if i.pk == state.last_id), None)
        if cached:
            return JsonResponse({'splash': _splash_json(cached)})

    # 新的一天：随机选一张，排除昨天那张
    candidates = [i for i in images if i.pk != state.last_id] or images
    img = random.choice(candidates)
    state.last_date = today
    state.last_id = img.pk
    state.save(update_fields=['last_date', 'last_id'])
    return JsonResponse({'splash': _splash_json(img)})


@require_api_token
@csrf_exempt
@require_http_methods(['POST'])
def api_splash_upload(request):
    """上传加载页图片（multipart：image + 可选 title，请求头 X-Upload-Token 鉴权）。"""
    token = request.headers.get('X-Upload-Token', '')
    if not token or token != _upload_token():
        return JsonResponse({'error': '上传令牌无效（请求头 X-Upload-Token）'}, status=403)
    f = request.FILES.get('image')
    if not f:
        return JsonResponse({'error': '缺少图片字段 image'}, status=400)
    image_field = forms.ImageField()
    try:
        image_field.clean(f)
    except forms.ValidationError as exc:
        return JsonResponse({'error': f'图片无效：{exc}'}, status=400)
    img = SplashImage.objects.create(
        title=(request.POST.get('title') or '').strip()[:100],
        image=f,
    )
    return JsonResponse({'ok': True, 'splash': _splash_json(img)}, status=201)


# ============ 每日占卜 ============

# 22 张大阿卡纳：牌名 → 关键词
TAROT_CARDS = {
    '愚人': '新的开始 · 冒险 · 纯真',
    '魔术师': '创造力 · 行动 · 自信',
    '女祭司': '直觉 · 内心的声音 · 神秘',
    '女皇': '丰盛 · 温柔 · 滋养',
    '皇帝': '秩序 · 责任 · 掌控',
    '教皇': '传统 · 指引 · 信念',
    '恋人': '爱 · 契合 · 选择',
    '战车': '意志 · 前进 · 胜利',
    '力量': '勇气 · 耐心 · 温柔的力量',
    '隐士': '沉淀 · 内省 · 寻找答案',
    '命运之轮': '转机 · 循环 · 好运将至',
    '正义': '公平 · 清晰 · 因果',
    '倒吊人': '换位思考 · 等待 · 放下',
    '死神': '结束与重生 · 蜕变 · 告别',
    '节制': '平衡 · 调和 · 慢慢来',
    '恶魔': '执念 · 束缚 · 看清欲望',
    '高塔': '突变 · 打破 · 重建',
    '星星': '希望 · 治愈 · 美好预兆',
    '月亮': '朦胧 · 情绪 · 潜意识的提示',
    '太阳': '快乐 · 成功 · 满满的能量',
    '审判': '觉醒 · 召唤 · 新的阶段',
    '世界': '圆满 · 完成 · 旅程的收获',
}

# 牌名 → 塔罗牌图片文件名（韦特塔罗，公有领域）
TAROT_CARD_IMAGES = {
    '愚人': '00_fool.jpg',
    '魔术师': '01_magician.jpg',
    '女祭司': '02_high_priestess.jpg',
    '女皇': '03_empress.jpg',
    '皇帝': '04_emperor.jpg',
    '教皇': '05_hierophant.jpg',
    '恋人': '06_lovers.jpg',
    '战车': '07_chariot.jpg',
    '力量': '08_strength.jpg',
    '隐士': '09_hermit.jpg',
    '命运之轮': '10_wheel_of_fortune.jpg',
    '正义': '11_justice.jpg',
    '倒吊人': '12_hanged_man.jpg',
    '死神': '13_death.jpg',
    '节制': '14_temperance.jpg',
    '恶魔': '15_devil.jpg',
    '高塔': '16_tower.jpg',
    '星星': '17_star.jpg',
    '月亮': '18_moon.jpg',
    '太阳': '19_sun.jpg',
    '审判': '20_judgement.jpg',
    '世界': '21_world.jpg',
}


def _draw_three_cards(date_str):
    """抽三张不重复的牌（时间之流牌阵：过去-现在-未来）：
    以日期哈希为种子，同一天恒定，天然保证正逆位固定。
    """
    seed = int(hashlib.md5(f'tarot-{date_str}'.encode()).hexdigest()[:8], 16)
    rng = random.Random(seed)
    names = rng.sample(list(TAROT_CARDS), 3)
    positions = ('过去', '现在', '未来')
    cards = []
    for position, name in zip(positions, names):
        orientation = '正位' if rng.random() < 0.7 else '逆位'
        cards.append(
            {
                'position': position,
                'name': name,
                'orientation': orientation,
                'keyword': TAROT_CARDS[name],
                'image': f'/media/tarot/{TAROT_CARD_IMAGES[name]}',
            }
        )
    return cards


def _generate_reading(cards, her_name):
    """调用 DeepSeek 为三张牌阵生成当日解读，失败时返回兜底文案。"""
    name = (her_name or '').strip() or '你'

    def _card_line(card):
        return f"{card['position']}：「{card['name']} · {card['orientation']}」，牌意关键词：{card['keyword']}"

    card_lines = '\n'.join(_card_line(c) for c in cards)
    messages = [
        {
            'role': 'system',
            'content': (
                '你是一位温柔神秘的塔罗占卜师。'
                '语气温暖治愈、带一点神秘感。禁止使用Markdown格式，直接输出纯文本。'
            ),
        },
        {
            'role': 'user',
            'content': (
                f'今天是{name}抽到的三张牌阵（时间之流：过去-现在-未来）：\n'
                f'{card_lines}\n'
                '请为今天写一段塔罗解读，你的回答必须严格符合以下格式：\n'
                '只输出恰好两行：第一行以【今日解读】开头，第二行以【幸运指引】开头；'
                '不要有任何前言、后语、解释、编号或其他符号；两行顺序不可颠倒；'
                '标记符号只能用中文全角【】，不要用括号、冒号等其他符号代替。\n'
                '【今日解读】120~180字，把三张牌串成一个完整的故事：过去的位置轻轻回顾、'
                '现在的位置描述今日课题、未来的位置给出温柔展望，语言要像在她耳边轻声说话。\n'
                '【幸运指引】20字以内的一句今日幸运提示（如幸运色、幸运小物或一个温暖的小建议）。\n'
                '输出格式示例（仅为格式参考，内容请结合今天的三张牌重新写，不要照抄）：\n'
                '【今日解读】<一段温柔解读>\n'
                '【幸运指引】<一句幸运提示>'
            ),
        },
    ]
    text = chat(messages, temperature=0.9, timeout=60).strip()
    # 解析【今日解读】与【幸运指引】两段；模型偶尔不守格式，用正则加兜底
    reading, lucky = '', ''
    m = re.search(r'【今日解读】\s*(.*?)(?=【幸运指引】|$)', text, re.S)
    if m:
        reading = m.group(1).strip()
    m = re.search(r'【幸运指引】\s*(.*)$', text, re.S)
    if m:
        lucky = m.group(1).strip()
    if not reading:
        reading = text
    if not lucky:
        # 模型漏输出幸运指引时，用“未来”位置的牌生成有意义的兜底，而非死板默认值
        future_card = cards[-1]
        lucky = f"幸运指引：未来牌「{future_card['name']}」提醒你，{future_card['keyword']}"
    return reading, lucky


@require_api_token
def api_divination_today(request):
    """今日占卜：当天首次请求抽牌并调 DeepSeek 生成解读，之后直接返回缓存（零点自动刷新）。"""
    today = timezone.localdate().isoformat()
    cached = Divination.objects.filter(date=today).first()
    if cached:
        return JsonResponse({'date': today, 'cached': True, 'divination': _divination_json(cached)})

    cards = _draw_three_cards(today)
    # 昵称取不到配置时用全局默认值，与 APP 端 RemoteConfig 展示保持一致
    her_name = (
        AppConfig.objects.filter(key='her_name').values_list('value', flat=True).first()
        or APP_CONFIG_DEFAULTS['her_name']
    )
    try:
        reading, lucky = _generate_reading(cards, her_name)
    except LLMError as exc:
        # DeepSeek 不可用时也落库兜底文案，保证当天后续请求稳定返回
        names = '、'.join(f"{c['name']}（{c['orientation']}）" for c in cards)
        reading = (
            f'今天抽到的是三张牌阵：{names}。'
            '星星暂时躲进了云里，占卜师没能连线成功，但好运气并不会缺席——'
            '愿你今天被温柔对待，遇到的都是小美好。'
        )
        future_card = cards[-1]
        lucky = f"幸运指引：未来牌「{future_card['name']}」提醒你，{future_card['keyword']}"

    obj, _ = Divination.objects.update_or_create(
        date=today,
        defaults={
            'cards': cards,
            'reading': reading,
            'lucky': lucky,
        },
    )
    return JsonResponse({'date': today, 'cached': False, 'divination': _divination_json(obj)})


def _divination_json(d):
    return {
        'cards': d.cards,
        'reading': d.reading,
        'lucky': d.lucky,
    }


# ============ 好句好段 ============


def _quote_json(q):
    """好句序列化（与 APP Quote.fromJson 字段对应）。

    注意：update_or_create 新建的对象 date 仍是传入的 str（未经过 DB 类型转换），
    与查询出的 date 对象不一致，统一用 str() 兼容两者。
    """
    return {
        'id': q.pk,
        'date': str(q.date),
        'text': q.text,
        'author': q.author,
        'source': q.source,
        'category': q.category,
        'image_url': q.image_url,
    }


@require_api_token
def api_quote_today(request):
    """今日好句：按日期缓存，当天首次请求从 hitokoto.cn 拉取并取 Pixabay 配图。
    配图失败导致 image_url 为空时，后续请求会重试补图（自愈）。"""
    today = timezone.localdate().isoformat()
    cached = Quote.objects.filter(date=today).first()
    if cached and cached.image_url:
        return JsonResponse({'date': today, 'cached': True, 'quote': _quote_json(cached)})

    if cached:
        # 已有句子但缺配图：用落库的关键词重试补图，成功则更新返回，失败仍返回原缓存
        from .services.cover_image import fetch_cover_url
        image_url = fetch_cover_url(cached.image_keyword)
        if image_url:
            cached.image_url = image_url
            cached.save(update_fields=['image_url'])
        return JsonResponse({'date': today, 'cached': True, 'quote': _quote_json(cached)})

    # 从 hitokoto.cn 拉取
    from .data.quotes import fetch_hitokoto
    item = fetch_hitokoto()
    if not item:
        return JsonResponse({'error': '好句数据源暂时不可用，请稍后再试'}, status=503)

    # Pixabay 配图：一次性取好落库，避免历史列表重复请求（免费额度 100 次/小时）
    from .services.cover_image import fetch_cover_url
    image_url = fetch_cover_url(item['image_keyword'])

    obj, _ = Quote.objects.update_or_create(
        date=today,
        defaults={
            'text': item['text'],
            'author': item['author'],
            'source': item['source'],
            'category': item['category'],
            'image_keyword': item['image_keyword'],
            'image_url': image_url,
            'uuid': item['uuid'],
            'detail_url': item['detail_url'],
        },
    )
    return JsonResponse({'date': today, 'cached': False, 'quote': _quote_json(obj)})


@require_api_token
def api_quote_history(request):
    """历史好句列表：按日期倒序。"""
    quotes = [
        _quote_json(q)
        for q in Quote.objects.all().order_by('-date')[:30]
    ]
    return JsonResponse({'total': len(quotes), 'quotes': quotes})


@require_api_token
def api_quote_random(request):
    """再来一条：实时从 hitokoto.cn 拉取，不缓存、不计数、不限制。
    每次请求新随机句子，需配新图（必要调用）；配图失败时回退到最近一张历史配图，
    再不行用默认意境图，保证前端不出现占位图。"""
    from .data.quotes import fetch_hitokoto
    item = fetch_hitokoto()
    if not item:
        return JsonResponse({'error': '好句数据源暂时不可用，请稍后再试'}, status=503)
    from .services.cover_image import DEFAULT_IMAGE_URL, fetch_cover_url
    image_url = fetch_cover_url(item['image_keyword'])
    if not image_url:
        fallback = Quote.objects.exclude(image_url='').order_by('-date').values_list('image_url', flat=True).first()
        image_url = fallback or DEFAULT_IMAGE_URL
    return JsonResponse({
        'text': item['text'],
        'author': item['author'],
        'source': item['source'],
        'category': item['category'],
        'image_url': image_url,
    })


# ============ 每日菜单（HowToCook 开源菜谱池） ============


def _meal_json(m):
    """每日菜单序列化（与 APP Dish.fromJson 字段对应），支持池子 dict 与 DailyMeal 模型。

    材料/步骤统一输出 JSON 数组；旧式按行文本也兼容。
    """
    def to_list(value):
        if value is None:
            return []
        if isinstance(value, list):
            return value
        text = str(value).strip()
        if not text:
            return []
        try:
            parsed = json.loads(text)
            if isinstance(parsed, list):
                return parsed
        except ValueError:
            pass
        return [l.strip() for l in text.splitlines() if l.strip()]

    if isinstance(m, DailyMeal):
        return {
            'id': m.name,
            'name': m.name,
            'category': m.category,
            'description': m.description,
            'ingredients': to_list(m.ingredients),
            'steps': to_list(m.steps),
            'image_url': m.image_url,
        }
    return {
        'id': m.get('name', ''),
        'name': m.get('name', ''),
        'category': m.get('category', ''),
        'description': m.get('description', ''),
        'ingredients': to_list(m.get('ingredients', [])),
        'steps': to_list(m.get('steps', [])),
        'image_url': m.get('image', ''),
    }


@require_api_token
def api_meal_today(request):
    """今日菜单：按日期缓存。当天首次访问从菜谱池随机抽一道落库，之后返回同一道。"""
    from .services import meal_pool
    today = timezone.localdate()
    meal = DailyMeal.objects.filter(date=today).first()
    if meal:
        return JsonResponse({'date': today.isoformat(), 'cached': True, 'meal': _meal_json(meal)})

    item = meal_pool.random_meal()
    if not item:
        return JsonResponse({'error': '菜谱池为空，请稍后再试'}, status=503)
    try:
        meal = DailyMeal.objects.create(
            date=today,
            name=item['name'],
            category=item.get('category', ''),
            description=item.get('description', ''),
            ingredients=json.dumps(item.get('ingredients', []), ensure_ascii=False),
            steps=json.dumps(item.get('steps', []), ensure_ascii=False),
            image_url=item.get('image', ''),
        )
    except IntegrityError:
        # 并发下已被其他请求创建，读取已存在的
        meal = DailyMeal.objects.get(date=today)
    return JsonResponse({'date': today.isoformat(), 'cached': False, 'meal': _meal_json(meal)})


@require_api_token
def api_meal_history(request):
    """历史每日菜单：按日期倒序，最多 30 条。"""
    meals = []
    for m in DailyMeal.objects.all().order_by('-date')[:30]:
        item = _meal_json(m)
        item['date'] = m.date.isoformat()
        meals.append(item)
    return JsonResponse({'total': len(meals), 'meals': meals})


@require_api_token
def api_meal_random(request):
    """随机菜单：从菜谱池随机抽一道，不落库、不影响今日菜单；尽量避开今日已选。"""
    from .services import meal_pool
    today_meal = DailyMeal.objects.filter(date=timezone.localdate()).first()
    today_name = today_meal.name if today_meal else None
    item = None
    for _ in range(5):
        candidate = meal_pool.random_meal()
        if not candidate:
            return JsonResponse({'error': '菜谱池为空，请稍后再试'}, status=503)
        item = candidate
        if meal_pool.pool_size() <= 1 or candidate['name'] != today_name:
            break
    return JsonResponse({'meal': _meal_json(item)})
