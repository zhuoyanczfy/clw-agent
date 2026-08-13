import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/pet.dart';
import '../services/foodmap_api.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets/cute_widgets.dart';
import 'pet_event_form_page.dart';
import 'pet_form_page.dart';

/// 猫咪名片：宠物档案主页（生日 / 疫苗驱虫 / 体重 / 照片相册 / 大事记）。
class PetPage extends StatefulWidget {
  const PetPage({super.key});

  @override
  State<PetPage> createState() => _PetPageState();
}

class _PetPageState extends State<PetPage> {
  Pet? _pet;
  List<PetPhoto> _photos = [];
  List<PetEvent> _events = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pets = await FoodmapApi.fetchPets();
      if (pets.isEmpty) {
        if (!mounted) return;
        setState(() {
          _pet = null;
          _photos = [];
          _events = [];
          _loading = false;
        });
        return;
      }
      final pet = pets.first;
      final results = await Future.wait([
        FoodmapApi.fetchPetPhotos(pet.id),
        FoodmapApi.fetchPetEvents(pet.id),
      ]);
      if (!mounted) return;
      setState(() {
        _pet = pet;
        _photos = results[0] as List<PetPhoto>;
        _events = results[1] as List<PetEvent>;
        _loading = false;
      });
      // 数据变化后重新调度疫苗/驱虫到期提醒
      unawaited(_reschedule());
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载失败：$e')));
    }
  }

  Future<void> _reschedule() async {
    try {
      await NotificationService.schedulePetReminders(_events);
    } catch (_) {
      // 通知调度失败不影响使用
    }
  }

  Future<void> _pickAndUploadPhotos() async {
    if (_uploading || _pet == null) return;
    final files = await ImagePicker().pickMultiImage(limit: 9);
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final paths = [for (final f in files) f.path];
      await FoodmapApi.uploadPetPhotos(_pet!.id, paths);
      final photos = await FoodmapApi.fetchPetPhotos(_pet!.id);
      if (!mounted) return;
      setState(() => _photos = photos);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已上传 ${paths.length} 张照片 🐾')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('上传失败：$e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deletePhoto(PetPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这张照片？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppTheme.primaryDark)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FoodmapApi.deletePetPhoto(photo.id);
      setState(() => _photos = _photos.where((p) => p.id != photo.id).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  Future<void> _deleteEvent(PetEvent event) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${event.title}」这条记录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppTheme.primaryDark)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FoodmapApi.deletePetEvent(event.id);
      setState(() => _events = _events.where((e) => e.id != event.id).toList());
      await _reschedule();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  void _openEventForm(String kind) {
    if (_pet == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PetEventFormPage(pet: _pet!, kind: kind),
      ),
    ).then((added) async {
      if (added == true) await _load();
    });
  }

  void _openEditForm() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PetFormPage(pet: _pet)),
    ).then((saved) async {
      if (saved == true) await _load();
    });
  }

  void _openCreateForm() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PetFormPage()),
    ).then((saved) async {
      if (saved == true) await _load();
    });
  }

  void _showPhoto(PetPhoto photo) async {
    final url = await FoodmapApi.photoUrl(photo.image);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Stack(
            children: [
              Center(
                child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '记一笔什么？',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              _addOption(ctx, '💉', '疫苗', '猫三联 / 狂犬，记得写下一次时间', PetEvent.kindVaccine),
              _addOption(ctx, '🐛', '驱虫', '体内 / 体外驱虫', PetEvent.kindDeworm),
              _addOption(ctx, '⚖️', '称体重', '记录成长曲线', PetEvent.kindWeight),
              _addOption(ctx, '📌', '其他', '绝育、体检、生日派对…', PetEvent.kindOther),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addOption(
    BuildContext ctx,
    String emoji,
    String title,
    String desc,
    String kind,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Text(emoji, style: const TextStyle(fontSize: 26)),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark),
      ),
      subtitle: Text(desc, style: const TextStyle(fontSize: 12, color: AppTheme.textLight)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textLight),
      onTap: () {
        Navigator.pop(ctx);
        _openEventForm(kind);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '猫咪名片',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_pet != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _openEditForm,
              tooltip: '编辑档案',
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _pet == null
          ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildDueCards(),
                  const SizedBox(height: 16),
                  _buildWeightCard(),
                  const SizedBox(height: 16),
                  _buildAlbum(),
                  const SizedBox(height: 16),
                  _buildTimeline(),
                ],
              ),
            ),
      floatingActionButton: _pet == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddSheet,
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('记一笔'),
            ),
    );
  }

  // ---- 空态：还没创建名片 ----
  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HeartBeat(
              maxScale: 1.08,
              child: const Text('🐱', style: TextStyle(fontSize: 72)),
            ),
            const SizedBox(height: 20),
            const Text(
              '还没有猫咪名片',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '创建一张专属名片，记录生日、疫苗、驱虫、体重和成长照片，重要的事一件都不忘～',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppTheme.textLight, height: 1.6),
            ),
            const SizedBox(height: 28),
            SquishyTap(
              borderRadius: BorderRadius.circular(30),
              onTap: _openCreateForm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  '创建猫咪名片 🐾',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 头部：头像 + 基本信息 ----
  Widget _buildHeader() {
    final pet = _pet!;
    final age = pet.ageText;
    final companion = pet.companionDays;
    return BouncyIn(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              _avatar(84),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (pet.breed.isNotEmpty) pet.breed,
                        if (pet.gender == 'male')
                          '弟弟'
                        else if (pet.gender == 'female')
                          '妹妹',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (age.isNotEmpty) _infoChip('🎂 $age'),
                        if (companion != null) _infoChip('💛 已相伴 $companion 天'),
                        if (pet.birthday.isNotEmpty)
                          _infoChip('📅 ${pet.birthday}'),
                        if (pet.adoptDate.isNotEmpty)
                          _infoChip('🏠 ${pet.adoptDate} 来家'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(double size) {
    return FutureBuilder<String>(
      future: _pet!.avatar.isEmpty
          ? Future.value('')
          : FoodmapApi.photoUrl(_pet!.avatar),
      builder: (context, snapshot) {
        final url = snapshot.data ?? '';
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFFE9E9),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: url.isEmpty
              ? const Center(child: Text('🐱', style: TextStyle(fontSize: 40)))
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) =>
                      const Center(child: Text('🐱', style: TextStyle(fontSize: 40))),
                ),
        );
      },
    );
  }

  Widget _infoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0E3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Color(0xFFB07850)),
      ),
    );
  }

  // ---- 疫苗 / 驱虫到期提醒 ----
  Widget _buildDueCards() {
    final vaccines =
        _events.where((e) => e.kind == PetEvent.kindVaccine).toList();
    final deworms =
        _events.where((e) => e.kind == PetEvent.kindDeworm).toList();
    final cards = <Widget>[
      if (vaccines.isNotEmpty) _dueCard('💉', '疫苗', vaccines.first, Colors.redAccent),
      if (deworms.isNotEmpty)
        _dueCard('🐛', '驱虫', deworms.first, const Color(0xFF8D6E63)),
    ];
    if (cards.isEmpty) {
      return Card(
        child: SquishyTap(
          onTap: () => _openEventForm(PetEvent.kindVaccine),
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Text('💉', style: TextStyle(fontSize: 26)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '还没有疫苗记录，点击记下第一次疫苗吧',
                    style: TextStyle(fontSize: 14, color: AppTheme.textLight),
                  ),
                ),
                Icon(Icons.chevron_right, color: AppTheme.textLight),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in cards) ...[c, const SizedBox(height: 12)],
      ],
    );
  }

  Widget _dueCard(String emoji, String label, PetEvent event, Color color) {
    final days = event.daysUntilDue;
    String statusText;
    Color statusColor;
    if (days == null) {
      statusText = '已记录 · 未设下次时间';
      statusColor = AppTheme.textLight;
    } else if (days < 0) {
      statusText = '已过期 ${-days} 天，该带猫咪去$label啦';
      statusColor = const Color(0xFFE53935);
    } else if (days == 0) {
      statusText = '今天到期！';
      statusColor = const Color(0xFFE53935);
    } else if (days <= 7) {
      statusText = '$days 天后到期，记得预约';
      statusColor = const Color(0xFFEF6C00);
    } else {
      statusText = '下次到期还有 $days 天';
      statusColor = const Color(0xFF43A047);
    }
    return BouncyIn(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$label · ${event.title}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '上次：${event.date}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (event.dueDate.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '到期\n${event.dueDate.substring(5)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textLight,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 体重卡片 ----
  Widget _buildWeightCard() {
    final weights =
        _events.where((e) => e.kind == PetEvent.kindWeight).toList();
    if (weights.isEmpty) {
      return Card(
        child: SquishyTap(
          onTap: () => _openEventForm(PetEvent.kindWeight),
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Text('⚖️', style: TextStyle(fontSize: 26)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '还没称过体重，定期称一称关注健康',
                    style: TextStyle(fontSize: 14, color: AppTheme.textLight),
                  ),
                ),
                Icon(Icons.chevron_right, color: AppTheme.textLight),
              ],
            ),
          ),
        ),
      );
    }
    final latest = weights.first;
    final prev = weights.length > 1 ? weights[1] : null;
    double? diff;
    if (prev != null && latest.weight != null && prev.weight != null) {
      diff = latest.weight! - prev.weight!;
    }
    return BouncyIn(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text('⚖️', style: TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '最近体重',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      latest.date,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${latest.weight?.toStringAsFixed(2) ?? '--'} kg',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  if (diff != null)
                    Text(
                      diff == 0
                          ? '与上次持平'
                          : diff > 0
                          ? '比上次 +${diff.toStringAsFixed(2)} kg'
                          : '比上次 ${diff.toStringAsFixed(2)} kg',
                      style: TextStyle(
                        fontSize: 12,
                        color: diff > 0 ? AppTheme.primaryDark : const Color(0xFF43A047),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 照片相册 ----
  Widget _buildAlbum() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            '成长相册',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
        ),
        SizedBox(
          height: 130,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _albumAddTile(),
              for (final p in _photos) ...[
                const SizedBox(width: 10),
                _albumTile(p),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _albumAddTile() {
    return SizedBox(
      width: 130,
      child: Card(
        child: SquishyTap(
          onTap: _uploading ? null : _pickAndUploadPhotos,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_uploading)
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.primary,
                  ),
                )
              else
                const Icon(
                  Icons.add_a_photo_outlined,
                  size: 30,
                  color: AppTheme.primary,
                ),
              const SizedBox(height: 8),
              Text(
                _uploading ? '上传中…' : '上传照片',
                style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _albumTile(PetPhoto photo) {
    return SizedBox(
      width: 130,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          onTap: () => _showPhoto(photo),
          onLongPress: () => _deletePhoto(photo),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<String>(
                future: FoodmapApi.photoUrl(photo.image),
                builder: (context, snapshot) {
                  final url = snapshot.data ?? '';
                  if (url.isEmpty) return const SizedBox.shrink();
                  return CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      color: const Color(0xFFFFE9E9),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: const Color(0xFFFFE9E9),
                      child: const Center(child: Text('🐾', style: TextStyle(fontSize: 30))),
                    ),
                  );
                },
              ),
              if (photo.caption.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: Colors.black.withValues(alpha: 0.4),
                    child: Text(
                      photo.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 大事记时间线 ----
  Widget _buildTimeline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            '大事记',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
        ),
        if (_events.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '还没有记录。点右下角「记一笔」，把疫苗、驱虫、体重都记下来～',
                style: TextStyle(fontSize: 13, color: AppTheme.textLight, height: 1.5),
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < _events.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  _timelineTile(_events[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _timelineTile(PetEvent e) {
    final (emoji, color) = switch (e.kind) {
      PetEvent.kindVaccine => ('💉', const Color(0xFFE53935)),
      PetEvent.kindDeworm => ('🐛', const Color(0xFF8D6E63)),
      PetEvent.kindWeight => ('⚖️', const Color(0xFF43A047)),
      _ => ('📌', AppTheme.accent),
    };
    final subtitle = [
      e.date,
      if (e.kind == PetEvent.kindWeight && e.weight != null)
        '${e.weight!.toStringAsFixed(2)} kg',
      if (e.dueDate.isNotEmpty) '下次 ${e.dueDate}',
      if (e.note.isNotEmpty) e.note,
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 17))),
      ),
      title: Text(
        e.title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textDark,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
      ),
      onLongPress: () => _deleteEvent(e),
    );
  }
}
