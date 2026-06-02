import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config.dart';
import 'chat_list_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  List<dynamic> _members = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await http.get(Uri.parse('${Config.baseUrl}/members'));
      setState(() { _members = jsonDecode(r.body); _loading = false; });
    } catch (e) { debugPrint('錯誤：$e'); setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('社群'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Chat room entry
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ChatListScreen())),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.chat_bubble_outline,
                                color: Colors.purple.shade700, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('聊天室',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                                Text('公開聊天室 + 私人聊天室',
                                    style: TextStyle(color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Hall of fame
                  Text('名人榜',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_members.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text('尚無成員', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    ..._members.map((m) {
                      final rank = m['rank'] ?? 99;
                      Color medalColor = Colors.grey;
                      if (rank == 1) medalColor = Colors.amber;
                      if (rank == 2) medalColor = Colors.blueGrey.shade300;
                      if (rank == 3) medalColor = Colors.brown.shade300;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: medalColor.withOpacity(0.2),
                            child: Text('$rank',
                                style: TextStyle(
                                    color: medalColor,
                                    fontWeight: FontWeight.bold)),
                          ),
                          title: Text(m['name'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((m['badge'] ?? '').isNotEmpty)
                                Chip(
                                  label: Text(m['badge'],
                                      style: const TextStyle(fontSize: 11)),
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              Text('出遊 ${m['trips']} 次 · ${m['distance']} km'),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
