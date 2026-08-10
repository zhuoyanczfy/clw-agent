"""批量导入高德真实餐饮 POI 到 Restaurant 表。

用法：
    python manage.py import_amap_poi                        # 全量导入南京 11 区
    python manage.py import_amap_poi --districts 鼓楼区,玄武区
    python manage.py import_amap_poi --limit-per-grid 2     # 每格最多 2 页（快速试跑）
    python manage.py import_amap_poi --dry-run              # 只统计不写库

说明：
- 按区边界生成约 3.3km 网格，用高德多边形搜索（types=050000 餐饮服务）逐格拉取
- 坐标从 GCJ-02 转 WGS-84 入库（与前端渲染转换抵消）
- 已存在的高德 POI（amap_id 唯一）自动跳过，可重复执行断点续传
"""
import json
import time
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError

from foodmap.models import District, Restaurant
from foodmap.services.amap import (
    AMAPError,
    GRID_STEP,
    gcj02_to_wgs84,
    iter_grid_pois,
    point_in_polygon,
)

GEOJSON_PATH = Path(__file__).resolve().parent.parent.parent.parent / 'foodmap' / 'geodata' / 'nanjing_districts.json'


def _polygon_bbox(polygon):
    lngs = [p[0] for p in polygon]
    lats = [p[1] for p in polygon]
    return min(lngs), min(lats), max(lngs), max(lats)


class Command(BaseCommand):
    help = '从高德地图导入真实餐饮 POI 到 Restaurant 表'

    def add_arguments(self, parser):
        parser.add_argument('--districts', default='', help='只导入指定区，逗号分隔，默认全部')
        parser.add_argument('--limit-per-grid', type=int, default=0, help='每格最多拉取页数（用于快速试跑）')
        parser.add_argument('--dry-run', action='store_true', help='只统计不写库')

    def handle(self, *args, **options):
        with GEOJSON_PATH.open(encoding='utf-8') as f:
            geojson = json.load(f)

        # 目标区：GeoJSON 区名 -> 多边形列表
        wanted = set(name.strip() for name in options['districts'].split(',') if name.strip())
        region_polys = {}
        for feature in geojson['features']:
            name = feature['properties']['name']
            if wanted and name not in wanted:
                continue
            polys = [ring[0] for ring in feature['geometry']['coordinates'] if ring]
            region_polys[name] = polys

        if not region_polys:
            raise CommandError(f'未找到可导入的区，现有区：{", ".join(d.name for d in District.objects.all())}')

        existing_ids = set(
            Restaurant.objects.exclude(amap_id__isnull=True).values_list('amap_id', flat=True)
        )
        district_map = {d.name: d for d in District.objects.all()}
        limit_pages = options['limit_per_grid'] or None
        dry_run = options['dry_run']

        total_new = 0
        total_skip = 0
        total_calls = 0
        created = []
        for region_name, polys in region_polys.items():
            if region_name not in district_map:
                self.stdout.write(self.style.WARNING(f'跳过未知区: {region_name}'))
                continue
            district = district_map[region_name]
            region_new = 0
            grids = self._grids_for_region(polys)
            self.stdout.write(f'[{region_name}] 生成 {len(grids)} 个有效网格，开始拉取…')
            for i, grid in enumerate(grids, 1):
                try:
                    for poi in iter_grid_pois(grid, limit_pages=limit_pages):
                        total_calls += 1
                        poi_id = poi.get('id')
                        if not poi_id or poi_id in existing_ids:
                            total_skip += 1
                            continue
                        ok, name = self._save_poi(poi, district, dry_run)
                        if ok:
                            total_new += 1
                            region_new += 1
                            existing_ids.add(poi_id)
                            created.append(name)
                except AMAPError as exc:
                    self.stdout.write(self.style.ERROR(f'  [网格 {i}] 拉取失败: {exc}'))
                    continue
                if i % 20 == 0 or i == len(grids):
                    self.stdout.write(f'  [{region_name}] 网格 {i}/{len(grids)}，本区新增 {region_new} 家')
            self.stdout.write(self.style.SUCCESS(f'[{region_name}] 完成，本区新增 {region_new} 家'))
            time.sleep(0.5)

        self.stdout.write(self.style.SUCCESS(
            f'导入结束：新增 {total_new} 家，跳过 {total_skip} 条（已存在或无 id）'
            + ('（dry-run 未写库）' if dry_run else '')
        ))
        if created:
            self.stdout.write('示例：' + '、'.join(created[:10]))

    def _grids_for_region(self, polys):
        """生成落在区多边形内的网格（中心点判定，先按外接矩形粗筛）。"""
        all_lngs, all_lats = [], []
        for poly in polys:
            min_lng, min_lat, max_lng, max_lat = _polygon_bbox(poly)
            all_lngs += [min_lng, max_lng]
            all_lats += [min_lat, max_lat]
        min_lng, max_lng = min(all_lngs), max(all_lngs)
        min_lat, max_lat = min(all_lats), max(all_lats)

        grids = []
        lat = min_lat
        while lat < max_lat:
            lng = min_lng
            while lng < max_lng:
                center = (lng + GRID_STEP / 2, lat + GRID_STEP / 2)
                if any(
                    bbox[0] <= center[0] <= bbox[2] and bbox[1] <= center[1] <= bbox[3]
                    and point_in_polygon(center[0], center[1], poly)
                    for poly in polys
                    for bbox in [_polygon_bbox(poly)]
                ):
                    grids.append((lng, lat, lng + GRID_STEP, lat + GRID_STEP))
                lng += GRID_STEP
            lat += GRID_STEP
        return grids

    def _save_poi(self, poi, district, dry_run):
        """转换坐标并入库，返回 (是否新增, 餐厅名)。"""
        adname = poi.get('adname') or ''
        if adname and adname != district.name:
            return False, ''
        location = poi.get('location', '')
        if not location:
            return False, ''
        try:
            lng, lat = (float(x) for x in location.split(','))
        except ValueError:
            return False, ''
        lng, lat = gcj02_to_wgs84(lng, lat)

        name = (poi.get('name') or '').strip()[:100]
        if not name:
            return False, ''
        biz_ext = poi.get('biz_ext') or {}
        rating = None
        try:
            rating = float(biz_ext.get('rating'))
        except (TypeError, ValueError):
            pass

        if not dry_run:
            Restaurant.objects.create(
                name=name,
                district=district,
                address=(poi.get('address') or '').strip()[:200],
                lat=lat,
                lng=lng,
                amap_id=poi.get('id'),
                rating=rating,
            )
        return True, name
