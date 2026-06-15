import 'dart:convert';
import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../config.dart';
import '../../services/user_service.dart';
import '../../services/language_service.dart';
import 'weather_card.dart';

class InfoScreen extends StatefulWidget {
  const InfoScreen({super.key});
  @override
  State<InfoScreen> createState() => _InfoScreenState();
}

class _InfoScreenState extends State<InfoScreen> {
  List<dynamic> _articles = [];
  List<dynamic> _charity = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        ApiClient.get(Uri.parse('${Config.baseUrl}/articles')),
        ApiClient.get(Uri.parse('${Config.baseUrl}/charity')),
      ]);
      setState(() {
        _articles = jsonDecode(r[0].body);
        _charity = jsonDecode(r[1].body);
        _loading = false;
      });
    } catch (e) { debugPrint('錯誤：$e'); setState(() => _loading = false); }
  }

  void _showFeedbackDialog() {
    showDialog(
      context: context,
      builder: (_) => const _FeedbackDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<String>(
          valueListenable: LanguageService.notifier,
          builder: (_, __, ___) => Text(LanguageService.t('nav_info')),
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const WeatherCard(),
                  const SizedBox(height: 16),
                  Text(LanguageService.t('featured_articles'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_articles.isEmpty)
                    Card(
                        child: ListTile(
                            title: Text(LanguageService.t('no_articles'),
                                style:
                                    const TextStyle(color: Colors.grey))))
                  else
                    ..._articles.map((a) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.article, color: Colors.blue),
                        title: Text(a['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Row(children: [
                          Chip(label: Text(a['category'] ?? '', style: const TextStyle(fontSize: 11)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          const SizedBox(width: 6),
                          Text(a['author'] ?? '', style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    )),
                  const SizedBox(height: 16),
                  Text(LanguageService.t('charity'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_charity.isEmpty)
                    Card(
                        child: ListTile(
                            title: Text(LanguageService.t('no_charity'),
                                style:
                                    const TextStyle(color: Colors.grey))))
                  else
                    ..._charity.map((c) {
                      final int joined = c['joined'] ?? 0;
                      final int spots = c['spots'] ?? 1;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 6),
                            Text('📅 ${c['date'] ?? ''}   📍 ${c['location'] ?? ''}'),
                            if ((c['description'] ?? '').isNotEmpty)
                              Padding(padding: const EdgeInsets.only(top: 4),
                                  child: Text(c['description'], style: const TextStyle(fontSize: 13))),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(value: joined / spots, minHeight: 6,
                                borderRadius: BorderRadius.circular(3)),
                            const SizedBox(height: 4),
                            Text(
                                LanguageService.tp('reg_count',
                                    {'a': '$joined', 'b': '$spots'}),
                                style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  // ── 反饋入口 ──────────────────────────────────────
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _showFeedbackDialog,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.feedback_outlined,
                                color: Colors.orange.shade700, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(LanguageService.t('feedback_suggest'),
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                                Text(LanguageService.t('feedback_tellus'),
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ── 反饋對話框 ───────────────────────────────────────────────────────────
class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _ctrl = TextEditingController();
  String _type = '問題回報';
  bool _sending = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final sender = await UserService.getUsername() ?? '匿名';
      await ApiClient.post(
        Uri.parse('${Config.baseUrl}/feedback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender': sender,
          'content': text,
          'type': _type,
          'status': 'unread',
        }),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('feedback_thanks'))),
        );
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(LanguageService.t('feedback_title')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          value: _type,
          decoration: InputDecoration(
              labelText: LanguageService.t('f_type'),
              border: const OutlineInputBorder()),
          // value 維持中文存入後端，顯示文字依語言翻譯
          items: [
            DropdownMenuItem(
                value: '問題回報',
                child: Text(LanguageService.t('fb_bug'))),
            DropdownMenuItem(
                value: '功能建議',
                child: Text(LanguageService.t('fb_feature'))),
            DropdownMenuItem(
                value: '其他', child: Text(LanguageService.t('fb_other'))),
          ],
          onChanged: (v) => setState(() => _type = v!),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          decoration: InputDecoration(
            labelText: LanguageService.t('feedback_desc'),
            border: const OutlineInputBorder(),
            hintText: LanguageService.t('feedback_hint'),
          ),
          maxLines: 4,
          autofocus: true,
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LanguageService.t('cancel'))),
        FilledButton(
          onPressed: _sending ? null : _submit,
          child: _sending
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(LanguageService.t('send')),
        ),
      ],
    );
  }
}
