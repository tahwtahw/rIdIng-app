import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config.dart';
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
        http.get(Uri.parse('${Config.baseUrl}/articles')),
        http.get(Uri.parse('${Config.baseUrl}/charity')),
      ]);
      setState(() {
        _articles = jsonDecode(r[0].body);
        _charity = jsonDecode(r[1].body);
        _loading = false;
      });
    } catch (e) { debugPrint('錯誤：$e'); setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('資訊'),
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
                  Text('精選文章', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_articles.isEmpty)
                    const Card(child: ListTile(title: Text('尚無文章', style: TextStyle(color: Colors.grey))))
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
                  Text('公益活動', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_charity.isEmpty)
                    const Card(child: ListTile(title: Text('尚無公益活動', style: TextStyle(color: Colors.grey))))
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
                            Text('已報名 $joined / $spots 人', style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
