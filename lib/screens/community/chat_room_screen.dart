import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api_client.dart';
import 'package:share_plus/share_plus.dart';
import '../../config.dart';
import '../../services/language_service.dart';
import '../../services/user_service.dart';
import 'room_photos_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final String roomName;
  final bool isPublic;

  const ChatRoomScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.isPublic,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<dynamic> _messages = [];
  String _username = '我';
  Timer? _pollTimer;
  String? _lastTime;
  bool _sending = false;
  Map? _replyTo; // quoted reply target

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  Future<void> _init() async {
    String? name = await UserService.getUsername();
    if (name == null || name.isEmpty) {
      if (mounted) name = await _askUsername();
    }
    setState(() => _username = name ?? '匿名');

    if (widget.isPublic) {
      final asked = await UserService.hasAskedPublicNotif();
      if (!asked && mounted) {
        await _askPublicNotif();
        await UserService.markPublicNotifAsked();
      }
    }

    await _loadMessages();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _pollNew());
  }

  Future<String?> _askUsername() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(LanguageService.t('set_nickname')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
              hintText: LanguageService.t('enter_your_nickname')),
          autofocus: true,
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              await UserService.setUsername(name);
              if (mounted) Navigator.pop(context, name);
            },
            child: Text(LanguageService.t('confirm')),
          ),
        ],
      ),
    );
  }

  Future<void> _askPublicNotif() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(LanguageService.t('notif_title')),
        content: Text(LanguageService.t('notif_ask')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(LanguageService.t('not_now'))),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(LanguageService.t('open'))),
        ],
      ),
    );
  }

  Future<void> _loadMessages() async {
    try {
      final r = await ApiClient.get(
        Uri.parse('${Config.baseUrl}/rooms/${widget.roomId}/messages'),
      );
      final msgs = jsonDecode(r.body) as List;
      setState(() {
        _messages = msgs;
        if (msgs.isNotEmpty) _lastTime = msgs.last['created_at'];
      });
      _scrollToBottom();
    } catch (e) { debugPrint('錯誤：$e'); }
  }

  Future<void> _pollNew() async {
    if (_tabController.index != 0) return;
    try {
      final url = _lastTime != null
          ? '${Config.baseUrl}/rooms/${widget.roomId}/messages?since=${Uri.encodeComponent(_lastTime!)}'
          : '${Config.baseUrl}/rooms/${widget.roomId}/messages';
      final r = await ApiClient.get(Uri.parse(url));
      final newMsgs = jsonDecode(r.body) as List;
      if (newMsgs.isNotEmpty) {
        setState(() {
          _messages.addAll(newMsgs);
          _lastTime = newMsgs.last['created_at'];
        });
        _scrollToBottom();
      }
    } catch (e) { debugPrint('錯誤：$e'); }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    final replySnapshot = _replyTo;
    setState(() => _replyTo = null);
    try {
      final body = <String, dynamic>{
        'sender': _username,
        'text': text,
      };
      if (replySnapshot != null) {
        body['reply_to'] = {
          'sender': replySnapshot['sender'],
          'text': replySnapshot['text'],
        };
      }
      final r = await ApiClient.post(
        Uri.parse('${Config.baseUrl}/rooms/${widget.roomId}/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      final msg = jsonDecode(r.body);
      setState(() {
        _messages.add(msg);
        _lastTime = msg['created_at'];
      });
      _scrollToBottom();
    } catch (e) { debugPrint('錯誤：$e'); }
    setState(() => _sending = false);
  }

  // ── Long press menu ──────────────────────────────────
  void _onLongPress(Map msg) {
    final isMine = msg['sender'] == _username;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Preview
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '"${msg['text']}"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
            const Divider(height: 1),
            _MenuItem(
              icon: Icons.copy_outlined,
              label: LanguageService.t('copy'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: msg['text'] ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(LanguageService.t('msg_copied'))),
                );
              },
            ),
            _MenuItem(
              icon: Icons.share_outlined,
              label: LanguageService.t('share'),
              onTap: () {
                Navigator.pop(context);
                Share.share(msg['text'] ?? '');
              },
            ),
            _MenuItem(
              icon: Icons.reply_outlined,
              label: LanguageService.t('reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyTo = msg);
                _controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: _controller.text.length),
                );
              },
            ),
            if (isMine)
              _MenuItem(
                icon: Icons.edit_outlined,
                label: LanguageService.t('edit'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(msg);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(Map msg) {
    final ctrl = TextEditingController(text: msg['text'] ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(LanguageService.t('edit_message')),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          maxLines: null,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(LanguageService.t('cancel'))),
          FilledButton(
            onPressed: () async {
              final newText = ctrl.text.trim();
              if (newText.isEmpty) return;
              Navigator.pop(context);
              await _editMessage(msg['id'], newText);
            },
            child: Text(LanguageService.t('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _editMessage(String msgId, String newText) async {
    try {
      final r = await ApiClient.put(
        Uri.parse(
            '${Config.baseUrl}/rooms/${widget.roomId}/messages/$msgId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': newText}),
      );
      final updated = jsonDecode(r.body);
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == msgId);
        if (idx != -1) _messages[idx] = updated;
      });
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${LanguageService.t('edit_fail')}: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 公開聊天室名稱依語言顯示；私人聊天室顯示自訂名稱
            Text(widget.isPublic
                ? LanguageService.t('public_room')
                : widget.roomName),
            Text(
              widget.isPublic
                  ? LanguageService.t('public_room')
                  : LanguageService.t('private_room'),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
                icon: const Icon(Icons.chat_bubble_outline),
                text: LanguageService.t('messages')),
            Tab(
                icon: const Icon(Icons.photo_library_outlined),
                text: LanguageService.t('nav_gallery')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Messages tab ──
          Column(children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Text(LanguageService.t('no_messages'),
                          style: const TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) {
                        final m = _messages[i];
                        final isMine = m['sender'] == _username;
                        return GestureDetector(
                          onLongPress: () => _onLongPress(m),
                          child: _Bubble(
                            sender: m['sender'] ?? '匿名',
                            text: m['text'] ?? '',
                            time: (m['created_at'] ?? '').toString().length >=
                                    16
                                ? (m['created_at'] as String)
                                    .substring(11, 16)
                                : '',
                            isMine: isMine,
                            edited: m['edited'] == true,
                            replyTo: m['reply_to'],
                          ),
                        );
                      },
                    ),
            ),
            // Reply preview bar
            if (_replyTo != null) _ReplyBar(
              msg: _replyTo!,
              onCancel: () => setState(() => _replyTo = null),
            ),
            _InputBar(
              controller: _controller,
              onSend: _send,
              sending: _sending,
            ),
          ]),

          // ── Photos tab ──
          RoomPhotosScreen(
            roomId: widget.roomId,
            isPublic: widget.isPublic,
          ),
        ],
      ),
    );
  }
}

// ── Menu item ─────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }
}

// ── Reply preview bar ─────────────────────────────────
class _ReplyBar extends StatelessWidget {
  final Map msg;
  final VoidCallback onCancel;
  const _ReplyBar({required this.msg, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(children: [
        Container(
          width: 3,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(msg['sender'] ?? '',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary)),
              Text(
                msg['text'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: onCancel,
        ),
      ]),
    );
  }
}

// ── Message bubble ────────────────────────────────────
class _Bubble extends StatelessWidget {
  final String sender;
  final String text;
  final String time;
  final bool isMine;
  final bool edited;
  final Map? replyTo;

  const _Bubble({
    required this.sender,
    required this.text,
    required this.time,
    required this.isMine,
    required this.edited,
    this.replyTo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isMine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(edited ? '${LanguageService.t('edited')} · $time' : time,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500)),
            const SizedBox(width: 6),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth:
                        MediaQuery.of(context).size.width * 0.65),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (replyTo != null) _QuoteBox(replyTo: replyTo!, isMine: true),
                      Text(text,
                          style: TextStyle(
                              color: theme.colorScheme.onPrimary)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(sender.isNotEmpty ? sender[0] : '?',
                style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sender,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.60),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(18),
                              bottomLeft: Radius.circular(18),
                              bottomRight: Radius.circular(18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (replyTo != null)
                                _QuoteBox(replyTo: replyTo!, isMine: false),
                              Text(text),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(edited ? '${LanguageService.t('edited')} · $time' : time,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quote box inside bubble ───────────────────────────
class _QuoteBox extends StatelessWidget {
  final Map replyTo;
  final bool isMine;
  const _QuoteBox({required this.replyTo, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.white.withValues(alpha: 0.18)
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: isMine ? Colors.white54 : theme.colorScheme.primary,
            width: 2.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(replyTo['sender'] ?? '',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isMine
                      ? Colors.white70
                      : theme.colorScheme.primary)),
          Text(replyTo['text'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: isMine ? Colors.white60 : Colors.grey.shade600)),
        ],
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;

  const _InputBar(
      {required this.controller,
      required this.onSend,
      required this.sending});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, -2))
        ],
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: null,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: LanguageService.t('type_message'),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none),
              filled: true,
              fillColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 8),
        sending
            ? const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
                icon: Icon(Icons.send_rounded,
                    color: Theme.of(context).colorScheme.primary),
                onPressed: onSend,
              ),
      ]),
    );
  }
}
