import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../api_client.dart';
import 'package:image_picker/image_picker.dart';
import '../../config.dart';
import '../../services/auth_service.dart';
import '../../services/language_service.dart';
import '../../services/user_service.dart';
import '../../utils/photo_actions.dart';
import '../../widgets/login_dialog.dart';
import 'calendar_screen.dart';

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
    await _loadUser(); // 暱稱可能在個人頁更新過，重新讀取
    setState(() => _loading = true);
    try {
      final r = await ApiClient.get(Uri.parse('${Config.baseUrl}/outings'));
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
      final resp = await ApiClient.delete(
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
        title: Text(LanguageService.t('nav_events')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: TabBar(controller: _tab, tabs: [
          Tab(
              icon: const Icon(Icons.calendar_month),
              text: LanguageService.t('tab_calendar')),
          Tab(
              icon: const Icon(Icons.group_add),
              text: LanguageService.t('tab_outings')),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [
              const CalendarScreen(),
              _buildOutings(),
            ]),
      floatingActionButton: ListenableBuilder(
        listenable: _tab,
        builder: (context, _) => _tab.index == 1
            ? FloatingActionButton.extended(
                onPressed: () => _showCreateOuting(context),
                icon: const Icon(Icons.add),
                label: Text(LanguageService.t('add')),
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
                  key: ValueKey('outing_g_${o['id']}'),
                  outing: o,
                  isMine: isMine,
                  username: _username,
                  onDelete: () => _confirmDelete(o),
                  onChanged: _load,
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
            label: Text(LanguageService.t('create_outing')),
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
            key: ValueKey('outing_${o['id']}'),
            outing: o,
            isMine: isMine,
            username: _username,
            onDelete: () => _confirmDelete(o),
            onChanged: _load,
          );
        },
      ),
    );
  }

  void _confirmDelete(Map outing) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(LanguageService.t('del_outing')),
        content: Text(LanguageService.tp(
            'del_confirm', {'x': '${outing['title'] ?? ''}'})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LanguageService.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _deleteOuting(outing['id'].toString());
            },
            child: Text(LanguageService.t('delete')),
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

/// 行程團體類型顯示名稱（資料庫存中文原值，顯示依語言翻譯）
String _outingTypeLabel(String v) {
  switch (v) {
    case '個人':
      return LanguageService.t('type_solo');
    case '小隊(3人)':
      return LanguageService.t('type_small');
    case '大隊(多人)':
      return LanguageService.t('type_large');
    default:
      return v;
  }
}

// ── 行程卡片 ────────────────────────────────────────────────────────
class _OutingCard extends StatefulWidget {
  final Map outing;
  final bool isMine;
  final String username;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _OutingCard({
    super.key,
    required this.outing,
    required this.isMine,
    required this.username,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<_OutingCard> createState() => _OutingCardState();
}

class _OutingCardState extends State<_OutingCard> {
  List<String> _members = [];
  bool _busy = false;
  String _myName = '';

  Map get outing => widget.outing;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
    _loadMyName();
  }

  /// 每次都重新讀取暱稱（暱稱可能剛在個人頁設定，避免拿到舊值）
  Future<void> _loadMyName() async {
    final n = (await UserService.getUsername())?.trim() ?? '';
    if (mounted && n.isNotEmpty) setState(() => _myName = n);
  }

  String get _effectiveName =>
      _myName.isNotEmpty ? _myName : widget.username;

  Future<void> _fetchMembers() async {
    try {
      final r = await ApiClient.get(Uri.parse(
          '${Config.baseUrl}/outings/${outing['id']}/members'));
      if (!mounted || r.statusCode != 200) return;
      setState(() => _members = (jsonDecode(r.body) as List)
          .map((e) => '${e['name']}')
          .toList());
    } catch (_) {}
  }

  bool get _isMember =>
      _effectiveName.isNotEmpty &&
      _effectiveName != '匿名' &&
      _members.contains(_effectiveName);

  Future<void> _join() async {
    await _loadMyName(); // 取得最新暱稱
    final name = _effectiveName;
    if (name.isEmpty || name == '匿名') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(LanguageService.t('msg_set_nickname'))));
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await ApiClient.post(
        Uri.parse('${Config.baseUrl}/outings/${outing['id']}/join'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      final body = jsonDecode(r.body);
      if (r.statusCode != 200) {
        throw body['error'] ?? LanguageService.t('msg_join_fail');
      }
      // 自動加入行程專屬聊天室
      final room = body['room'];
      if (room != null && room['id'] != null) {
        await UserService.joinRoom('${room['id']}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.tp(
              'msg_joined', {'x': '${outing['title']}'}))));
      await _fetchMembers();
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    try {
      await ApiClient.post(
        Uri.parse('${Config.baseUrl}/outings/${outing['id']}/leave'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': _effectiveName}),
      );
      if (!mounted) return;
      await _fetchMembers();
      widget.onChanged();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _urls(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    // D1 將陣列以 JSON 字串儲存
    if (raw is String && raw.isNotEmpty) {
      try {
        final l = jsonDecode(raw);
        if (l is List) {
          return l.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
        }
      } catch (_) {}
    }
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
            Chip(
                label: Text(_outingTypeLabel('${o['type'] ?? ''}'),
                    style: const TextStyle(fontSize: 12)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            if (widget.isMine)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                tooltip: '刪除行程',
                onPressed: widget.onDelete,
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
          Text(
              LanguageService.tp(
                  'reg_count', {'a': '$joined', 'b': '$capacity'}),
              style: const TextStyle(fontSize: 12)),

          // 加入 / 退出行程
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _isMember
                ? OutlinedButton.icon(
                    icon: const Icon(Icons.exit_to_app, size: 18),
                    label: Text(LanguageService.t('leave_outing')),
                    onPressed: _busy ? null : _leave,
                  )
                : FilledButton.tonalIcon(
                    icon: const Icon(Icons.group_add, size: 18),
                    label: Text(_busy
                        ? '…'
                        : LanguageService.t('join_outing')),
                    onPressed: _busy ? null : _join,
                  ),
          ),

          // 參加成員名單：僅已加入的人可見
          if (_isMember && _members.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(LanguageService.t('members'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _members
                  .map((n) => Chip(
                        avatar: const Icon(Icons.person, size: 14),
                        label:
                            Text(n, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
          ] else if (!_isMember) ...[
            const SizedBox(height: 4),
            Text('加入後可查看參加成員，並自動加入行程專屬聊天室',
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ]),
      ),
    );
  }
}

// ── 全螢幕照片檢視器（縮放 + 翻頁） ────────────────────
class _PhotoViewer extends StatefulWidget {
  final List<String> urls;
  final int initial;
  const _PhotoViewer({required this.urls, required this.initial});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _ctrl = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.urls.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            tooltip: '更多',
            onPressed: () =>
                showPhotoActions(context, url: widget.urls[_index]),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.network(
              fullImageUrl(widget.urls[i]),
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white54)),
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
                  color: Colors.white54, size: 64),
            ),
          ),
        ),
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
              // 點擊縮圖 → 全螢幕檢視（可縮放、左右滑動）
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _PhotoViewer(urls: urls, initial: i),
                ),
              ),
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
    if (!AuthService.isLoggedIn) {
      final ok = await LoginDialog.show(context);
      if (!ok || !mounted) return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    try {
      final bytes = await picked.readAsBytes();
      final req = http.MultipartRequest('POST', Uri.parse('${Config.baseUrl}/upload'));
      req.headers.addAll(AuthService.authHeader);
      req.files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: picked.name.isNotEmpty ? picked.name : 'photo.jpg'));
      final resp = await req.send();
      final body = jsonDecode(await resp.stream.bytesToString());
      if (resp.statusCode == 200 && body['url'] != null) {
        setState(() => target.add(body['url'] as String));
      } else {
        // 顯示後端錯誤（例如未登入 401），不再默默失敗
        final msg =
            (body is Map ? body['error'] : null) ?? 'HTTP ${resp.statusCode}';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('${LanguageService.t('msg_upload_fail')}: $msg')));
        }
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${LanguageService.t('msg_upload_fail')}: $e')));
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('msg_pick_date'))));
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await ApiClient.post(
        Uri.parse('${Config.baseUrl}/outings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': _title.text,
          'type': _type,
          'date': '${_date!.year}-${_date!.month.toString().padLeft(2, "0")}-${_date!.day.toString().padLeft(2, "0")}',
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
      // 創建者自動加入行程 + 行程專屬聊天室
      try {
        final created = jsonDecode(res.body);
        final outingId = created['id'];
        if (outingId != null &&
            widget.creator.isNotEmpty &&
            widget.creator != '匿名') {
          final jr = await ApiClient.post(
            Uri.parse('${Config.baseUrl}/outings/$outingId/join'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'name': widget.creator}),
          );
          final jb = jsonDecode(jr.body);
          final room = jb['room'];
          if (jr.statusCode == 200 && room != null && room['id'] != null) {
            await UserService.joinRoom('${room['id']}');
          }
        }
      } catch (_) {}
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(LanguageService.t('msg_outing_created'))));
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${LanguageService.t('msg_create_fail')}: $e')));
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
          label: Text(LanguageService.t('add'),
              style: const TextStyle(fontSize: 12)),
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
              Text(LanguageService.t('create_outing'),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              decoration: InputDecoration(
                  labelText: '${LanguageService.t('f_title')} *',
                  border: const OutlineInputBorder()),
              validator: (v) =>
                  v!.isEmpty ? LanguageService.t('msg_need_title') : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: InputDecoration(
                  labelText: LanguageService.t('f_type'),
                  border: const OutlineInputBorder()),
              // value 維持中文存入後端，顯示文字依語言翻譯
              items: [
                DropdownMenuItem(
                    value: '個人',
                    child: Text(LanguageService.t('type_solo'))),
                DropdownMenuItem(
                    value: '小隊(3人)',
                    child: Text(LanguageService.t('type_small'))),
                DropdownMenuItem(
                    value: '大隊(多人)',
                    child: Text(LanguageService.t('type_large'))),
              ],
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
                decoration: InputDecoration(
                    labelText: '${LanguageService.t('f_date')} *',
                    border: const OutlineInputBorder()),
                child: Text(
                  _date == null
                      ? LanguageService.t('pick_date_tap')
                      : '${_date!.year}/${_date!.month}/${_date!.day}',
                  style: TextStyle(color: _date == null ? Colors.grey : Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _location,
                decoration: InputDecoration(
                    labelText: LanguageService.t('f_meet'),
                    border: const OutlineInputBorder())),
            const SizedBox(height: 6),
            _photoSection(
                '${LanguageService.t('f_meet')}・${LanguageService.t('photo')}',
                _photosLocation,
                () => _pickPhoto(_photosLocation)),
            TextFormField(controller: _destination,
                decoration: InputDecoration(
                    labelText: LanguageService.t('f_dest'),
                    border: const OutlineInputBorder())),
            const SizedBox(height: 6),
            _photoSection(
                '${LanguageService.t('f_dest')}・${LanguageService.t('photo')}',
                _photosDestination,
                () => _pickPhoto(_photosDestination)),
            TextFormField(controller: _accommodation,
                decoration: InputDecoration(
                    labelText: LanguageService.t('f_accom'),
                    border: const OutlineInputBorder())),
            const SizedBox(height: 6),
            _photoSection(
                '${LanguageService.t('f_accom')}・${LanguageService.t('photo')}',
                _photosAccommodation,
                () => _pickPhoto(_photosAccommodation)),
            TextFormField(
              controller: _capacity,
              decoration: InputDecoration(
                  labelText: LanguageService.t('f_capacity'),
                  border: const OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(LanguageService.t('create_outing')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
