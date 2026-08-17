# -*- coding: utf-8 -*-
"""核心逻辑单测：坐标转换、日期取模两端一致、塔罗抽牌/解读解析。

覆盖隐性契约（代码 review 关注点）：
1. GCJ-02 <-> WGS-84 双向转换（amap.py，与前端互为逆运算）
2. 后端 dish_for_date 与 APP 内置库算法/顺序一致（md5(日期) 取模）
3. 塔罗抽牌确定性 + DeepSeek 解读解析兜底（_parse_reading）
"""
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import quote

from django.test import TestCase

from foodmap.auth import _load_api_token
from foodmap.dishes_full import DISHES_FULL
from foodmap.models import ChatSession, DailyMeal, Dish, FavoriteDish
from foodmap.services.amap import gcj02_to_wgs84, wgs84_to_gcj02
from foodmap.views import _draw_three_cards, _parse_reading, dish_for_date

APP_DISHES_DART = (
    Path(__file__).resolve().parent.parent.parent
    / 'app' / 'lib' / 'data' / 'dishes.dart'
)


def _md5_mod(date_str, length):
    """与后端 dish_for_date / APP _fromBuiltin 相同的 md5 前 8 位取模算法。"""
    return int(hashlib.md5(date_str.encode()).hexdigest()[:8], 16) % length


class CoordConversionTests(TestCase):
    """GCJ-02 <-> WGS-84 互逆与境外原样返回。"""

    def test_roundtrip_nanjing(self):
        # 南京新街口附近的 GCJ-02 坐标（高德返回），转 WGS 再转回应还原
        gcj = (118.778074, 32.057236)
        wgs = gcj02_to_wgs84(*gcj)
        back = wgs84_to_gcj02(*wgs)
        # 近似逆运算，往返误差约 1e-6 度（0.6 米内），阈值放宽到 1e-5 度
        self.assertLess(abs(back[0] - gcj[0]), 1e-5)
        self.assertLess(abs(back[1] - gcj[1]), 1e-5)

    def test_out_of_china_unchanged(self):
        # 境外（美国纽约）坐标应原样返回
        for fn in (gcj02_to_wgs84, wgs84_to_gcj02):
            self.assertEqual(fn(-74.0060, 40.7128), (-74.0060, 40.7128))

    def test_nanjing_conversion_snapshot(self):
        # 快照：锁定当前实现的具体输出，防止后续改动破坏坐标转换
        self.assertEqual(
            gcj02_to_wgs84(118.778074, 32.057236),
            (118.77286373060447, 32.05928707899662),
        )


class DishDateAlgorithmTests(TestCase):
    """锁住隐性契约：APP 内置库顺序 == dishes_full.py 顺序 == 后端 order_by('sort','id')，
    保证 md5(日期) 取模在两端推出同一道菜。"""

    @classmethod
    def setUpTestData(cls):
        # 模拟 seed_dishes 导入（sort = DISHES_FULL 索引）
        for idx, item in enumerate(DISHES_FULL):
            Dish.objects.create(
                slug=item['slug'],
                name=item['name'],
                category=item.get('category', ''),
                description=item.get('description', ''),
                ingredients=item.get('ingredients', ''),
                steps=item.get('steps', ''),
                image_url=item.get('image_url', ''),
                sort=idx,
                enabled=True,
            )

    def test_app_builtin_order_matches_dishes_full(self):
        # APP 内置库 id 顺序必须与 dishes_full.py 一致（由 tmp/gen_dishes_dart.py 生成）
        text = APP_DISHES_DART.read_text(encoding='utf-8')
        ids = re.findall(r"id: '([^']+)'", text)
        self.assertEqual(ids, [d['slug'] for d in DISHES_FULL])

    def test_dish_for_date_equals_pure_md5_mod(self):
        for date_str in ('2026-08-17', '2026-08-01', '2027-01-01', '2025-12-31'):
            with self.subTest(date=date_str):
                dish = dish_for_date(date_str)
                self.assertEqual(
                    dish.slug,
                    DISHES_FULL[_md5_mod(date_str, len(DISHES_FULL))]['slug'],
                )

    def test_same_date_stable(self):
        d1 = dish_for_date('2026-08-17')
        d2 = dish_for_date('2026-08-17')
        self.assertEqual(d1.id, d2.id)


class TarotDrawTests(TestCase):
    """塔罗抽牌：同一天恒定、三张不重复、位置与正逆位合法。"""

    def test_same_date_same_cards(self):
        self.assertEqual(_draw_three_cards('2026-08-17'), _draw_three_cards('2026-08-17'))

    def test_three_distinct_cards_with_positions(self):
        cards = _draw_three_cards('2026-08-17')
        self.assertEqual(len(cards), 3)
        self.assertEqual([c['position'] for c in cards], ['过去', '现在', '未来'])
        names = [c['name'] for c in cards]
        self.assertEqual(len(set(names)), 3, '三张牌不应重复')
        for c in cards:
            self.assertIn(c['orientation'], ('正位', '逆位'))
            self.assertTrue(c['image'].startswith('/media/tarot/'))
            self.assertTrue(c['keyword'])


class ReadingParseTests(TestCase):
    """DeepSeek 解读回复的解析兜底逻辑（_parse_reading 纯函数）。"""

    @staticmethod
    def _cards():
        return _draw_three_cards('2026-08-17')

    def test_normal_format(self):
        text = '【今日解读】今天很适合慢慢来。\n【幸运指引】幸运色是暖黄色'
        reading, lucky = _parse_reading(text, self._cards())
        self.assertEqual(reading, '今天很适合慢慢来。')
        self.assertEqual(lucky, '幸运色是暖黄色')

    def test_missing_lucky_fallback_to_future_card(self):
        text = '【今日解读】一段温柔的解读内容'
        cards = self._cards()
        reading, lucky = _parse_reading(text, cards)
        self.assertEqual(reading, '一段温柔的解读内容')
        self.assertIn(cards[-1]['name'], lucky)
        self.assertIn('幸运指引', lucky)

    def test_missing_reading_falls_back_to_full_text(self):
        text = '模型完全跑偏输出了别的内容'
        reading, lucky = _parse_reading(text, self._cards())
        self.assertEqual(reading, text)
        self.assertTrue(lucky)

    def test_reading_stops_at_lucky_marker(self):
        text = '【今日解读】第一段。\n【幸运指引】第二段。\n【今日解读】不应再出现'
        reading, lucky = _parse_reading(text, self._cards())
        self.assertEqual(reading, '第一段。')
        self.assertEqual(lucky, '第二段。')


class FavoriteSnapshotTests(TestCase):
    """收藏快照：每日菜单（菜库外）的菜也能收藏并完整展示，中文菜名可删除。"""

    @classmethod
    def setUpTestData(cls):
        cls.token = _load_api_token()
        cls.headers = {'HTTP_X_API_TOKEN': cls.token}
        Dish.objects.create(
            slug='tomato-beef',
            name='番茄牛腩',
            category='热菜',
            description='暖心暖胃',
            ingredients='牛腩 500 克',
            steps='焯水后炖煮',
            image_url='/media/dishes/tomato-beef.jpg',
            sort=0,
            enabled=True,
        )
        DailyMeal.objects.create(
            date='2026-08-17',
            name='逼真豆沙毛毛虫',
            category='主食',
            description='以假乱真的可爱造型',
            ingredients=json.dumps(['面粉 300 克', '豆沙 200 克'], ensure_ascii=False),
            steps=json.dumps(['和面发酵', '包馅整形'], ensure_ascii=False),
            image_url='/media/meals/2026-08-17.jpg',
        )

    def test_meal_favorite_slug_only_backfilled_from_meal(self):
        # 只传 slug（菜名）：后端从每日菜单补全内容
        resp = self.client.post(
            '/api/favorites/',
            data=json.dumps({'slug': '逼真豆沙毛毛虫'}, ensure_ascii=False),
            content_type='application/json',
            **self.headers,
        )
        self.assertEqual(resp.status_code, 200)
        fav = FavoriteDish.objects.get(slug='逼真豆沙毛毛虫')
        self.assertIsNone(fav.dish_id)
        self.assertEqual(fav.name, '逼真豆沙毛毛虫')

        listing = self.client.get('/api/favorites/', **self.headers).json()
        self.assertEqual(len(listing['favorites']), 1)
        item = listing['favorites'][0]
        self.assertEqual(item['id'], '逼真豆沙毛毛虫')
        self.assertEqual(item['ingredients'], ['面粉 300 克', '豆沙 200 克'])
        self.assertEqual(item['steps'], ['和面发酵', '包馅整形'])
        self.assertEqual(item['image_url'], '/media/meals/2026-08-17.jpg')

    def test_snapshot_from_request_body(self):
        # 菜库与每日菜单都没有的菜：用请求体完整内容建快照
        resp = self.client.post(
            '/api/favorites/',
            data=json.dumps({
                'slug': '创意小炒',
                'name': '创意小炒',
                'category': '创意菜',
                'description': '临时创意',
                'ingredients': ['时蔬 200 克'],
                'steps': ['快炒'],
                'image_url': '',
            }, ensure_ascii=False),
            content_type='application/json',
            **self.headers,
        )
        self.assertEqual(resp.status_code, 200)
        listing = self.client.get('/api/favorites/', **self.headers).json()
        item = next(
            f for f in listing['favorites'] if f['id'] == '创意小炒'
        )
        self.assertEqual(item['name'], '创意小炒')
        self.assertEqual(item['ingredients'], ['时蔬 200 克'])

    def test_dish_favorite_links_and_delete_by_slug(self):
        resp = self.client.post(
            '/api/favorites/',
            data=json.dumps({'slug': 'tomato-beef'}),
            content_type='application/json',
            **self.headers,
        )
        self.assertEqual(resp.status_code, 200)
        fav = FavoriteDish.objects.get(slug='tomato-beef')
        self.assertEqual(fav.dish.slug, 'tomato-beef')

        resp = self.client.delete('/api/favorites/tomato-beef/', **self.headers)
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(FavoriteDish.objects.filter(slug='tomato-beef').exists())

    def test_chinese_name_delete(self):
        self.client.post(
            '/api/favorites/',
            data=json.dumps({'slug': '逼真豆沙毛毛虫'}, ensure_ascii=False),
            content_type='application/json',
            **self.headers,
        )
        resp = self.client.delete(
            f'/api/favorites/{quote("逼真豆沙毛毛虫")}/', **self.headers
        )
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(
            FavoriteDish.objects.filter(slug='逼真豆沙毛毛虫').exists()
        )

    def test_unknown_slug_rejected(self):
        resp = self.client.post(
            '/api/favorites/',
            data=json.dumps({'slug': '根本不存在的菜'}, ensure_ascii=False),
            content_type='application/json',
            **self.headers,
        )
        self.assertEqual(resp.status_code, 404)

    def test_re_favorite_updates_not_duplicates(self):
        for _ in range(2):
            self.client.post(
                '/api/favorites/',
                data=json.dumps({'slug': 'tomato-beef'}),
                content_type='application/json',
                **self.headers,
            )
        self.assertEqual(FavoriteDish.objects.filter(slug='tomato-beef').count(), 1)


class ChatSessionPaginationTests(TestCase):
    """推荐官会话列表分页：offset/limit 与 total，旧接口行为兼容。"""

    @classmethod
    def setUpTestData(cls):
        cls.token = _load_api_token()
        cls.headers = {'HTTP_X_API_TOKEN': cls.token}
        for i in range(3):
            ChatSession.objects.create(title=f'会话{i}')

    def test_first_page_with_limit(self):
        body = self.client.get(
            '/api/chat/sessions/?limit=2', **self.headers
        ).json()
        self.assertEqual(body['total'], 3)
        self.assertEqual(len(body['sessions']), 2)
        self.assertEqual(body['offset'], 0)
        self.assertEqual(body['limit'], 2)

    def test_second_page(self):
        body = self.client.get(
            '/api/chat/sessions/?offset=2&limit=2', **self.headers
        ).json()
        self.assertEqual(body['total'], 3)
        self.assertEqual(len(body['sessions']), 1)

    def test_invalid_params_fallback(self):
        # limit=0 钳到下限 1，offset=-1 钳到 0
        body = self.client.get(
            '/api/chat/sessions/?limit=0&offset=-1', **self.headers
        ).json()
        self.assertEqual(body['limit'], 1)
        self.assertEqual(body['offset'], 0)

    def test_default_limit_is_20(self):
        body = self.client.get('/api/chat/sessions/', **self.headers).json()
        self.assertEqual(body['limit'], 20)
        self.assertEqual(body['total'], 3)
        self.assertEqual(len(body['sessions']), 3)
