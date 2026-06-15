import 'dart:convert';
import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../config.dart';
import '../../services/auth_service.dart';
import '../../services/language_service.dart';
import '../../services/user_service.dart';
import '../../widgets/login_dialog.dart';
import 'album_detail_screen.dart';
import '../community/room_photos_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});
  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<dynamic> _visibleAlbums = [];
  List<dynamic> _rooms = [];
  String _username = '';
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
        ApiClient.get(Uri.parse('${Config.baseUrl}/albums')),
        ApiClient.get(Uri.parse('${Config.baseUrl}/rooms')),
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
        _visibleAlbums = visible;
        _rooms = allRooms.where((r) => joinedIds.contains(r['id'])).toList();
        _username = name;
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
        title: Text(LanguageService.t('delete')),
        content: Text(LanguageService.tp(
            'del_confirm', {'x': '${album['title'] ?? ''}'})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(LanguageService.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(LanguageService.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.delete(Uri.parse('${Config.baseUrl}/albums/${album['id']}'));
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('album_deleted'))));
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${LanguageService.t('delete_fail')}：$e')));
    }
  }

  void _openAlbum(Map album) {
    final visibility = album['visibility'] ?? 'public';
    final roomId = (album['room_id'] ?? '').toString();
    // 僅限聊天室的相簿：直接開啟該聊天室的照片庫，
    // 與聊天室內「相簿」分頁完全同步（同一份內容）
    if (visibility == 'room' && roomId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(album['title'] ?? LanguageService.t('room_album'))),
            body: RoomPhotosScreen(roomId: roomId, isPublic: false),
          ),
        ),
      ).then((_) => _load());
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
    ).then((_) => _load());
  }

  void _showCreateDialog() async {
    if (!AuthService.isLoggedIn) {
      final ok = await LoginDialog.show(context);
      if (!ok || !mounted) return;
    }
    // 先重新載入已加入的聊天室，
    // 避免在社群頁加入聊天室後，這裡仍是啟動時的舊資料而無法選擇
    await _load();
    if (!mounted) return;
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
      await ApiClient.post(
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
          SnackBar(content: Text(LanguageService.t('album_created'))),
        );
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${LanguageService.t('msg_create_fail')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('nav_gallery')),
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
                    FilledButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
                  ]),
                )
              : RefreshIndicator(
                      onRefresh: _load,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
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
                                      appBar: AppBar(
                                          title: Text(LanguageService.t(
                                              'public_room_album'))),
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
                                    SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 220,
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
                                  Text(
                                      LanguageService.t(
                                          'no_personal_albums'),
                                      style: const TextStyle(
                                          color: Colors.grey)),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _showCreateDialog,
                                    icon: const Icon(Icons.add),
                                    label: Text(LanguageService.t('new_album')),
                                  ),
                                ]),
                              ),
                            ),
                        ],
                      ),
                        ),
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.create_new_folder),
        label: Text(LanguageService.t('new_album')),
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
      _option(context, 'private', Icons.lock, LanguageService.t('vis_private')),
      _option(context, 'room', Icons.people, LanguageService.t('vis_room')),
      _option(context, 'public', Icons.public, LanguageService.t('vis_public')),
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
                        .withValues(alpha: 0.4),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
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
                        color: Colors.black.withValues(alpha: 0.45),
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
                  Text(LanguageService.t('public_room_album'),
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                  Text(LanguageService.t('public_album_sync'),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
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
      title: Text(LanguageService.t('new_album')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
                labelText: '${LanguageService.t('album_name')} *',
                border: const OutlineInputBorder()),
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
              decoration: InputDecoration(
                  labelText: LanguageService.t('f_date'),
                  border: const OutlineInputBorder()),
              child: Text(
                _date == null
                    ? LanguageService.t('pick_date_tap')
                    : '${_date!.year}/${_date!.month.toString().padLeft(2, "0")}/${_date!.day.toString().padLeft(2, "0")}',
                style: TextStyle(color: _date == null ? Colors.grey : Colors.black),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationCtrl,
            decoration: InputDecoration(
                labelText: LanguageService.t('f_loc'),
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(LanguageService.t('visibility'),
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
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
              Text(LanguageService.t('msg_no_rooms'),
                  style: const TextStyle(color: Colors.red, fontSize: 13))
            else
              DropdownButtonFormField<String>(
                value: _roomId,
                decoration: InputDecoration(
                    labelText: LanguageService.t('choose_room'),
                    border: const OutlineInputBorder()),
                hint: Text(LanguageService.t('choose_private_room')),
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
          child: Text(LanguageService.t('cancel')),
        ),
        FilledButton(
          onPressed: () async {
            final title = _titleCtrl.text.trim();
            if (title.isEmpty) return;
            if (_visibility == 'room' && _roomId == null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(LanguageService.t('msg_pick_room'))));
              return;
            }
            Navigator.pop(context);
            await widget.onCreate(
              title,
              _date == null
                  ? ''
                  : '${_date!.year}-${_date!.month.toString().padLeft(2, "0")}-${_date!.day.toString().padLeft(2, "0")}',
              _locationCtrl.text,
              _visibility,
              _roomId,
            );
          },
          child: Text(LanguageService.t('create')),
        ),
      ],
    );
  }
}
