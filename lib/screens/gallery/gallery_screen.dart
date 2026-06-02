import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config.dart';
import '../../services/user_service.dart';
import 'album_detail_screen.dart';
import '../community/room_photos_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<dynamic> _albums = [];
  List<dynamic> _visibleAlbums = [];
  List<dynamic> _rooms = [];
  String _username = '';
  List<String> _joinedRoomIds = ['public'];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final name = await UserService.getUsername() ?? '';
      final joinedIds = await UserService.getJoinedRooms();

      final results = await Future.wait([
        http.get(Uri.parse('${Config.baseUrl}/albums')),
        http.get(Uri.parse('${Config.baseUrl}/rooms')),
      ]);

      final allAlbums = jsonDecode(results[0].body) as List;
      final allRooms = jsonDecode(results[1].body) as List;

      // Filter by visibility
      final visible = allAlbums.where((a) {
        final v = a['visibility'] ?? 'public';
        if (v == 'public') return true;
        if (v == 'private') return a['creator'] == name;
        if (v == 'room') return joinedIds.contains(a['room_id']);
        return true;
      }).toList();

      setState(() {
        _albums = allAlbums;
        _visibleAlbums = visible;
        _rooms = allRooms.where((r) => joinedIds.contains(r['id'])).toList();
        _username = name;
        _joinedRoomIds = joinedIds;
        _loading = false;
      });
    } catch (e) {
      debugPrint('錯誤：$e');
      setState(() { _error = '錯誤：$e'; _loading = false; });
    }
  }

  Future<void> _deleteAlbum(Map album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除相簿'),
        content: Text('確定要刪除「${album['title'] ?? ''}」及其所有照片嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await http.delete(Uri.parse('${Config.baseUrl}/albums/${album['id']}'));
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('相簿已刪除')));
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刪除失敗：$e')));
    }
  }

  void _openAlbum(Map album) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
    ).then((_) => _load());
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (_) => _CreateAlbumDialog(
        rooms: _rooms.where((r) => r['id'] != 'public').toList(),
        onCreate: (title, date, location, visibility, roomId) =>
            _createAlbum(
              title: title,
              date: date,
              location: location,
              visibility: visibility,
              roomId: roomId,
            ),
      ),
    );
  }

  Future<void> _createAlbum({
    required String title,
    required String date,
    required String location,
    required String visibility,
    String? roomId,
  }) async {
    try {
      await http.post(
        Uri.parse('${Config.baseUrl}/albums'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'date': date,
          'location': location,
          'description': '',
          'visibility': visibility,
          'creator': _username,
          'room_id': roomId ?? '',
        }),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('相簿已建立')),
        );
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('建立失敗：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('相簿'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _load, child: const Text('重試')),
                  ]),
                )
              : RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(
                        slivers: [
                          // 公開聊天室相簿（固定置頂）
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                              child: _PublicRoomAlbumCard(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      appBar: AppBar(title: const Text('公開聊天室相簿')),
                                      body: const RoomPhotosScreen(
                                          roomId: 'public', isPublic: true),
                                    ),
                                  ),
                                ).then((_) => _load()),
                              ),
                            ),
                          ),
                          // 個人 / 聊天室相簿
                          if (_visibleAlbums.isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
                              sliver: SliverGrid(
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) {
                                    final a = _visibleAlbums[i];
                                    return _AlbumCard(
                                      album: a,
                                      username: _username,
                                      onTap: () => _openAlbum(a),
                                      onDelete: () => _deleteAlbum(a),
                                    );
                                  },
                                  childCount: _visibleAlbums.length,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio: 0.85,
                                ),
                              ),
                            )
                          else
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(children: [
                                  const Icon(Icons.photo_album,
                                      size: 48, color: Colors.grey),
                                  const SizedBox(height: 12),
                                  const Text('還沒有個人相簿',
                                      style: TextStyle(color: Colors.grey)),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _showCreateDialog,
                                    icon: const Icon(Icons.add),
                                    label: const Text('建立相簿'),
                                  ),
                                ]),
                              ),
                            ),
                        ],
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.create_new_folder),
        label: const Text('新增相簿'),
      ),
    );
  }
}

// ── 可見性選擇器 ─────────────────────────────────────
class _VisibilitySelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _VisibilitySelector(
      {required this.value, required this.onChanged});

  Widget _option(BuildContext context, String val, IconData icon, String label) {
    final theme = Theme.of(context);
    final selected = value == val;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(val),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: selected
                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 22,
                    color: selected ? theme.colorScheme.primary : Colors.grey),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    color: selected
                        ? theme.colorScheme.primary
                        : Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _option(context, 'private', Icons.lock, '僅個人可見'),
      _option(context, 'room', Icons.people, '僅限聊天室'),
      _option(context, 'public', Icons.public, '公開可見'),
    ]);
  }
}

// ── 相簿卡片 ─────────────────────────────────────────
class _AlbumCard extends StatelessWidget {
  final Map album;
  final String username;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _AlbumCard({required this.album, required this.username, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibility = album['visibility'] ?? 'public';

    final IconData visIcon;
    final Color visColor;
    if (visibility == 'private') {
      visIcon = Icons.lock;
      visColor = Colors.orange;
    } else if (visibility == 'room') {
      visIcon = Icons.people;
      visColor = Colors.purple;
    } else {
      visIcon = Icons.public;
      visColor = Colors.green;
    }

    final isMine = (album['creator'] ?? '') == username;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: isMine ? onDelete : null,
        child: Column(children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.secondaryContainer,
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.photo_library,
                    size: 52,
                    color: theme.colorScheme.onPrimaryContainer
                        .withOpacity(0.4),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(visIcon, size: 16, color: visColor),
                  ),
                ),
                if (isMine)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.delete_outline,
                          size: 14, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album['title'] ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if ((album['date'] ?? '').isNotEmpty)
                  Text(album['date'],
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                if ((album['location'] ?? '').isNotEmpty)
                  Text(
                    album['location'],
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── 公開聊天室相簿卡（橫幅式） ────────────────────────
class _PublicRoomAlbumCard extends StatelessWidget {
  final VoidCallback onTap;
  const _PublicRoomAlbumCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primaryContainer,
              ],
            ),
          ),
          child: Row(children: [
            const Icon(Icons.public, color: Colors.white, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('公開聊天室相簿',
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                  Text('與公開聊天室即時同步',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}

// ── 新增相簿對話框（獨立 StatefulWidget 確保狀態正確更新） ────────────
class _CreateAlbumDialog extends StatefulWidget {
  final List<dynamic> rooms;
  final Future<void> Function(String title, String date, String location,
      String visibility, String? roomId) onCreate;

  const _CreateAlbumDialog({required this.rooms, required this.onCreate});

  @override
  State<_CreateAlbumDialog> createState() => _CreateAlbumDialogState();
}

class _CreateAlbumDialogState extends State<_CreateAlbumDialog> {
  final _titleCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  DateTime? _date;
  String _visibility = 'public';
  String? _roomId;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新增相簿'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
                labelText: '相簿名稱 *', border: OutlineInputBorder()),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _date = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: '日期', border: OutlineInputBorder()),
              child: Text(
                _date == null
                    ? '點擊選擇日期'
                    : '${_date!.year}/${_date!.month.toString().padLeft(2,'0')}/${_date!.day.toString().padLeft(2,'0')}',
                style: TextStyle(color: _date == null ? Colors.grey : Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationCtrl,
            decoration: const InputDecoration(
                labelText: '地點', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('可見範圍', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ),
          const SizedBox(height: 6),
          _VisibilitySelector(
            value: _visibility,
            onChanged: (v) => setState(() {
              _visibility = v;
              if (v != 'room') _roomId = null;
            }),
          ),
          if (_visibility == 'room') ...[
            const SizedBox(height: 12),
            if (widget.rooms.isEmpty)
              const Text('尚未加入任何私人聊天室',
                  style: TextStyle(color: Colors.red, fontSize: 13))
            else
              DropdownButtonFormField<String>(
                value: _roomId,
                decoration: const InputDecoration(
                    labelText: '選擇聊天室', border: OutlineInputBorder()),
                hint: const Text('選擇私人聊天室'),
                items: widget.rooms
                    .map<DropdownMenuItem<String>>((r) => DropdownMenuItem(
                          value: r['id'] as String,
                          child: Text(r['name'] ?? ''),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _roomId = v),
              ),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final title = _titleCtrl.text.trim();
            if (title.isEmpty) return;
            if (_visibility == 'room' && _roomId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('請選擇聊天室')));
              return;
            }
            Navigator.pop(context);
            await widget.onCreate(
              title,
              _date == null
                  ? ''
                  : '${_date!.year}-${_date!.month.toString().padLeft(2,'0')}-${_date!.day.toString().padLeft(2,'0')}',
              _locationCtrl.text.trim(),
              _visibility,
              _roomId,
            );
          },
          child: const Text('建立'),
        ),
      ],
    );
  }
}
