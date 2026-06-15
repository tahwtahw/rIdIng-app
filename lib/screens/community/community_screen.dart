import 'dart:convert';
import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../config.dart';
import '../../services/language_service.dart';
import 'chat_list_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  List<dynamic> _members = [];
  bool _loading = true;
  String? _country; // null = 全球總榜

  /// 名人榜分數 = 騎行總距離(km) + 前往的站點數
  double _score(dynamic m) =>
      (num.tryParse('${m['distance'] ?? 0}') ?? 0).toDouble() +
      (num.tryParse('${m['trips'] ?? 0}') ?? 0).toDouble();

  void _showRules() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.emoji_events, color: Colors.amber),
          const SizedBox(width: 8),
          Text(LanguageService.t('hall_rules')),
        ]),
        content: Text(LanguageService.t('rules_body')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(LanguageService.t('ok_got')),
          ),
        ],
      ),
    );
  }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiClient.get(Uri.parse('${Config.baseUrl}/members'));
      setState(() { _members = jsonDecode(r.body); _loading = false; });
    } catch (e) { debugPrint('錯誤：$e'); setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('nav_community')),
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
                                Text(LanguageService.t('chat_rooms'),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                                Text(
                                    '${LanguageService.t('public_room')} + ${LanguageService.t('private_room')}',
                                    style: TextStyle(
                                        color: Colors.grey.shade600)),
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
                  Row(
                    children: [
                      Text(LanguageService.t('hall_of_fame'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 2),
                      IconButton(
                        icon: Icon(Icons.error_outline,
                            size: 18, color: theme.colorScheme.primary),
                        tooltip: LanguageService.t('hall_rules'),
                        visualDensity: VisualDensity.compact,
                        onPressed: _showRules,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // 國家榜選擇（全球總榜 + 各國家）
                  Builder(builder: (context) {
                    final countries = _members
                        .map((m) => (m['country'] ?? '').toString().trim())
                        .where((c) => c.isNotEmpty)
                        .toSet()
                        .toList()
                      ..sort();
                    if (countries.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('🌏 全球總榜',
                                  style: TextStyle(fontSize: 12)),
                              selected: _country == null,
                              onSelected: (_) =>
                                  setState(() => _country = null),
                            ),
                            ...countries.map((c) => Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: ChoiceChip(
                                    label: Text(c,
                                        style:
                                            const TextStyle(fontSize: 12)),
                                    selected: _country == c,
                                    onSelected: (_) =>
                                        setState(() => _country = c),
                                  ),
                                )),
                          ],
                        ),
                      ),
                    );
                  }),

                  if (_members.isEmpty)
                    Card(
                      child: ListTile(
                        title: Text(LanguageService.t('no_members'),
                            style: const TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    Builder(builder: (context) {
                      // 依分數（總距離 + 站點數）自動排名
                      final list = (_country == null
                          ? [..._members]
                          : _members
                              .where((m) =>
                                  (m['country'] ?? '').toString().trim() ==
                                  _country)
                              .toList())
                        ..sort((a, b) => _score(b).compareTo(_score(a)));
                      if (list.isEmpty) {
                        return Card(
                          child: ListTile(
                            title: Text(
                                LanguageService.t('no_members_country'),
                                style:
                                    const TextStyle(color: Colors.grey)),
                          ),
                        );
                      }
                      return Column(
                        children: list.asMap().entries.map((entry) {
                          final rank = entry.key + 1;
                          final m = entry.value;
                          final country =
                              (m['country'] ?? '').toString().trim();
                          Color medalColor = Colors.grey;
                          if (rank == 1) medalColor = Colors.amber;
                          if (rank == 2) medalColor = Colors.blueGrey.shade300;
                          if (rank == 3) medalColor = Colors.brown.shade300;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    medalColor.withValues(alpha: 0.2),
                                child: Text('$rank',
                                    style: TextStyle(
                                        color: medalColor,
                                        fontWeight: FontWeight.bold)),
                              ),
                              title: Text(m['name'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if ((m['badge'] ?? '').isNotEmpty)
                                    Chip(
                                      label: Text(m['badge'],
                                          style:
                                              const TextStyle(fontSize: 11)),
                                      padding: EdgeInsets.zero,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  Text(
                                    '${LanguageService.t('station')} ${m['trips']} · ${m['distance']} km'
                                    '${_country == null && country.isNotEmpty ? ' · $country' : ''}'
                                    ' · ${LanguageService.t('score')} ${_score(m).round()}',
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        }).toList(),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
