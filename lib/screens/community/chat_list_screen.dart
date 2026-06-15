import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api_client.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../config.dart';
import '../../services/language_service.dart';
import '../../services/user_service.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<dynamic> _allRooms = [];
  List<String> _joinedIds = ['public'];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final joined = await UserService.getJoinedRooms();
      final r = await ApiClient.get(Uri.parse('${Config.baseUrl}/rooms'));
      final all = jsonDecode(r.body) as List;
      setState(() {
        _allRooms = all;
        _joinedIds = joined;
        _loading = false;
      });
    } catch (e) {
      debugPrint('錯誤：$e');
      setState(() => _loading = false);
    }
  }

  List<dynamic> get _myRooms =>
      _allRooms.where((r) => _joinedIds.contains(r['id'])).toList();

  void _openRoom(Map room) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          roomId: room['id'],
          roomName: room['name'],
          isPublic: room['is_public'] == true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('chat_rooms')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Public room (always first)
                  _buildPublicRoomTile(context),
                  const SizedBox(height: 8),
                  // Private rooms
                  ..._myRooms
                      .where((r) => r['id'] != 'public')
                      .map((r) => _buildRoomTile(r)),
                  // Empty state for private rooms
                  if (_myRooms.where((r) => r['id'] != 'public').isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(LanguageService.t('msg_no_rooms'),
                          style: TextStyle(color: Colors.grey.shade500),
                          textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'join',
            onPressed: () => _showJoinDialog(context),
            tooltip: LanguageService.t('join_room'),
            child: const Icon(Icons.login),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'create',
            onPressed: () => _showCreateDialog(context),
            icon: const Icon(Icons.add),
            label: Text(LanguageService.t('create_room')),
          ),
        ],
      ),
    );
  }

  Widget _buildPublicRoomTile(BuildContext context) {
    final room = _allRooms.firstWhere(
      (r) => r['id'] == 'public',
      orElse: () => {'id': 'public', 'name': '公開聊天室', 'is_public': true},
    );
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: Icon(Icons.public, color: Colors.blue.shade700),
        ),
        title: Text(LanguageService.t('public_room'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(LanguageService.t('public_room_desc')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openRoom(room),
      ),
    );
  }

  Widget _buildRoomTile(Map room) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.purple.shade100,
            child: Icon(Icons.lock, color: Colors.purple.shade700),
          ),
          title: Text(room['name'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle:
              Text('${LanguageService.t('room_code')}: ${room['code'] ?? ''}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.qr_code),
                tooltip: LanguageService.t('show_qr'),
                onPressed: () => _showQrCode(context, room),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.red),
                tooltip: LanguageService.t('leave_room'),
                onPressed: () => _leaveRoom(room),
              ),
            ],
          ),
          onTap: () => _openRoom(room),
        ),
      ),
    );
  }

  void _showQrCode(BuildContext context, Map room) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(room['name'] ?? ''),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 220,
              height: 220,
              color: Colors.white,
              padding: const EdgeInsets.all(10),
              child: QrImageView(
                data: room['code'] ?? 'NOCODE',
                version: QrVersions.auto,
                gapless: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${LanguageService.t('room_code')}: ${room['code']}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold,
                      letterSpacing: 4),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: '複製代碼',
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: room['code'] ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(LanguageService.t('code_copied'))));
                  },
                ),
              ],
            ),
            Text(LanguageService.t('share_qr'),
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(LanguageService.t('close'))),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(LanguageService.t('create_private_room')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: LanguageService.t('room_name'),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(LanguageService.t('cancel'))),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              await _createRoom(name);
            },
            child: Text(LanguageService.t('create')),
          ),
        ],
      ),
    );
  }

  Future<void> _createRoom(String name) async {
    try {
      final r = await ApiClient.post(
        Uri.parse('${Config.baseUrl}/rooms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'is_public': false}),
      );
      final room = jsonDecode(r.body);
      await UserService.joinRoom(room['id']);
      await _load();
      if (mounted) _showQrCode(context, room);
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${LanguageService.t('msg_create_fail')}: $e')));
      }
    }
  }

  void _showJoinDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(LanguageService.t('join_private_room')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: LanguageService.t('code_hint'),
            border: const OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final code = ctrl.text.trim().toUpperCase();
              if (code.length < 4) return;
              Navigator.pop(context);
              await _joinByCode(code);
            },
            child: Text(LanguageService.t('join')),
          ),
        ],
      ),
    );
  }

  Future<void> _joinByCode(String code) async {
    try {
      final r = await ApiClient.get(
          Uri.parse('${Config.baseUrl}/rooms/code/$code'));
      if (r.statusCode == 404) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(LanguageService.t('room_not_found'))));
        }
        return;
      }
      final room = jsonDecode(r.body);
      await UserService.joinRoom(room['id']);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(LanguageService.tp(
                'room_joined', {'x': '${room['name']}'}))));
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${LanguageService.t('msg_join_fail')}: $e')));
      }
    }
  }

  Future<void> _leaveRoom(Map room) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(LanguageService.t('leave_room')),
        content: Text(LanguageService.tp(
            'leave_room_confirm', {'x': '${room['name']}'})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(LanguageService.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(LanguageService.t('leave')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await UserService.leaveRoom(room['id']);
      await _load();
    }
  }
}
