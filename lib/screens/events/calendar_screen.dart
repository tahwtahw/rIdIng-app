import 'dart:convert';
import 'package:flutter/material.dart';
import '../../api_client.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../config.dart';
import '../../services/background_service.dart';
import '../../services/language_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<dynamic>> _eventMap = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 同時載入後台活動(events)與 App 建立的揪團行程(outings)
      final results = await Future.wait([
        ApiClient.get(Uri.parse('${Config.baseUrl}/events')),
        ApiClient.get(Uri.parse('${Config.baseUrl}/outings')),
      ]);
      final events = jsonDecode(results[0].body) as List;
      final outings = jsonDecode(results[1].body) as List;
      final map = <DateTime, List<dynamic>>{};
      for (final e in events) {
        final date = _parseDate(e['date']);
        if (date != null) {
          final key = DateTime(date.year, date.month, date.day);
          map.putIfAbsent(key, () => []).add({...e as Map, '_kind': 'event'});
        }
      }
      for (final o in outings) {
        final date = _parseDate(o['date']);
        if (date != null) {
          final key = DateTime(date.year, date.month, date.day);
          map.putIfAbsent(key, () => []).add({...o as Map, '_kind': 'outing'});
        }
      }
      setState(() {
        _eventMap = map;
        _loading = false;
      });
    } catch (e) {
      debugPrint('錯誤：$e');
      setState(() => _loading = false);
    }
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try { return DateTime.parse(raw.toString()); } catch (_) { return null; }
  }

  List<dynamic> _getEventsForDay(DateTime day) =>
      _eventMap[DateTime(day.year, day.month, day.day)] ?? [];

  /// 根據背景亮暗決定對比色
  Color _contrastColor() {
    final bg = BackgroundService.notifier.value;
    if (bg.type == 'color' && bg.color != null) {
      return bg.color!.computeLuminance() > 0.4 ? Colors.black87 : Colors.white;
    }
    return Colors.black87; // 預設深色文字
  }

  Color _calendarBg() {
    final bg = BackgroundService.notifier.value;
    if (bg.type == 'color' && bg.color != null) {
      final lum = bg.color!.computeLuminance();
      return lum > 0.4
          ? Colors.black.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.12);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedDay;
    final selectedEvents = selected != null ? _getEventsForDay(selected) : <dynamic>[];

    return ValueListenableBuilder<BackgroundConfig>(
      valueListenable: BackgroundService.notifier,
      builder: (_, __, ___) {
        final textColor = _contrastColor();
        final calBg    = _calendarBg();

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Container(
                  color: calBg,
                  child: TableCalendar(
                  firstDay: DateTime(2020),
                  lastDay: DateTime(2030),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
                  eventLoader: _getEventsForDay,
                  calendarStyle: CalendarStyle(
                    defaultTextStyle: TextStyle(color: textColor),
                    weekendTextStyle: TextStyle(color: textColor.withValues(alpha: 0.7)),
                    outsideTextStyle: TextStyle(color: textColor.withValues(alpha: 0.3)),
                    markerDecoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    todayDecoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold),
                  ),
                  // 有活動的日期顯示 '!'
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (context, day, events) {
                      if (events.isEmpty) return null;
                      return Positioned(
                        bottom: 2,
                        child: Text(
                          '!',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(
                        color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                    leftChevronIcon: Icon(Icons.chevron_left, color: textColor),
                    rightChevronIcon: Icon(Icons.chevron_right, color: textColor),
                  ),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: TextStyle(color: textColor.withValues(alpha: 0.8), fontSize: 12),
                    weekendStyle: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12),
                  ),
                  onDaySelected: (sel, focused) {
                    setState(() {
                      _selectedDay = sel;
                      _focusedDay = focused;
                    });
                  },
                  onPageChanged: (focused) => _focusedDay = focused,
                ),
                ), // Container
                const Divider(height: 1),
                if (selected != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '${selected.year}/${selected.month.toString().padLeft(2, '0')}/${selected.day.toString().padLeft(2, '0')} · ${LanguageService.t('nav_events')}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: textColor),
                    ),
                  ),
                  if (selectedEvents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                          child: Text(LanguageService.t('no_event_day'),
                              style: TextStyle(color: textColor.withValues(alpha: 0.5)))),
                    )
                  else
                    ...selectedEvents.map((e) {
                      final isOuting = e['_kind'] == 'outing';
                      final dest = (e['destination'] ?? '').toString();
                      final loc = (e['location'] ?? '').toString();
                      return ListTile(
                        leading: Icon(
                            isOuting ? Icons.two_wheeler : Icons.event,
                            color: textColor),
                        title: Text(e['title'] ?? '',
                            style: TextStyle(color: textColor)),
                        subtitle: Text(
                            isOuting && dest.isNotEmpty
                                ? (loc.isNotEmpty ? '$loc → $dest' : dest)
                                : loc,
                            style: TextStyle(
                                color: textColor.withValues(alpha: 0.7))),
                        trailing: isOuting
                            ? Chip(
                                label: Text(
                                    LanguageService.t('tab_outings'),
                                    style: TextStyle(
                                        fontSize: 11, color: textColor)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              )
                            : null,
                      );
                    }),
                ] else
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(LanguageService.t('pick_date_hint'),
                          style: TextStyle(color: textColor.withValues(alpha: 0.5))),
                    ),
                  ),
              ],
            ),
          );
      }, // ValueListenableBuilder builder
    ); // ValueListenableBuilder
  }
}
