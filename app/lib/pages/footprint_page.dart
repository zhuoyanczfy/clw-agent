import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/district.dart';
import '../models/dining_record.dart';
import '../models/restaurant.dart';
import '../services/foodmap_api.dart';
import '../theme.dart';
import 'record_form_page.dart';
import 'restaurant_detail_page.dart';

/// 美食足迹：南京分区地图 + 用餐记录列表（底部导航第 3 个 Tab）。
class FootprintPage extends StatefulWidget {
  const FootprintPage({super.key});

  @override
  State<FootprintPage> createState() => _FootprintPageState();
}

class _FootprintPageState extends State<FootprintPage> {
  final _mapController = MapController();
  bool _loading = true;
  String? _error;
  List<District> _districts = [];
  List<Restaurant> _restaurants = [];
  List<DiningRecord> _records = [];
  Map<String, dynamic>? _geoJson;
  int? _selectedDistrictId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        FoodmapApi.fetchDistricts(),
        FoodmapApi.fetchRestaurants(visitedOnly: true),
        FoodmapApi.fetchRecords(),
        FoodmapApi.fetchDistrictsGeoJson(),
      ]);
      if (!mounted) return;
      setState(() {
        _districts = results[0] as List<District>;
        _restaurants = results[1] as List<Restaurant>;
        _records = results[2] as List<DiningRecord>;
        _geoJson = results[3] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  District? get _selectedDistrict {
    for (final d in _districts) {
      if (d.id == _selectedDistrictId) return d;
    }
    return null;
  }

  /// 解析 GeoJSON 的 MultiPolygon 为 flutter_map 的 Polygon
  List<Polygon> _buildPolygons() {
    final geo = _geoJson;
    if (geo == null) return [];
    final visitedMap = {for (final d in _districts) d.adcode: d.visitedCount};
    final polygons = <Polygon>[];
    for (final feature in (geo['features'] as List)) {
      final props = (feature as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      if (geometry['type'] != 'MultiPolygon') continue;
      final adcode = props['adcode']?.toString() ?? '';
      final visited = visitedMap[adcode] ?? 0;
      final isSelected = _selectedDistrictId != null &&
          _selectedDistrict != null &&
          adcode == _selectedDistrict!.adcode;
      final color = isSelected
          ? const Color(0xFFFF8C9E)
          : visited > 0
              ? const Color(0x33FF8C9E)
              : const Color(0x1A9B8F85);
      for (final polygon in (geometry['coordinates'] as List)) {
        final ring = (polygon as List).first as List;
        polygons.add(Polygon(
          points: [
            for (final pt in ring)
              LatLng((pt as List)[1] as double, pt[0] as double),
          ],
          color: color,
          borderColor: isSelected ? AppTheme.primaryDark : const Color(0x66FFFFFF),
          borderStrokeWidth: isSelected ? 2.5 : 1.2,
        ));
      }
    }
    return polygons;
  }

  List<Marker> _buildMarkers() {
    final showAll = _selectedDistrictId == null;
    return [
      for (final r in _restaurants)
        // 后端部分餐厅可能没有坐标（如手动录入），跳过避免 LatLng 空值异常
        if ((showAll || r.districtId == _selectedDistrictId) && r.lat != null && r.lng != null)
          Marker(
            point: LatLng(r.lat!, r.lng!),
            width: 36,
            height: 36,
            child: GestureDetector(
              onTap: () => _openRestaurant(r.id),
              child: Container(
                decoration: BoxDecoration(
                  color: r.visited ? AppTheme.primary : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.restaurant, size: 16, color: Colors.white),
              ),
            ),
          ),
    ];
  }

  void _openRestaurant(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RestaurantDetailPage(restaurantId: id)),
    );
  }

  /// 点击区 chip：地图缩放到该区，再次点击取消
  void _onSelectDistrict(District? d) async {
    setState(() => _selectedDistrictId = d?.id);
    if (d == null) return;
    final geo = _geoJson;
    if (geo == null) return;
    final points = <LatLng>[];
    for (final feature in (geo['features'] as List)) {
      final props = (feature as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
      if (props['adcode']?.toString() != d.adcode) continue;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      for (final polygon in (geometry['coordinates'] as List)) {
        for (final ring in (polygon as List)) {
          for (final pt in (ring as List)) {
            points.add(LatLng((pt as List)[1] as double, pt[0] as double));
          }
        }
      }
    }
    if (points.isNotEmpty) {
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(48),
          ),
        );
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('美食足迹'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: AppTheme.textLight),
              const SizedBox(height: 12),
              Text(
                '无法连接美食足迹后端\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textLight),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                _StatChip(icon: Icons.room, text: '去过 ${_restaurants.length} 家'),
                const SizedBox(width: 8),
                _StatChip(icon: Icons.notes, text: '记录 ${_records.length} 条'),
                const Spacer(),
                // 图例：深色 = 去过的区
                const Icon(Icons.circle, size: 12, color: AppTheme.primary),
                const SizedBox(width: 4),
                const Text('去过', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
                const SizedBox(width: 8),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0x1A9B8F85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 4),
                const Text('没去过', style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              ],
            ),
          ),
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.map_outlined), text: '足迹地图'),
              Tab(icon: Icon(Icons.list_alt), text: '用餐记录'),
            ],
            labelColor: AppTheme.primaryDark,
            indicatorColor: AppTheme.primary,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildMapTab(),
                _buildRecordsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapTab() {
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(32.06, 118.80),
                    initialZoom: 10,
                    minZoom: 8,
                    maxZoom: 17,
                  ),
                  children: [
                    // 底图用腾讯瓦片（国内可达、无需 key）；OSM 官方源在国内经常连不上。
                    // 腾讯瓦片是 TMS 风格（y 自南向北），与 flutter_map 默认 XYZ 相反，需 tms: true 翻转
                    TileLayer(
                      urlTemplate: 'https://rt0.map.gtimg.com/tile?z={z}&x={x}&y={y}&styleid=1',
                      tms: true,
                      userAgentPackageName: 'com.gift.dailycare',
                    ),
                    PolygonLayer(polygons: _buildPolygons()),
                    MarkerLayer(markers: _buildMarkers()),
                  ],
                ),
                if (_selectedDistrict != null)
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryDark,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_selectedDistrict!.name} · 去过的餐厅 ${_restaurants.where((r) => r.districtId == _selectedDistrict!.id).length} 家',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // 区选择条
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _DistrictChip(
                name: '全部',
                selected: _selectedDistrictId == null,
                onTap: () => _onSelectDistrict(null),
              ),
              for (final d in _districts)
                _DistrictChip(
                  name: d.name,
                  selected: _selectedDistrictId == d.id,
                  visited: d.visitedCount > 0,
                  onTap: () => _onSelectDistrict(d),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecordsTab() {
    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant_menu, size: 48, color: AppTheme.textLight),
            const SizedBox(height: 12),
            const Text('还没有用餐记录，去记录第一家吧',
                style: TextStyle(color: AppTheme.textLight)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecordFormPage()),
                );
                _load();
              },
              child: const Text('记录一次用餐'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _records.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return FilledButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecordFormPage()),
                );
                _load();
              },
              icon: const Icon(Icons.add),
              label: const Text('记录一次用餐'),
            );
          }
          final r = _records[index - 1];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFFFE9E9),
                child: Text('${r.rating}★',
                    style: const TextStyle(fontSize: 13, color: AppTheme.primaryDark)),
              ),
              title: Text(r.restaurant,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${r.date} · ${r.district}'
                '${r.mood.isNotEmpty ? ' · ${r.mood}' : ''}'
                '${r.perCapita != null ? ' · ¥${r.perCapita}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: r.comment.isNotEmpty,
              trailing: const Icon(Icons.chevron_right, color: AppTheme.textLight),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => _RecordDetailPage(record: r)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _StatChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryDark),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, color: AppTheme.textDark)),
        ],
      ),
    );
  }
}

class _DistrictChip extends StatelessWidget {
  final String name;
  final bool selected;
  final bool visited;
  final VoidCallback onTap;
  const _DistrictChip({
    required this.name,
    required this.selected,
    this.visited = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: visited
                  ? AppTheme.primary.withValues(alpha: 0.6)
                  : const Color(0xFFE8E0D8),
            ),
          ),
          child: Row(
            children: [
              if (visited) ...[
                const Icon(Icons.restaurant, size: 12, color: AppTheme.primaryDark),
                const SizedBox(width: 4),
              ],
              Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? Colors.white : AppTheme.textDark,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 记录详情（完整信息 + 照片 + 编辑/删除）
class _RecordDetailPage extends StatefulWidget {
  final DiningRecord record;
  const _RecordDetailPage({required this.record});

  @override
  State<_RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<_RecordDetailPage> {
  late DiningRecord _record = widget.record;
  bool _deleting = false;

  Future<void> _refresh() async {
    final records = await FoodmapApi.fetchRecords();
    if (!mounted) return;
    for (final found in records) {
      if (found.id == widget.record.id) {
        setState(() => _record = found);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _record;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.restaurant),
        actions: [
          IconButton(
            onPressed: _deleting ? null : _delete,
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: '删除记录',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(r.date,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('★ ${r.rating}',
                            style: const TextStyle(
                                fontSize: 20, color: Colors.orange, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('${r.district}'
                        '${r.mood.isNotEmpty ? ' · ${r.mood}' : ''}'
                        '${r.perCapita != null ? ' · 人均 ¥${r.perCapita}' : ''}',
                        style: const TextStyle(color: AppTheme.textLight, fontSize: 13)),
                    if (r.comment.isNotEmpty) ...[
                      const Divider(height: 24),
                      Text(r.comment, style: const TextStyle(fontSize: 15, height: 1.6)),
                    ],
                  ],
                ),
              ),
            ),
            if (r.photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('照片（${r.photos.length}）',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: r.photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _PhotoView(path: r.photos[i].url),
                ),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecordFormPage(record: _record),
                  ),
                );
                _refresh();
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('编辑记录'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('删除后不可恢复'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _deleting = true);
    try {
      await FoodmapApi.deleteRecord(_record.id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

/// 用餐照片：后端返回相对路径，这里异步拼接完整地址后展示。
class _PhotoView extends StatelessWidget {
  final String path;
  const _PhotoView({required this.path});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: FoodmapApi.photoUrl(path),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) {
          return Container(
            width: 110,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EAE4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.image_outlined, color: AppTheme.textLight),
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            width: 110,
            height: 110,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 110,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EAE4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.broken_image, color: AppTheme.textLight),
              ),
            ),
          ),
        );
      },
    );
  }
}
