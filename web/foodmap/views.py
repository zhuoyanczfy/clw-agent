import json
import os
from pathlib import Path

from django import forms
from django.contrib import messages
from django.db.models import Count
from django.http import JsonResponse, StreamingHttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.http import require_POST

from .forms import DiningRecordForm
from .models import DiningRecord, DiningRecordPhoto, District, Restaurant, WishlistItem
from .services.agent import build_system_prompt, execute_tool_calls
from .services.llm import LLMError, chat_stream, chat_tool_round
from .services.profile import build_taste_profile
from .services.tools.registry import tools_schema

GEOJSON_PATH = Path(__file__).parent / 'geodata' / 'nanjing_districts.json'


def index(request):
    """主界面：南京分区地图 + 餐厅标记 + 底部区选择导航。"""
    districts = District.objects.annotate(
        rest_count=Count('restaurants', distinct=True),
        visited_count=Count('restaurants__records', distinct=True),
    ).order_by('id')
    # 地图只标记“去过”的餐厅（真实餐厅库可能有几千家，全部渲染会卡）
    restaurants = (
        Restaurant.objects.filter(records__isnull=False, lat__isnull=False, lng__isnull=False)
        .select_related('district')
        .prefetch_related('records')
        .distinct()
    )
    for r in restaurants:
        r.latest_date = r.latest_record.date if r.latest_record else None
    # 顶部统计：total_restaurants 是用户去过的数量，不是餐厅库总数
    total_restaurants = restaurants.count()
    total_records = DiningRecord.objects.count()
    districts_json = [
        {
            'id': d.id, 'name': d.name, 'adcode': d.adcode, 'count': d.rest_count,
            'visited_count': d.visited_count,
        }
        for d in districts
    ]
    restaurants_json = [
        {
            'id': r.id, 'name': r.name, 'lat': r.lat, 'lng': r.lng,
            'address': r.address, 'district': r.district.name,
            'latest_date': str(r.latest_date) if r.latest_date else None,
        }
        for r in restaurants
    ]
    return render(request, 'foodmap/index.html', {
        'districts': districts,
        'restaurants': restaurants,
        'total_restaurants': total_restaurants,
        'total_records': total_records,
        'districts_json': districts_json,
        'restaurants_json': restaurants_json,
    })


def districts_geojson(request):
    """返回南京区划 GeoJSON，并按 adcode 附加区内餐厅库数量与用户足迹数。"""
    with GEOJSON_PATH.open(encoding='utf-8') as f:
        geojson = json.load(f)
    # restaurant_count: 区内真实餐厅库数量；visited_count: 用户在该区去过的餐厅数
    stats = {
        d.adcode: (
            d.restaurants.count(),
            d.restaurants.filter(records__isnull=False).distinct().count(),
        )
        for d in District.objects.prefetch_related('restaurants')
    }
    for feature in geojson['features']:
        props = feature['properties']
        # GeoJSON 中 adcode 为数字，统一转为字符串与模型匹配
        adcode = str(props.get('adcode'))
        props['adcode'] = adcode
        props['restaurant_count'], props['visited_count'] = stats.get(adcode, (0, 0))
    return JsonResponse(geojson)


def district_list(request):
    """全部区列表（底部导航入口）。"""
    districts = District.objects.annotate(
        rest_count=Count('restaurants', distinct=True),
        record_count=Count('restaurants__records', distinct=True),
    ).order_by('-rest_count', 'id')
    return render(request, 'foodmap/district_list.html', {
        'districts': districts,
    })


def district_detail(request, district_id):
    """区页：区内真实餐厅（支持搜索），去过/有评分的排前面。"""
    district = get_object_or_404(District, pk=district_id)
    restaurants = (
        district.restaurants
        .annotate(rec_count=Count('records'))
        .prefetch_related('records')
        .order_by('-rec_count', '-rating', 'name')
    )
    visited = [r for r in restaurants if r.rec_count]
    restaurants_json = [
        {
            'id': r.pk, 'name': r.name, 'address': r.address,
            'rating': r.rating, 'rec_count': r.rec_count,
            'visited': r.rec_count > 0,
        }
        for r in restaurants
    ]
    return render(request, 'foodmap/district.html', {
        'district': district,
        'visited': visited,
        'restaurant_count': len(restaurants),
        'restaurants_json': restaurants_json,
    })


def restaurant_detail(request, restaurant_id):
    """餐厅页：餐厅信息 + 全部用餐记录。"""
    restaurant = get_object_or_404(Restaurant, pk=restaurant_id)
    records = restaurant.records.all()
    return render(request, 'foodmap/restaurant.html', {
        'restaurant': restaurant,
        'records': records,
    })


def record_detail(request, record_id):
    """用餐记录详情页。"""
    record = get_object_or_404(DiningRecord.objects.select_related('restaurant__district'), pk=record_id)
    return render(request, 'foodmap/record_detail.html', {
        'record': record,
    })


def record_form(request, record_id=None):
    """新增/编辑用餐记录。GET 展示表单，POST 保存。"""
    record = None
    if record_id:
        record = get_object_or_404(DiningRecord, pk=record_id)
    initial = {}
    if request.GET.get('district'):
        initial['district'] = request.GET['district']
    if request.GET.get('restaurant'):
        initial['restaurant'] = request.GET['restaurant']

    if request.method == 'POST':
        form = DiningRecordForm(request.POST, instance=record)
        if form.is_valid():
            saved = form.save()
            # 多图上传：一条记录可附加多张照片，逐张校验（Pillow 验证真实图片）后保存
            photo_field = forms.ImageField()
            for f in request.FILES.getlist('photos'):
                try:
                    photo_field.clean(f)
                except forms.ValidationError as exc:
                    messages.error(request, f'照片「{f.name}」未保存：{exc}')
                    continue
                DiningRecordPhoto.objects.create(record=saved, image=f)
            messages.success(request, '记录已保存')
            return redirect('foodmap:record_detail', saved.pk)
    else:
        form = DiningRecordForm(instance=record, initial=initial)

    # 餐厅搜索数据源：id/名称/所属区（供前端 datalist 搜索与按区过滤）
    restaurants_json = [
        {'id': pk, 'name': name, 'district_id': did}
        for pk, name, did in Restaurant.objects.values_list('pk', 'name', 'district_id')
    ]
    # 预选/编辑时输入框显示的餐厅名
    selected_pk = (record.restaurant_id if record else None) or initial.get('restaurant')
    selected_name = ''
    if selected_pk:
        selected_name = (
            Restaurant.objects.filter(pk=selected_pk).values_list('name', flat=True).first() or ''
        )

    return render(request, 'foodmap/record_form.html', {
        'form': form,
        'record': record,
        'districts': District.objects.annotate(rest_count=Count('restaurants')),
        'restaurants_json': restaurants_json,
        'selected_name': selected_name,
        'existing_photos': record.photos.all() if record else [],
    })


@require_POST
def photo_delete(request, photo_id):
    """删除单张用餐照片：先删数据库行，再删磁盘文件（Django 不会自动清理文件）。"""
    photo = get_object_or_404(DiningRecordPhoto, pk=photo_id)
    record_id = photo.record_id
    path = photo.image.path
    photo.delete()
    try:
        os.remove(path)
    except FileNotFoundError:
        pass
    if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        return JsonResponse({'ok': True})
    messages.success(request, '照片已删除')
    return redirect('foodmap:record_edit', record_id)


@require_POST
def record_delete(request, record_id):
    """删除用餐记录（POST）。"""
    record = get_object_or_404(DiningRecord, pk=record_id)
    restaurant_pk = record.restaurant.pk
    record.delete()
    messages.success(request, '记录已删除')
    return redirect('foodmap:restaurant_detail', restaurant_pk)


# ============ AI 智能推荐 ============

MAX_HISTORY = 20  # 会话保留的最大消息条数（不含 system）

# Agent 可用工具（function calling），定义见 foodmap/services/tools/registry.py
TOOLS_SCHEMA = tools_schema()


def recommend(request):
    """AI 推荐页：对话 tab + 待尝清单 tab。"""
    wishlist = WishlistItem.objects.select_related('district').all()
    pending_items = [item for item in wishlist if item.status == 'pending']
    eaten_items = [item for item in wishlist if item.status == 'eaten']
    # 待尝项若已关联数据库真实餐厅（按 amap_id），"去记录"时可直接预选
    amap_to_rest = {
        r.amap_id: r.pk
        for r in Restaurant.objects.exclude(amap_id__isnull=True)
    }
    for item in wishlist:
        item.linked_restaurant_id = amap_to_rest.get(item.amap_id)
    return render(request, 'foodmap/recommend.html', {
        'wishlist': wishlist,
        'pending_items': pending_items,
        'eaten_items': eaten_items,
        'wishlist_pending_count': len(pending_items),
    })


def chat(request):
    """SSE 流式对话接口。POST body: {"message": "...", "reset": true} 清空会话。"""
    if request.method != 'POST':
        return JsonResponse({'error': '仅支持 POST 请求'}, status=405)
    try:
        data = json.loads(request.body or b'{}')
    except ValueError:
        return JsonResponse({'error': '请求体不是合法 JSON'}, status=400)

    if data.get('reset'):
        request.session['ai_history'] = []
        return JsonResponse({'ok': True, 'message': '对话已重置'})

    message = (data.get('message') or '').strip()
    if not message:
        return JsonResponse({'error': '消息不能为空'}, status=400)

    history = request.session.get('ai_history') or []
    history = [m for m in history if m.get('role') in ('user', 'assistant')]
    history.append({'role': 'user', 'content': message})

    # system prompt 由 agent.md 定义（foodmap/agents/recommender/agent.md），注入画像与当前任务
    system_msg = {'role': 'system', 'content': build_system_prompt(profile=build_taste_profile(), task=message)}
    messages_payload = [system_msg] + history[-MAX_HISTORY:]

    def sse_generator():
        full_reply = ''
        try:
            # 第一轮（非流式）：带 tools 让模型决定是否调用工具（查真实餐厅库）
            tool_round = chat_tool_round(messages_payload, TOOLS_SCHEMA)
            tool_calls = tool_round.get('tool_calls') or []
            if tool_calls:
                # 执行工具 → 组装 role=tool 结果消息 → 第二轮流式出最终回复
                assistant_msg = {
                    'role': 'assistant',
                    'content': tool_round.get('content') or '',
                    'tool_calls': tool_calls,
                }
                tool_results = execute_tool_calls(tool_calls)
                final_messages = messages_payload + [assistant_msg] + tool_results
                for delta in chat_stream(final_messages):
                    full_reply += delta
                    yield f'data: {json.dumps({"delta": delta}, ensure_ascii=False)}\n\n'
            else:
                # 模型直接回答（如寒暄/追问偏好）：一次性下发
                full_reply = tool_round.get('content') or ''
                yield f'data: {json.dumps({"delta": full_reply}, ensure_ascii=False)}\n\n'
            history.append({'role': 'assistant', 'content': full_reply})
            request.session['ai_history'] = history[-MAX_HISTORY:]
            # SSE 流式响应：SessionMiddleware 在生成器运行前已完成请求处理，必须显式保存
            request.session.save()
            yield 'data: [DONE]\n\n'
        except LLMError as exc:
            yield f'data: {json.dumps({"error": str(exc)}, ensure_ascii=False)}\n\n'
            yield 'data: [DONE]\n\n'

    response = StreamingHttpResponse(sse_generator(), content_type='text/event-stream')
    response['Cache-Control'] = 'no-cache'
    response['X-Accel-Buffering'] = 'no'
    return response


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
        'created_at': item.created_at.strftime('%Y-%m-%d %H:%M'),
    }


def _parse_per_capita(value):
    try:
        if value:
            parsed = int(value)
            return parsed if parsed > 0 else None
    except (TypeError, ValueError):
        pass
    return None


@require_POST
def recommend_verify(request):
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


@require_POST
def wishlist_add(request):
    """收藏 AI 推荐的餐厅到待尝清单。"""
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
        source='ai',
    )
    return JsonResponse({'ok': True, 'item': _wishlist_json(item)})


@require_POST
def wishlist_eaten(request, item_id):
    """标记待尝餐厅为已尝。"""
    item = get_object_or_404(WishlistItem, pk=item_id)
    item.status = 'eaten'
    item.save(update_fields=['status'])
    return JsonResponse({'ok': True, 'item': _wishlist_json(item)})


@require_POST
def wishlist_delete(request, item_id):
    """删除待尝清单项。"""
    item = get_object_or_404(WishlistItem, pk=item_id)
    item.delete()
    return JsonResponse({'ok': True})
    return JsonResponse({'ok': True})
