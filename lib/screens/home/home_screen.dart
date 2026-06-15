import 'dart:convert';
import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../config.dart';
import '../../services/language_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _events = [];
  List<dynamic> _outings = [];
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
      final responses = await Future.wait([
        ApiClient.get(Uri.parse('${Config.baseUrl}/events')),
        ApiClient.get(Uri.parse('${Config.baseUrl}/outings')),
      ]);
      setState(() {
        _events = jsonDecode(responses[0].body);
        _outings = jsonDecode(responses[1].body);
        _loading = false;
      });
    } catch (e) {
      debugPrint('錯誤：$e');
      setState(() {
        _error = '${LanguageService.t('error')}: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('rIdIng'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: _load,
                      child: Text(LanguageService.t('retry'))),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Banner
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [theme.colorScheme.primary, theme.colorScheme.primaryContainer],
                            ),
                          ),
                          child: Row(children: [
                            const Icon(Icons.pedal_bike, color: Colors.white, size: 48),
                            const SizedBox(width: 16),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(LanguageService.t('welcome_back'),
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(color: Colors.white)),
                              Text(
                                  LanguageService.tp('events_ongoing',
                                      {'n': '${_outings.length}'}),
                                  style: TextStyle(
                                      color: Colors.white
                                          .withValues(alpha: 0.9))),
                            ]),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Upcoming events
                      Text(LanguageService.t('recent_events'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_events.isEmpty)
                        Card(
                            child: ListTile(
                                title: Text(
                                    LanguageService.t('no_events_now'),
                                    style: const TextStyle(
                                        color: Colors.grey))))
                      else
                        ..._events.take(3).map((e) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.event, color: Colors.blue),
                            title: Text(e['title'] ?? ''),
                            subtitle: Text('${e['date'] ?? ''} · ${e['location'] ?? ''}'),
                            trailing: e['is_regular'] == 1
                                ? Chip(
                                    label: Text(
                                        LanguageService.t('fixed_tag'),
                                        style: const TextStyle(
                                            fontSize: 11)))
                                : null,
                          ),
                        )),
                      const SizedBox(height: 16),
                      Text(LanguageService.t('latest_events'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (_outings.isEmpty)
                        Card(
                            child: ListTile(
                                title: Text(
                                    LanguageService.t('no_outings_now'),
                                    style: const TextStyle(
                                        color: Colors.grey))))
                      else
                        ..._outings.take(3).map((o) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.group, color: Colors.orange),
                            title: Text(o['title'] ?? ''),
                            subtitle: Text('${o['date'] ?? ''} · ${o['location'] ?? ''}'),
                            trailing: Text(
                                '${o['joined']}/${o['capacity']} ${LanguageService.t('ppl')}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                        )),
                    ],
                  ),
                ),
    );
  }
}
