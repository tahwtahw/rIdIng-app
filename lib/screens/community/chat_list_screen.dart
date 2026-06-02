import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import '../../config.dart';
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
      final r = await http.get(Uri.parse('${Config.baseUrl}/rooms'));
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
        title: const Text('聊天室'),
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
                      child: Text('尚未加入任何私人聊天室',
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
            tooltip: '加入聊天室',
            child: const Icon(Icons.login),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'create',
            onPressed: () => _showCreateDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('建立聊天室'),
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
        title: const Text('公開聊天室',
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('所有人都可以參與的公共頻道'),
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
          subtitle: Text('代碼：${room['code'] ?? ''}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.qr_code),
                tooltip: '顯示 QR Code',
                onPressed: () => _showQrCode(context, room),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.red),
                tooltip: '離開聊天室',
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
                  '代碼：${room['code']}',
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
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已複製代碼')));
                  },
                ),
              ],
            ),
            const Text('分享此 QR Code 或代碼給朋友',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('關閉')),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('建立私人聊天室'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: '聊天室名稱',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              await _createRoom(name);
            },
            child: const Text('建立'),
          ),
        ],
      ),
    );
  }

  Future<void> _createRoom(String name) async {
    try {
      final r = await http.post(
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('建立失敗：$e')));
      }
    }
  }

  void _showJoinDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('加入私人聊天室'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: '輸入 6 碼房間代碼',
            border: OutlineInputBorder(),
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
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinByCode(String code) async {
    try {
      final r = await http.get(
          Uri.parse('${Config.baseUrl}/rooms/code/$code'));
      if (r.statusCode == 404) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('找不到此聊天室代碼')));
        }
        return;
      }
      final room = jsonDecode(r.body);
      await UserService.joinRoom(room['id']);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已加入「${room['name']}」')));
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加入失敗：$e')));
      }
    }
  }

  Future<void> _leaveRoom(Map room) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('離開聊天室'),
        content: Text('確定離開「${room['name']}」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('離開'),
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
