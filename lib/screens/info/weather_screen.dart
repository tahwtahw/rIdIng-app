import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../services/language_service.dart';
import '../../services/weather_service.dart';
import '../weather/route_weather_screen.dart';

// ═══════════════════════════════════════════════════════════
// 縣市清單（名稱 + 中心座標）
// ═══════════════════════════════════════════════════════════

class _City {
  final String name;  // 原始名稱（API 查詢/比對用）
  final String tKey;  // 翻譯鍵（空字串 = 直接顯示 name）
  final double lat, lon;
  const _City(this.name, this.lat, this.lon, [this.tKey = '']);
}

/// 縣市顯示名稱（依語言）
String _cityLabel(_City c) =>
    c.tKey.isEmpty ? c.name : LanguageService.t(c.tKey);

const _kGpsCity = _City('目前位置', 0, 0, 'cur_loc_gps'); // 特殊：GPS

const _kCities = [
  _City('基隆市', 25.1283, 121.7419, 'ct_kee'),
  _City('臺北市', 25.0330, 121.5654, 'ct_tpe'),
  _City('新北市', 25.0169, 121.4627, 'ct_ntp'),
  _City('桃園市', 24.9937, 121.2980, 'ct_tao'),
  _City('新竹市', 24.8036, 120.9686, 'ct_hsc'),
  _City('新竹縣', 24.7021, 121.1523, 'ct_hsx'),
  _City('苗栗縣', 24.5602, 120.8214, 'ct_mia'),
  _City('臺中市', 24.1477, 120.6736, 'ct_txg'),
  _City('彰化縣', 24.0518, 120.5162, 'ct_cha'),
  _City('南投縣', 23.9602, 120.9718, 'ct_nto'),
  _City('雲林縣', 23.7092, 120.4313, 'ct_yun'),
  _City('嘉義市', 23.4800, 120.4491, 'ct_cyi'),
  _City('嘉義縣', 23.4518, 120.2554, 'ct_cyx'),
  _City('臺南市', 22.9999, 120.2270, 'ct_tnn'),
  _City('高雄市', 22.6273, 120.3014, 'ct_khh'),
  _City('屏東縣', 22.5519, 120.5488, 'ct_pit'),
  _City('宜蘭縣', 24.7021, 121.7377, 'ct_ila'),
  _City('花蓮縣', 23.9871, 121.6015, 'ct_hun'),
  _City('臺東縣', 22.7972, 121.0714, 'ct_ttt'),
  _City('澎湖縣', 23.5711, 119.5793, 'ct_pen'),
  _City('金門縣', 24.4493, 118.3767, 'ct_kmn'),
  _City('連江縣', 26.1612, 119.9519, 'ct_ljg'),
];

// ═══════════════════════════════════════════════════════════
// 天氣預報頁面（鄉鎮天氣 + 路線天氣）
// ═══════════════════════════════════════════════════════════

class WeatherScreen extends StatelessWidget {
  const WeatherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(LanguageService.t('weather_forecast')),
          bottom: TabBar(
            tabs: [
              Tab(
                  icon: const Icon(Icons.location_city),
                  text: LanguageService.t('town_weather')),
              Tab(
                  icon: const Icon(Icons.route),
                  text: LanguageService.t('route_weather')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _TownshipWeatherTab(),
            RouteWeatherScreen(embedded: true),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 鄉鎮天氣 Tab
// ═══════════════════════════════════════════════════════════

class _TownshipWeatherTab extends StatefulWidget {
  const _TownshipWeatherTab();

  @override
  State<_TownshipWeatherTab> createState() => _TownshipWeatherTabState();
}

class _TownshipWeatherTabState extends State<_TownshipWeatherTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  _City _selected = _kGpsCity;
  bool _loading = false;
  String? _error;
  String _displayName = '';
  _CurrentWeather? _current;
  List<_DailyWeather> _daily = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _showCityPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CityPickerSheet(
        selected: _selected,
        onSelect: (c) {
          Navigator.pop(context);
          _onCitySelected(c);
        },
      ),
    );
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      double lat, lon;

      if (_selected == _kGpsCity) {
        // GPS 定位
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.deniedForever) {
          throw Exception(LanguageService.t('loc_denied'));
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium),
        );
        lat = pos.latitude;
        lon = pos.longitude;

        // 反向地理編碼
        final geoResp = await http.get(
          Uri.parse('https://nominatim.openstreetmap.org/reverse'
              '?lat=$lat&lon=$lon&format=json&accept-language=zh'),
          headers: {'User-Agent': 'rIdIng-app/1.0'},
        );
        if (!mounted) return;
        String name = LanguageService.t('current_loc');
        if (geoResp.statusCode == 200) {
          final addr =
              (jsonDecode(geoResp.body) as Map<String, dynamic>)['address']
                  as Map?;
          if (addr != null) {
            final city = addr['city'] ?? addr['county'] ?? addr['state'] ?? '';
            final district = addr['city_district'] ??
                addr['suburb'] ??
                addr['town'] ??
                addr['village'] ??
                '';
            final parts = <String>[];
            if (city.toString().isNotEmpty) parts.add(city.toString());
            if (district.toString().isNotEmpty && district != city) {
              parts.add(district.toString());
            }
            if (parts.isNotEmpty) name = parts.join(' ');
          }
        }
        _displayName = name;
      } else {
        lat = _selected.lat;
        lon = _selected.lon;
        _displayName = _cityLabel(_selected);
      }

      // Open-Meteo 天氣
      final resp = await http.get(Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,relative_humidity_2m,apparent_temperature,'
        'precipitation_probability,weathercode,windspeed_10m'
        '&daily=weathercode,temperature_2m_max,temperature_2m_min,'
        'precipitation_probability_max,windspeed_10m_max'
        '&timezone=auto&forecast_days=7',
      ));
      if (!mounted) return;
      if (resp.statusCode != 200) {
        throw Exception(LanguageService.t('weather_fail'));
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final cur = data['current'] as Map<String, dynamic>;
      final day = data['daily'] as Map<String, dynamic>;
      final List times = day['time'] as List;

      if (mounted) {
        setState(() {
          _current = _CurrentWeather(
            temp: (cur['temperature_2m'] as num).toDouble(),
            feelsLike: (cur['apparent_temperature'] as num).toDouble(),
            humidity: (cur['relative_humidity_2m'] as num).toInt(),
            rainProb: (cur['precipitation_probability'] as num? ?? 0).toInt(),
            code: (cur['weathercode'] as num).toInt(),
            windSpeed: (cur['windspeed_10m'] as num).toDouble(),
          );
          _daily = List.generate(
            times.length,
            (i) => _DailyWeather(
              date: times[i] as String,
              code: (day['weathercode'] as List)[i] as int,
              maxTemp:
                  ((day['temperature_2m_max'] as List)[i] as num).toDouble(),
              minTemp:
                  ((day['temperature_2m_min'] as List)[i] as num).toDouble(),
              rainProb: ((day['precipitation_probability_max'] as List)[i]
                          as num? ??
                      0)
                  .toInt(),
              maxWind:
                  ((day['windspeed_10m_max'] as List)[i] as num).toDouble(),
            ),
          );
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onCitySelected(_City city) {
    if (_selected == city) return;
    setState(() => _selected = city);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // ── 城市選擇器 item ──────────────────────────
    final selectorTile = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: FilledButton.tonalIcon(
        icon: Icon(
          _selected == _kGpsCity ? Icons.my_location : Icons.location_city,
          size: 18,
        ),
        label: Row(children: [
          Expanded(
            child: Text(
              _cityLabel(_selected),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down, size: 20),
        ]),
        style: FilledButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _showCityPicker,
      ),
    );

    // ── 載入中 ───────────────────────────────────
    if (_loading) {
      return Column(children: [
        selectorTile,
        const Expanded(child: Center(child: CircularProgressIndicator())),
      ]);
    }

    // ── 錯誤 ─────────────────────────────────────
    if (_error != null) {
      return Column(children: [
        selectorTile,
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: Text(LanguageService.t('retry')),
                  onPressed: _load,
                ),
              ]),
            ),
          ),
        ),
      ]);
    }

    // ── 正常內容：全部放進同一個 ListView ────────
    final cur = _current!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          selectorTile,
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 目前天氣卡 ───────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.location_on,
                                size: 16, color: cs.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(_displayName,
                                  style: TextStyle(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ]),
                          const SizedBox(height: 16),
                          Row(children: [
                            Icon(_weatherIcon(cur.code),
                                size: 56,
                                color: _weatherColor(cur.code)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${cur.temp.toStringAsFixed(1)}°C',
                                        style: theme.textTheme.displaySmall
                                            ?.copyWith(
                                                fontWeight:
                                                    FontWeight.bold)),
                                    Text(_weatherLabel(cur.code),
                                        style: TextStyle(
                                            color: cs.onSurfaceVariant,
                                            fontSize: 15)),
                                    Text(
                                        '${LanguageService.t('feels_like')} ${cur.feelsLike.toStringAsFixed(0)}°C',
                                        style: TextStyle(
                                            color: cs.onSurfaceVariant,
                                            fontSize: 13)),
                                  ]),
                            ),
                          ]),
                          const SizedBox(height: 16),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            _StatChip(
                                icon: Icons.water_drop_outlined,
                                label:
                                    '${LanguageService.t('humidity')} ${cur.humidity}%'),
                            _StatChip(
                                icon: Icons.umbrella_outlined,
                                label:
                                    '${LanguageService.t('rain')} ${cur.rainProb}%'),
                            _StatChip(
                                icon: Icons.air,
                                label:
                                    '${LanguageService.t('wind')} ${cur.windSpeed.round()} km/h'),
                          ]),
                        ]),
                  ),
                ),

                const SizedBox(height: 16),
                Text(LanguageService.t('seven_day'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

                // ── 7 日預報 ─────────────────────
                ..._daily.asMap().entries.map((e) {
                  final i = e.key;
                  final d = e.value;
                  final parts = d.date.split('-');
                  final label = i == 0
                      ? LanguageService.t('today')
                      : i == 1
                          ? LanguageService.t('tomorrow')
                          : '${int.parse(parts[1])}/${int.parse(parts[2])}';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(children: [
                        SizedBox(
                            width: 44,
                            child: Text(label,
                                style: TextStyle(
                                    fontWeight: i == 0
                                        ? FontWeight.bold
                                        : FontWeight.normal))),
                        Icon(_weatherIcon(d.code),
                            color: _weatherColor(d.code), size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_weatherLabel(d.code),
                                style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 13))),
                        Text('${d.minTemp.round()}°',
                            style: TextStyle(
                                color: Colors.blue.shade400, fontSize: 13)),
                        Text(' / ',
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 13)),
                        Text('${d.maxTemp.round()}°',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 12),
                        Icon(Icons.water_drop,
                            size: 13, color: Colors.blue.shade300),
                        Text(' ${d.rainProb}%',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade400)),
                      ]),
                    ),
                  );
                }),

                const SizedBox(height: 8),
                Text('${LanguageService.t('data_source')}: Open-Meteo · OpenStreetMap',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 小資訊 Chip ──────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13,
            color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

// ── 資料模型 ─────────────────────────────────────────────
class _CurrentWeather {
  final double temp, feelsLike, windSpeed;
  final int humidity, rainProb, code;
  const _CurrentWeather({
    required this.temp, required this.feelsLike, required this.humidity,
    required this.rainProb, required this.code, required this.windSpeed,
  });
}

class _DailyWeather {
  final String date;
  final int code, rainProb;
  final double maxTemp, minTemp, maxWind;
  const _DailyWeather({
    required this.date, required this.code, required this.maxTemp,
    required this.minTemp, required this.rainProb, required this.maxWind,
  });
}

// ── 天氣工具函式 ─────────────────────────────────────────
IconData _weatherIcon(int code) {
  if (code == 0) return Icons.wb_sunny;
  if (code <= 2) return Icons.wb_cloudy_outlined;
  if (code == 3) return Icons.cloud;
  if (code <= 48) return Icons.foggy;
  if (code <= 57) return Icons.grain;
  if (code <= 67) return Icons.umbrella;
  if (code <= 77) return Icons.ac_unit;
  if (code <= 82) return Icons.shower;
  if (code <= 86) return Icons.cloudy_snowing;
  return Icons.thunderstorm;
}

Color _weatherColor(int code) {
  if (code == 0) return Colors.orange;
  if (code <= 2) return Colors.amber;
  if (code <= 3) return Colors.blueGrey;
  if (code <= 48) return Colors.grey;
  if (code <= 67) return Colors.blue;
  if (code <= 77) return Colors.lightBlue;
  if (code <= 82) return Colors.indigo;
  return Colors.deepPurple;
}

String _weatherLabel(int code) {
  // 委派給 weather_service 的多語天氣標籤
  return weatherLabel(code);
}

// ═══════════════════════════════════════════════════════════
// 城市選擇 BottomSheet（支援搜尋全球地點）
// ═══════════════════════════════════════════════════════════

class _CityPickerSheet extends StatefulWidget {
  final _City? selected;
  final void Function(_City) onSelect;
  const _CityPickerSheet(
      {required this.selected, required this.onSelect});

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<_City> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _results = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    try {
      final resp = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(q)}&format=json&limit=8'
            '&accept-language=zh'),
        headers: {'User-Agent': 'rIdIng-app/1.0'},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List;
        setState(() {
          _results = data.map((r) {
            final raw = r['display_name'] as String;
            final name = raw.split(',').take(3).join(', ');
            return _City(name,
                double.parse(r['lat'] as String),
                double.parse(r['lon'] as String));
          }).toList();
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchCtrl.text.trim().isNotEmpty;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Column(children: [
        const SizedBox(height: 10),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 12),
        Text(LanguageService.t('pick_place'),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        // 搜尋框
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl,
            autofocus: false,
            decoration: InputDecoration(
              hintText: LanguageService.t('search_place'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _results = []);
                          },
                        )
                      : null,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _search,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        // 列表
        Expanded(
          child: ListView.separated(
            controller: scrollCtrl,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: isSearching
                ? _results.length
                : 1 + _kCities.length,
            itemBuilder: (_, i) {
              if (!isSearching) {
                // GPS 選項
                if (i == 0) {
                  return ListTile(
                    leading: const Icon(Icons.my_location),
                    title: Text(LanguageService.t('cur_loc_gps')),
                    selected: widget.selected == _kGpsCity,
                    onTap: () => widget.onSelect(_kGpsCity),
                  );
                }
                final c = _kCities[i - 1];
                return ListTile(
                  leading: const Icon(Icons.location_city_outlined),
                  title: Text(_cityLabel(c)),
                  selected: widget.selected == c,
                  onTap: () => widget.onSelect(c),
                );
              }
              // 搜尋結果
              if (_results.isEmpty) {
                return ListTile(
                  title: Text(LanguageService.t('no_place'),
                      style: const TextStyle(color: Colors.grey)),
                );
              }
              final c = _results[i];
              return ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(c.name),
                onTap: () => widget.onSelect(c),
              );
            },
          ),
        ),
      ]),
    );
  }
}
