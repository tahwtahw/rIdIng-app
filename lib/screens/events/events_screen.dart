import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../config.dart';
import '../../services/user_service.dart';
import '../../utils/photo_actions.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<dynamic> _outings = [];
  bool _loading = true;
  String _username = '匿名';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadUser();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final name = await UserService.getUsername();
    if (mounted) setState(() => _username = name ?? '匿名');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await http.get(Uri.parse('${Config.baseUrl}/outings'));
      final list = List<dynamic>.from(jsonDecode(r.body));
      // Sort by date ascending
      list.sort((a, b) =>
          (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
      setState(() {
        _outings = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('錯誤：$e');
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteOuting(String id) async {
    try {
      final resp = await http.delete(
          Uri.parse('${Config.baseUrl}/outings/$id'));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('行程已刪除')));
        }
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('刪除失敗：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('活動'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: TabBar(controller: _tab, tabs: const [
          Tab(icon: Icon(Icons.calendar_month), text: '活動歷'),
          Tab(icon: Icon(Icons.group_add), text: '揪團出遊'),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [
              _buildCalendar(),
              _buildOutings(),
            ]),
      floatingActionButton: ListenableBuilder(
        listenable: _tab,
        builder: (context, _) => _tab.index == 1
            ? FloatingActionButton.extended(
                onPressed: () => _showCreateOuting(context),
                icon: const Icon(Icons.add),
                label: const Text('新增'),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  // ── 活動歷：所有公開行程依日期分組顯示 ────────────────────────────
  Widget _buildCalendar() {
    if (_outings.isEmpty) {
      return const Center(
        child: Text('目前沒有任何公開行程', style: TextStyle(color: Colors.grey)),
      );
    }

    // Group by year-month
    final Map<String, List<dynamic>> grouped = {};
    for (final o in _outings) {
      final date = (o['date'] ?? '').toString();
      final monthKey = date.length >= 7 ? date.substring(0, 7) : '未知';
      grouped.putIfAbsent(monthKey, () => []).add(o);
    }
    final months = grouped.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        itemCount: months.length,
        itemBuilder: (_, mi) {
          final month = months[mi];
          final items = grouped[month]!;
          final parts = month.split('-');
          final label = parts.length == 2
              ? '${parts[0]} 年 ${int.tryParse(parts[1]) ?? parts[1]} 月'
              : month;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              ...items.map((o) {
                final creator = (o['creator'] ?? '').toString();
                final isMine = creator == _username || creator.isEmpty;
                return _OutingCard(
                  outing: o,
                  isMine: isMine,
                  onDelete: () => _confirmDelete(o),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  // ── 揪團出遊：自己建立的行程可刪除 ──────────────────────────────────
  Widget _buildOutings() {
    if (_outings.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.group_off, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          const Text('尚無行程', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _showCreateOuting(context),
            icon: const Icon(Icons.add),
            label: const Text('建立行程'),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        itemCount: _outings.length,
        itemBuilder: (_, i) {
          final o = _outings[i];
          final creator = (o['creator'] ?? '').toString();
          // 顯示刪除：自己的行程，或舊資料沒有 creator 欄位
          final isMine = creator == _username || creator.isEmpty;
          return _OutingCard(
            outing: o,
            isMine: isMine,
            onDelete: () => _confirmDelete(o),
          );
        },
      ),
    );
  }

  void _confirmDelete(Map outing) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除行程'),
        content: Text('確定要刪除「${outing['title'] ?? ''}」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _deleteOuting(outing['id'].toString());
            },
            child: const Text('刪除'),
          ),
        ],
      ),
    );
  }

  void _showCreateOuting(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreateOutingSheet(
        creator: _username,
        onCreated: _load,
      ),
    );
  }
}

// ── 行程卡片 ────────────────────────────────────────────────────────
class _OutingCard extends StatelessWidget {
  final Map outing;
  final bool isMine;
  final VoidCallback onDelete;

  const _OutingCard({required this.outing, required this.isMine, required this.onDelete});

  List<String> _urls(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final o = outing;
    final int joined = (o['joined'] ?? 0) is int ? o['joined'] : int.tryParse('${o['joined']}') ?? 0;
    final int capacity = (o['capacity'] ?? 1) is int ? o['capacity'] : int.tryParse('${o['capacity']}') ?? 1;

    final photosLoc  = _urls(o['photos_location']);
    final photosDest = _urls(o['photos_destination']);
    final photosAcc  = _urls(o['photos_accommodation']);
    final hasPhotos  = photosLoc.isNotEmpty || photosDest.isNotEmpty || photosAcc.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(o['title'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            Chip(label: Text(o['type'] ?? '', style: const TextStyle(fontSize: 12)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            if (isMine)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                tooltip: '刪除行程',
                onPressed: onDelete,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
          ]),
          const SizedBox(height: 6),
          Text('📅 ${o['date'] ?? ''}   📍 ${o['location'] ?? ''}'),
          if ((o['destination'] ?? '').isNotEmpty) Text('🏁 ${o['destination']}'),
          if ((o['accommodation'] ?? '').isNotEmpty) Text('🏠 ${o['accommodation']}'),
          if ((o['creator'] ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('👤 ${o['creator']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
          // 照片列
          if (hasPhotos) ...[
            const SizedBox(height: 10),
            _PhotoRow(label: '集合地點', urls: photosLoc),
            _PhotoRow(label: '目的地',   urls: photosDest),
            _PhotoRow(label: '住宿',     urls: photosAcc),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: capacity > 0 ? joined / capacity : 0, minHeight: 6),
          ),
          const SizedBox(height: 4),
          Text('已報名 $joined / $capacity 人', style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  final String label;
  final List<String> urls;
  const _PhotoRow({required this.label, required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => showPhotoActions(context, url: urls[i]),
              child: Container(
                width: 72,
                height: 72,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.grey.shade200,
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(
                  fullImageUrl(urls[i]),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined, color: Colors.grey),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── 新增揪團 BottomSheet ──────────────────────────────────────────────
class _CreateOutingSheet extends StatefulWidget {
  final String creator;
  final VoidCallback onCreated;
  const _CreateOutingSheet({required this.creator, required this.onCreated});

  @override
  State<_CreateOutingSheet> createState() => _CreateOutingSheetState();
}

class _CreateOutingSheetState extends State<_CreateOutingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title        = TextEditingController();
  final _location     = TextEditingController();
  final _destination  = TextEditingController();
  final _accommodation = TextEditingController();
  final _capacity     = TextEditingController(text: '10');
  String _type = '個人';
  DateTime? _date;
  bool _saving = false;

  // 各類照片 URL 列表（先上傳取得 URL 再存入行程）
  final List<String> _photosLocation     = [];
  final List<String> _photosDestination  = [];
  final List<String> _photosAccommodation = [];

  @override
  void dispose() {
    _title.dispose(); _location.dispose();
    _destination.dispose(); _accommodation.dispose(); _capacity.dispose();
    super.dispose();
  }

  // 選照片 → 上傳 → 取得 URL
  Future<void> _pickPhoto(List<String> target) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    try {
      final bytes = await picked.readAsBytes();
      final req = http.MultipartRequest('POST', Uri.parse('${Config.baseUrl}/upload'));
      req.files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: picked.name.isNotEmpty ? picked.name : 'photo.jpg'));
      final resp = await req.send();
      final body = jsonDecode(await resp.stream.bytesToString());
      if (resp.statusCode == 200 && body['url'] != null) {
        setState(() => target.add(body['url'] as String));
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上傳失敗：$e')));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請選擇日期')));
      return;
    }
    setState(() => _saving = true);
    try {
      await http.post(
        Uri.parse('${Config.baseUrl}/outings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': _title.text,
          'type': _type,
          'date': '${_date!.year}-${_date!.month.toString().padLeft(2,'0')}-${_date!.day.toString().padLeft(2,'0')}',
          'location': _location.text,
          'destination': _destination.text,
          'accommodation': _accommodation.text,
          'capacity': int.tryParse(_capacity.text) ?? 10,
          'joined': 0,
          'creator': widget.creator,
          'photos_location': _photosLocation,
          'photos_destination': _photosDestination,
          'photos_accommodation': _photosAccommodation,
        }),
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('行程已建立！')));
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('建立失敗：$e')));
      }
    }
  }

  Widget _photoSection(String label, List<String> photos, VoidCallback onAdd) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const Spacer(),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_photo_alternate, size: 18),
          label: const Text('新增', style: TextStyle(fontSize: 12)),
        ),
      ]),
      if (photos.isNotEmpty)
        SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            itemBuilder: (_, i) => Stack(children: [
              Container(
                width: 72, height: 72,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.grey.shade200),
                clipBehavior: Clip.antiAlias,
                child: Image.network(fullImageUrl(photos[i]), fit: BoxFit.cover),
              ),
              Positioned(
                top: 0, right: 0,
                child: GestureDetector(
                  onTap: () => setState(() => photos.removeAt(i)),
                  child: Container(
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 8),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('新增揪團',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: '標題 *', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? '請輸入標題' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: '類型', border: OutlineInputBorder()),
              items: ['個人', '小隊(3人)', '大隊(多人)']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _date = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: '日期 *', border: OutlineInputBorder()),
                child: Text(
                  _date == null ? '點擊選擇日期' : '${_date!.year}/${_date!.month}/${_date!.day}',
                  style: TextStyle(color: _date == null ? Colors.grey : Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _location,
                decoration: const InputDecoration(labelText: '集合地點', border: OutlineInputBorder())),
            const SizedBox(height: 6),
            _photoSection('集合地點照片', _photosLocation, () => _pickPhoto(_photosLocation)),
            TextFormField(controller: _destination,
                decoration: const InputDecoration(labelText: '目的地', border: OutlineInputBorder())),
            const SizedBox(height: 6),
            _photoSection('目的地照片', _photosDestination, () => _pickPhoto(_photosDestination)),
            TextFormField(controller: _accommodation,
                decoration: const InputDecoration(labelText: '住宿資訊', border: OutlineInputBorder())),
            const SizedBox(height: 6),
            _photoSection('住宿照片', _photosAccommodation, () => _pickPhoto(_photosAccommodation)),
            TextFormField(
              controller: _capacity,
              decoration: const InputDecoration(labelText: '人數上限', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('建立行程'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
