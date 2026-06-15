import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../../services/language_service.dart';
import '../../services/routing_service.dart';
import '../../services/weather_service.dart';
import '../../services/gpx_service.dart';

// ════════════════════════════════════════════════════════════
// 採樣點標示方式
// ════════════════════════════════════════════════════════════

enum LabelMode {
  km,       // 距起點公里數
  road,     // 道路名稱（取自路線規劃路名）
  district, // 行政區
}

// ════════════════════════════════════════════════════════════
// 路線天氣主畫面
// ════════════════════════════════════════════════════════════

class RouteWeatherScreen extends StatefulWidget {
  /// [embedded] = true 時作為 Tab 嵌入，不顯示自己的 AppBar
  final bool embedded;
  const RouteWeatherScreen({super.key, this.embedded = false});

  @override
  State<RouteWeatherScreen> createState() => _RouteWeatherScreenState();
}

class _RouteWeatherScreenState extends State<RouteWeatherScreen> {
  final MapController _mapController = MapController();

  // 使用者點選的路線點（起點、中繼點、終點）
  final List<LatLng> _waypoints = [];

  // 備選路線
  List<RouteOption> _routes = [];
  int _routeIdx = 0;

  // 採樣點天氣結果
  List<WaypointWeather> _waypointWeathers = [];

  // 目前選取的天氣點
  WaypointWeather? _selectedWeather;

  bool _loadingRoute = false;
  bool _loadingWeather = false;
  bool _weatherSlow = false; // 查詢超過 30 秒
  Timer? _slowTimer;
  String? _error;

  // ── 搜尋欄 ──
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  LatLng? _startPos;
  LatLng? _endPos;
  bool _searchExpanded = true;
  bool _geocoding = false;
  bool _suggestForStart = true;
  List<_PlaceSuggestion> _suggestions = [];
  Timer? _debounce;

  // ── 騎行設定 ──
  double _speedKmh = 45.0;
  DateTime _departureTime = DateTime.now();
  double _sampleIntervalKm = 5.0;
  LabelMode _labelMode = LabelMode.km;

  // ── GPS 定位 ──
  LatLng? _myLocation;

  // ── 導航狀態 ──
  bool _navigating = false;
  StreamSubscription<Position>? _navSub;
  List<double> _navCumKm = [];
  List<double> _navStepKm = [];
  int _navStepIdx = 0;
  double _navToNextM = 0;
  double _navRemainKm = 0;

  @override
  void initState() {
    super.initState();
    _locateMe();
  }

  @override
  void dispose() {
    _navSub?.cancel();
    _debounce?.cancel();
    _slowTimer?.cancel();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  // ── GPS 定位 ──────────────────────────────────────────────

  Future<void> _locateMe() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ));
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      if (!_navigating) _mapController.move(_myLocation!, 13);
    } catch (_) {}
  }

  // ── 地圖點選：新增路線點 ──────────────────────────────────

  void _onMapTap(TapPosition _, LatLng point) {
    if (_navigating) return;
    FocusScope.of(context).unfocus();
    setState(() {
      if (_waypoints.isEmpty) _departureTime = DateTime.now();
      _waypoints.add(point);
      _routes = [];
      _routeIdx = 0;
      _waypointWeathers = [];
      _selectedWeather = null;
      _error = null;
      _suggestions = [];
    });
    if (_waypoints.length >= 2) _fetchRoute();
  }

  // ── 清除 / 撤銷 ──────────────────────────────────────────

  void _clearRoute() {
    setState(() {
      _waypoints.clear();
      _routes = [];
      _routeIdx = 0;
      _waypointWeathers = [];
      _selectedWeather = null;
      _error = null;
      _startPos = null;
      _endPos = null;
      _suggestions = [];
    });
  }

  void _undoWaypoint() {
    if (_waypoints.isEmpty) return;
    _removeWaypoint(_waypoints.length - 1);
  }

  /// 刪除指定標點（點擊地圖上的標點觸發，可移除誤觸的點）
  void _removeWaypoint(int index) {
    if (index < 0 || index >= _waypoints.length) return;
    setState(() {
      _waypoints.removeAt(index);
      _routes = [];
      _routeIdx = 0;
      _waypointWeathers = [];
      _selectedWeather = null;
    });
    if (_waypoints.length >= 2) _fetchRoute();
  }

  void _confirmRemoveWaypoint(int index) {
    if (_navigating) return;
    if (index < 0 || index >= _waypoints.length) return;
    final isFirst = index == 0;
    final isLast = index == _waypoints.length - 1;
    final label = isFirst
        ? LanguageService.t('origin')
        : isLast
            ? LanguageService.t('destination')
            : '${LanguageService.t('route_label')} $index';
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(LanguageService.t('delete_marker')),
        content: Text(LanguageService.tp('del_marker_confirm', {'x': label})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(LanguageService.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _removeWaypoint(index);
            },
            child: Text(LanguageService.t('delete')),
          ),
        ],
      ),
    );
  }

  // ── 路線規劃 ─────────────────────────────────────────────

  Future<void> _fetchRoute() async {
    setState(() {
      _loadingRoute = true;
      _error = null;
    });
    final routes = await RoutingService.getRoutes(_waypoints);
    if (!mounted) return;
    if (routes.isEmpty) {
      setState(() {
        _loadingRoute = false;
        _error = LanguageService.t('msg_no_route');
      });
      return;
    }
    setState(() {
      _routes = routes;
      _routeIdx = 0;
      _loadingRoute = false;
      _searchExpanded = false;
    });
    await _fetchWeather(routes.first);
  }

  void _selectRoute(int i) {
    if (i == _routeIdx || i >= _routes.length) return;
    setState(() {
      _routeIdx = i;
      _selectedWeather = null;
    });
    _fetchWeather(_routes[i]);
  }

  // ── 天氣查詢 ─────────────────────────────────────────────

  Future<void> _fetchWeather(RouteOption routeOpt) async {
    _slowTimer?.cancel();
    setState(() {
      _loadingWeather = true;
      _weatherSlow = false;
      _waypointWeathers = [];
    });
    // 查詢超過 30 秒仍未完成 → 提示節點偏多
    _slowTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _loadingWeather) {
        setState(() => _weatherSlow = true);
      }
    });
    final route = routeOpt.points;
    final samples = RoutingService.sampleRoute(route, _sampleIntervalKm);
    final totalKm = RoutingService.totalDistance(route);

    // 道路名模式：預先計算每個轉彎點的累積距離
    List<double>? stepKm;
    if (_labelMode == LabelMode.road && routeOpt.steps.isNotEmpty) {
      final cum = RoutingService.cumulativeKm(route);
      stepKm = routeOpt.steps
          .map((s) => cum[RoutingService.nearestIndex(route, s.location)])
          .toList();
    }

    final results = <WaypointWeather>[];

    for (final s in samples) {
      final eta = _departureTime.add(
        Duration(minutes: (s.distanceKm / _speedKmh * 60).round()),
      );
      final label = await _sampleLabel(s, totalKm, routeOpt, stepKm);

      final weather =
          await fetchHourAt(s.point.latitude, s.point.longitude, eta);
      if (!mounted) return;
      if (weather != null) {
        results.add(WaypointWeather(
          lat: s.point.latitude,
          lng: s.point.longitude,
          label: label,
          distanceKm: s.distanceKm,
          eta: eta,
          weather: weather,
        ));
      }
    }

    _slowTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _waypointWeathers = results;
      _loadingWeather = false;
      _weatherSlow = false;
      if (results.isNotEmpty) _selectedWeather = results.first;
    });
  }

  /// 依設定的標示模式產生採樣點名稱
  Future<String> _sampleLabel(
    ({LatLng point, double distanceKm}) s,
    double totalKm,
    RouteOption routeOpt,
    List<double>? stepKm,
  ) async {
    if (s.distanceKm < 1) return LanguageService.t('origin');
    if (s.distanceKm >= totalKm - 0.5) return LanguageService.t('destination');
    final fallback = 'km ${s.distanceKm.round()}';

    switch (_labelMode) {
      case LabelMode.km:
        return fallback;

      case LabelMode.road:
        if (stepKm != null) {
          String name = '';
          for (int i = 0; i < stepKm.length; i++) {
            if (stepKm[i] > s.distanceKm) break;
            if (routeOpt.steps[i].roadName.isNotEmpty) {
              name = routeOpt.steps[i].roadName;
            }
          }
          if (name.isNotEmpty) {
            return '$name ${s.distanceKm.toStringAsFixed(1)}k';
          }
        }
        return fallback;

      case LabelMode.district:
        final d = await _reverseDistrict(s.point);
        return d ?? fallback;
    }
  }

  /// 反查行政區（BigDataCloud 免費、無金鑰）
  Future<String?> _reverseDistrict(LatLng p) async {
    try {
      final resp = await http.get(Uri.parse(
          'https://api.bigdatacloud.net/data/reverse-geocode-client'
          '?latitude=${p.latitude}&longitude=${p.longitude}'
          '&localityLanguage=zh-Hant'));
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final locality = (j['locality'] as String?)?.trim() ?? '';
      final city = (j['city'] as String?)?.trim() ?? '';
      if (locality.isNotEmpty) return locality;
      if (city.isNotEmpty) return city;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── 地點搜尋（自動補全）──────────────────────────────────

  void _onQueryChanged(String q, bool forStart) {
    _suggestForStart = forStart;
    if (forStart) {
      _startPos = null;
    } else {
      _endPos = null;
    }
    _debounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _fetchSuggestions(query, forStart));
  }

  Future<void> _fetchSuggestions(String q, bool forStart) async {
    try {
      final resp = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(q)}'
            '&format=json&limit=5&accept-language=zh-TW&countrycodes=tw'),
        headers: {'User-Agent': 'rIdIng-app/1.0'},
      );
      if (!mounted || resp.statusCode != 200) return;
      final list = jsonDecode(resp.body) as List;
      setState(() {
        _suggestions = list
            .map((r) => _PlaceSuggestion(
                  name: ((r['display_name'] as String?) ?? '')
                      .split(',')
                      .first
                      .trim(),
                  displayName: (r['display_name'] as String?) ?? '',
                  pos: LatLng(double.parse(r['lat'] as String),
                      double.parse(r['lon'] as String)),
                ))
            .toList();
      });
    } catch (_) {}
  }

  void _pickSuggestion(_PlaceSuggestion s) {
    setState(() {
      if (_suggestForStart) {
        _startCtrl.text = s.name;
        _startPos = s.pos;
      } else {
        _endCtrl.text = s.name;
        _endPos = s.pos;
      }
      _suggestions = [];
    });
  }

  void _useMyLocationAsStart() async {
    if (_myLocation == null) await _locateMe();
    if (_myLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('msg_no_gps'))));
      }
      return;
    }
    setState(() {
      _startCtrl.text = LanguageService.t('my_location');
      _startPos = _myLocation;
      _suggestions = [];
    });
  }

  Future<LatLng?> _geocodeAddress(String query) async {
    try {
      final resp = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(query)}'
            '&format=json&limit=1&accept-language=zh-TW&countrycodes=tw'),
        headers: {'User-Agent': 'rIdIng-app/1.0'},
      );
      if (resp.statusCode != 200) return null;
      final list = jsonDecode(resp.body) as List;
      if (list.isEmpty) return null;
      final r = list.first as Map;
      return LatLng(double.parse(r['lat'] as String),
          double.parse(r['lon'] as String));
    } catch (_) {
      return null;
    }
  }

  Future<void> _searchRoute() async {
    FocusScope.of(context).unfocus();
    final sText = _startCtrl.text.trim();
    final eText = _endCtrl.text.trim();
    if ((sText.isEmpty && _startPos == null) ||
        (eText.isEmpty && _endPos == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('msg_enter_both'))));
      return;
    }
    setState(() => _geocoding = true);
    final sp = _startPos ?? await _geocodeAddress(sText);
    final ep = _endPos ?? await _geocodeAddress(eText);
    if (!mounted) return;
    if (sp == null || ep == null) {
      setState(() => _geocoding = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sp == null
              ? '${LanguageService.t('msg_start_nf')}: $sText'
              : '${LanguageService.t('msg_end_nf')}: $eText')));
      return;
    }
    _startPos = sp;
    _endPos = ep;
    setState(() {
      _geocoding = false;
      if (_departureTime.isBefore(DateTime.now())) {
        _departureTime = DateTime.now();
      }
      _waypoints
        ..clear()
        ..add(sp)
        ..add(ep);
      _routes = [];
      _routeIdx = 0;
      _waypointWeathers = [];
      _selectedWeather = null;
      _error = null;
      _suggestions = [];
    });
    _mapController.move(
      LatLng((sp.latitude + ep.latitude) / 2,
          (sp.longitude + ep.longitude) / 2),
      10,
    );
    await _fetchRoute();
  }

  // ── GPX 匯入 ─────────────────────────────────────────────

  Future<void> _importGpx() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final points = GpxService.parse(file);

    if (points.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('gpx_fail'))),
        );
      }
      return;
    }

    // GPX 點抽稀（每 0.5km 保留一點，避免 OSRM 請求過大）
    final decimated = GpxService.decimate(points, 0.5);

    setState(() {
      _waypoints
        ..clear()
        ..addAll(decimated);
      _routes = [];
      _routeIdx = 0;
      _waypointWeathers = [];
      _selectedWeather = null;
      _error = null;
    });

    if (decimated.isNotEmpty) {
      _mapController.move(decimated[decimated.length ~/ 2], 11);
    }

    // GPX 點太多時直接用原始點當路線，不再呼叫 OSRM
    if (decimated.length > 100) {
      final synthetic = RouteOption(
        points: decimated,
        distanceKm: RoutingService.totalDistance(decimated),
        durationMin: 0,
        steps: const [],
      );
      setState(() {
        _routes = [synthetic];
        _routeIdx = 0;
        _searchExpanded = false;
      });
      await _fetchWeather(synthetic);
    } else {
      await _fetchRoute();
    }
  }

  // ── 騎行設定 ─────────────────────────────────────────────

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SettingsSheet(
        speed: _speedKmh,
        departure: _departureTime,
        interval: _sampleIntervalKm,
        labelMode: _labelMode,
        onChanged: (speed, departure, interval, labelMode) {
          setState(() {
            _speedKmh = speed;
            _departureTime = departure;
            _sampleIntervalKm = interval;
            _labelMode = labelMode;
          });
          if (_routes.isNotEmpty) _fetchWeather(_routes[_routeIdx]);
        },
      ),
    );
  }

  // ── 導航 ─────────────────────────────────────────────────

  Future<void> _startNavigation() async {
    if (_routes.isEmpty) return;
    final route = _routes[_routeIdx];
    if (route.steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('msg_no_steps'))));
      return;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(LanguageService.t('msg_need_loc_perm'))));
      }
      return;
    }
    if (!mounted) return;

    _navCumKm = RoutingService.cumulativeKm(route.points);
    _navStepKm = route.steps
        .map((s) =>
            _navCumKm[RoutingService.nearestIndex(route.points, s.location)])
        .toList();

    setState(() {
      _navigating = true;
      _navStepIdx = 0;
      _navToNextM = 0;
      _navRemainKm = route.distanceKm;
      _selectedWeather = null;
      _searchExpanded = false;
    });

    _navSub?.cancel();
    _navSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen(_onNavPosition);

    final startAt = _myLocation ?? route.points.first;
    _mapController.move(startAt, 16.5);
  }

  void _onNavPosition(Position pos) {
    if (!mounted || !_navigating || _routes.isEmpty) return;
    final p = LatLng(pos.latitude, pos.longitude);
    final route = _routes[_routeIdx];
    final idx = RoutingService.nearestIndex(route.points, p);
    final curKm = _navCumKm[idx];
    final totalKm = _navCumKm.last;

    int stepIdx = _navStepIdx;
    while (stepIdx < route.steps.length - 1 &&
        _navStepKm[stepIdx] <= curKm + 0.01) {
      stepIdx++;
    }

    final remain = math.max(0.0, totalKm - curKm);
    final toNext = math.max(0.0, (_navStepKm[stepIdx] - curKm) * 1000);
    setState(() {
      _myLocation = p;
      _navStepIdx = stepIdx;
      _navToNextM = toNext;
      _navRemainKm = remain;
    });
    _mapController.move(p, math.max(_mapController.camera.zoom, 15.5));

    if (remain < 0.03) _stopNavigation(arrived: true);
  }

  void _stopNavigation({bool arrived = false}) {
    _navSub?.cancel();
    _navSub = null;
    if (!mounted) return;
    setState(() => _navigating = false);
    if (arrived) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('msg_arrived'))));
    }
  }

  // ── 小工具 ───────────────────────────────────────────────

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _durText(double minutes) {
    final m = minutes.round();
    if (m < 60) return '$m 分鐘';
    return '${m ~/ 60} 小時 ${m % 60} 分';
  }

  double _rideMinutes(RouteOption r) => r.distanceKm / _speedKmh * 60;

  // ════════════════════════════════════════════════════════════
  // 建構 UI
  // ════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheetVisible = _routes.isNotEmpty && !_navigating;

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('路線天氣')),
      body: Stack(
        children: [
          // ── 地圖 ──────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation ?? const LatLng(23.97, 120.97),
              initialZoom: _myLocation != null ? 13 : 8,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.riding.app',
              ),

              // 備選路線（未選取：灰色，選取：主色）
              if (_routes.isNotEmpty)
                PolylineLayer(polylines: [
                  for (int i = 0; i < _routes.length; i++)
                    if (i != _routeIdx)
                      Polyline(
                        points: _routes[i].points,
                        strokeWidth: 4,
                        color: Colors.grey.withOpacity(0.55),
                      ),
                  Polyline(
                    points: _routes[_routeIdx].points,
                    strokeWidth: 5,
                    color: theme.colorScheme.primary.withOpacity(0.9),
                  ),
                ]),

              MarkerLayer(
                markers: [
                  // GPS 位置
                  if (_myLocation != null)
                    Marker(
                      key: const ValueKey('gps'),
                      point: _myLocation!,
                      width: 20,
                      height: 20,
                      child: RepaintBoundary(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ),

                  // 使用者點選的路線點
                  ..._waypoints.asMap().entries.map((e) {
                    final isFirst = e.key == 0;
                    final isLast = e.key == _waypoints.length - 1;
                    return Marker(
                      key: ValueKey('wp_${e.key}'),
                      point: e.value,
                      width: 36,
                      height: 36,
                      child: RepaintBoundary(
                        child: GestureDetector(
                          // 點擊標點 → 詢問是否刪除（移除誤觸的點）
                          onTap: () => _confirmRemoveWaypoint(e.key),
                          behavior: HitTestBehavior.opaque,
                          child: Icon(
                            isFirst
                                ? Icons.trip_origin
                                : isLast
                                    ? Icons.place
                                    : Icons.circle,
                            color: isFirst
                                ? Colors.green
                                : isLast
                                    ? Colors.red
                                    : Colors.orange,
                            size: isFirst || isLast ? 28 : 16,
                          ),
                        ),
                      ),
                    );
                  }),

                  // 天氣採樣點
                  if (!_navigating)
                    ..._waypointWeathers.asMap().entries.map((e) {
                      final w = e.value;
                      return Marker(
                        key: ValueKey('ww_${e.key}'),
                        point: LatLng(w.lat, w.lng),
                        width: 56,
                        height: 56,
                        child: RepaintBoundary(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedWeather = w),
                            child: _WeatherDot(
                                w: w, selected: _selectedWeather == w),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ],
          ),

          // ── 頂部：搜尋欄 + 載入/錯誤提示 ──────────────────
          if (!_navigating)
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  _buildSearchCard(theme),
                  if (_loadingRoute || _loadingWeather) ...[
                    const SizedBox(height: 8),
                    _InfoChip(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                          const SizedBox(width: 10),
                          Text(
                            _loadingRoute
                                ? LanguageService.t('planning_route')
                                : _weatherSlow
                                    ? LanguageService.t('many_nodes')
                                    : LanguageService.t('querying_weather'),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // ── 導航中：頂部指示橫幅 ──────────────────────────
          if (_navigating) _buildNavBanner(theme),

          // ── 導航中：底部資訊列 ────────────────────────────
          if (_navigating) _buildNavBottomBar(theme),

          // ── GPS 按鈕 ──────────────────────────────────────
          Positioned(
            bottom: _navigating
                ? 96
                : sheetVisible
                    ? MediaQuery.of(context).size.height * 0.15 + 12
                    : 16,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'gps',
              onPressed: _locateMe,
              child: const Icon(Icons.my_location),
            ),
          ),

          // ── 底部：可拉起的路線/天氣面板 ───────────────────
          if (sheetVisible)
            DraggableScrollableSheet(
              minChildSize: 0.14,
              initialChildSize: 0.38,
              maxChildSize: 0.88,
              snap: true,
              snapSizes: const [0.38],
              builder: (context, scrollCtrl) =>
                  _buildSheet(theme, scrollCtrl),
            ),
        ],
      ),
    );
  }

  // ── 搜尋卡片 ─────────────────────────────────────────────

  Widget _buildSearchCard(ThemeData theme) {
    final cs = theme.colorScheme;
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: _searchExpanded
            ? _buildSearchExpanded(theme)
            : InkWell(
                onTap: () => setState(() => _searchExpanded = true),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _startCtrl.text.isEmpty && _endCtrl.text.isEmpty
                              ? LanguageService.t('search_collapsed_hint')
                              : '${_startCtrl.text.isEmpty ? LanguageService.t('map_start') : _startCtrl.text}'
                                  ' → '
                                  '${_endCtrl.text.isEmpty ? LanguageService.t('map_end') : _endCtrl.text}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14, color: cs.onSurfaceVariant),
                        ),
                      ),
                      Icon(Icons.expand_more, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSearchExpanded(ThemeData theme) {
    final cs = theme.colorScheme;
    return ConstrainedBox(
      // 限制高度避免小螢幕/鍵盤開啟時 overflow，超出改為捲動
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.62),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標題列
          Row(
            children: [
              Icon(Icons.directions_bike, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(LanguageService.t('route_planning'),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_waypoints.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.undo, size: 20),
                  tooltip: LanguageService.t('undo_point'),
                  visualDensity: VisualDensity.compact,
                  onPressed: _undoWaypoint,
                ),
              IconButton(
                icon: const Icon(Icons.expand_less),
                tooltip: LanguageService.t('close'),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _searchExpanded = false;
                  _suggestions = [];
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 起點輸入
          TextField(
            controller: _startCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.trip_origin, color: Colors.green),
              suffixIcon: IconButton(
                icon: const Icon(Icons.my_location, size: 20),
                tooltip: LanguageService.t('current_loc'),
                onPressed: _useMyLocationAsStart,
              ),
              labelText: LanguageService.t('origin'),
              hintText: LanguageService.t('addr_hint'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            onChanged: (v) => _onQueryChanged(v, true),
            onTap: () => _suggestForStart = true,
          ),
          const SizedBox(height: 8),

          // 終點輸入
          TextField(
            controller: _endCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.place, color: Colors.red),
              labelText: LanguageService.t('destination'),
              hintText: LanguageService.t('addr_hint'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.search,
            onChanged: (v) => _onQueryChanged(v, false),
            onTap: () => _suggestForStart = false,
            onSubmitted: (_) => _searchRoute(),
          ),

          // 自動補全下拉建議
          if (_suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _suggestions.length,
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.place_outlined,
                        size: 20, color: cs.primary),
                    title: Text(s.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(s.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                    onTap: () => _pickSuggestion(s),
                  );
                },
              ),
            ),
          const SizedBox(height: 10),

          // 騎行設定（位於輸入框下方）+ GPX + 清除
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(
                    '${LanguageService.t('ride_settings')}　${_speedKmh.round()} km/h・${_hm(_departureTime)} ${LanguageService.t('depart')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _showSettings,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.upload_file),
                tooltip: LanguageService.t('import_gpx'),
                onPressed: _importGpx,
              ),
              if (_waypoints.isNotEmpty || _routes.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: LanguageService.t('clear_route'),
                  onPressed: _clearRoute,
                ),
            ],
          ),
          const SizedBox(height: 8),

          // 搜尋按鈕
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _geocoding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search),
              label: Text(_geocoding
                  ? LanguageService.t('searching')
                  : LanguageService.t('search_route')),
              onPressed: _geocoding ? null : _searchRoute,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            LanguageService.t('map_tap_hint'),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
        ),
      ),
    );
  }

  // ── 底部面板（可拉起）────────────────────────────────────

  Widget _buildSheet(ThemeData theme, ScrollController scrollCtrl) {
    final cs = theme.colorScheme;
    final route = _routes[_routeIdx];
    final rideMin = _rideMinutes(route);
    final arrival = _departureTime.add(Duration(minutes: rideMin.round()));
    final sel = _selectedWeather;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 16,
              offset: const Offset(0, -4))
        ],
      ),
      child: ListView(
        controller: scrollCtrl,
        padding: EdgeInsets.zero,
        children: [
          // 拖曳把手
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),

          // 備選路線切換
          if (_routes.length > 1)
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _routes.length,
                itemBuilder: (_, i) {
                  final r = _routes[i];
                  final selected = i == _routeIdx;
                  return GestureDetector(
                    onTap: () => _selectRoute(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8, bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                selected ? cs.primary : Colors.transparent,
                            width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${LanguageService.t('route_label')} ${i + 1}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: selected
                                      ? cs.onPrimaryContainer
                                      : cs.onSurface)),
                          Text(
                            '${r.distanceKm.toStringAsFixed(1)} km・'
                            '約 ${_durText(_rideMinutes(r))}',
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // 全程資訊 + 導航按鈕
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${LanguageService.t('total')} ${route.distanceKm.toStringAsFixed(1)} km・'
                        '${LanguageService.t('ride_time')} ${_durText(rideMin)}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${LanguageService.t('depart')} ${_hm(_departureTime)}・'
                        '${LanguageService.t('arrive')} ${_hm(arrival)}',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.navigation, size: 18),
                  label: Text(LanguageService.t('nav')),
                  onPressed: _startNavigation,
                ),
              ],
            ),
          ),

          // 選取採樣點的天氣詳情
          if (sel != null) ...[
            const Divider(height: 16, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(weatherIcon(sel.weather.weatherCode),
                      color: weatherColor(sel.weather.weatherCode), size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${sel.label}　${LanguageService.t('arrive')} ${_hm(sel.eta)}',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${weatherLabel(sel.weather.weatherCode)}　'
                          '${sel.weather.temp.toStringAsFixed(1)}°C',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 風速 / 降雨明確顯示
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.air, size: 18, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${LanguageService.t('wind')} ${sel.weather.windSpeed.round()} km/h\n'
                              '${windDirText(sel.weather.windDir)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Transform.rotate(
                            // 風向為來向，箭頭指向風的去向
                            angle:
                                (sel.weather.windDir + 180) * math.pi / 180,
                            child: Icon(Icons.navigation,
                                size: 16, color: cs.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.water_drop_outlined,
                              size: 18, color: Colors.blue),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${LanguageService.t('rain_prob')}\n${sel.weather.precipProb}%',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 水平捲動：各採樣點
          if (_waypointWeathers.isNotEmpty)
            SizedBox(
              height: 96,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _waypointWeathers.length,
                itemBuilder: (_, i) {
                  final wp = _waypointWeathers[i];
                  final isSelected = wp == sel;
                  final c = weatherColor(wp.weather.weatherCode);
                  return GestureDetector(
                    onTap: () => setState(() => _selectedWeather = wp),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? c.withOpacity(0.18)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isSelected ? c : Colors.transparent,
                            width: 2),
                      ),
                      // FittedBox 防止字體放大時 bottom overflow 遮住天氣圖示
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(weatherIcon(wp.weather.weatherCode),
                                color: c, size: 20),
                            const SizedBox(height: 2),
                            Text(
                              '${wp.weather.temp.round()}°',
                              style: TextStyle(
                                  color: c,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                            ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 96),
                              child: Text(
                                wp.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // 騎行警示
          if (sel != null && ridingAlerts(sel.weather).isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: ridingAlerts(sel.weather)
                    .map((a) => Chip(
                          label: Text(a,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onTertiaryContainer)),
                          backgroundColor: cs.tertiaryContainer,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ),

          // 騎行防護建議（永遠顯示）
          if (sel != null) ...[
            const Divider(height: 20, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.health_and_safety,
                      size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(LanguageService.t('protection'),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ...ridingAdvice(sel.weather).map((a) => Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(a.icon, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(a.text,
                            style: TextStyle(
                                fontSize: 12.5, color: cs.onSurface)),
                      ),
                    ],
                  ),
                )),
          ],

          // 各採樣點詳情（拉起後可見）
          if (_waypointWeathers.isNotEmpty) ...[
            const Divider(height: 20, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(LanguageService.t('sample_details'),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            ..._waypointWeathers.map((wp) => ListTile(
                  dense: true,
                  leading: Icon(weatherIcon(wp.weather.weatherCode),
                      color: weatherColor(wp.weather.weatherCode)),
                  title: Text(
                      '${wp.label}　${LanguageService.t('arrive')} ${_hm(wp.eta)}',
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    '${weatherLabel(wp.weather.weatherCode)}　'
                    '${wp.weather.temp.toStringAsFixed(1)}°C　'
                    '${LanguageService.t('wind')} ${wp.weather.windSpeed.round()} km/h（${windDirText(wp.weather.windDir)}）　'
                    '${LanguageService.t('rain')} ${wp.weather.precipProb}%',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  selected: wp == sel,
                  onTap: () {
                    setState(() => _selectedWeather = wp);
                    _mapController.move(LatLng(wp.lat, wp.lng), 13);
                  },
                )),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  // ── 導航橫幅 ─────────────────────────────────────────────

  Widget _buildNavBanner(ThemeData theme) {
    final cs = theme.colorScheme;
    final route = _routes.isEmpty ? null : _routes[_routeIdx];
    if (route == null || route.steps.isEmpty) return const SizedBox.shrink();
    final stepIdx =
        _navStepIdx < route.steps.length ? _navStepIdx : route.steps.length - 1;
    final step = route.steps[stepIdx];
    final distText = _navToNextM >= 1000
        ? '${(_navToNextM / 1000).toStringAsFixed(1)} km'
        : '${_navToNextM.round()} m';

    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: Card(
        elevation: 6,
        color: cs.primaryContainer,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                RoutingService.maneuverIcon(step.type, step.modifier),
                size: 38,
                color: cs.onPrimaryContainer,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(distText,
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer)),
                    Text(
                      step.instruction,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14, color: cs.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavBottomBar(ThemeData theme) {
    final cs = theme.colorScheme;
    final remainMin = _navRemainKm / _speedKmh * 60;
    final eta = DateTime.now().add(Duration(minutes: remainMin.round()));

    return Positioned(
      bottom: 16,
      left: 12,
      right: 12,
      child: Card(
        elevation: 6,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${LanguageService.t('remaining')} ${_navRemainKm.toStringAsFixed(1)} km・'
                      '${LanguageService.t('ride_time')} ${_durText(remainMin)}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text('${LanguageService.t('arrive')} ${_hm(eta)}',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.close, size: 18),
                label: Text(LanguageService.t('end_nav')),
                onPressed: () => _stopNavigation(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 地點搜尋建議
// ════════════════════════════════════════════════════════════

class _PlaceSuggestion {
  final String name;
  final String displayName;
  final LatLng pos;

  const _PlaceSuggestion({
    required this.name,
    required this.displayName,
    required this.pos,
  });
}

// ════════════════════════════════════════════════════════════
// 黑底提示小卡
// ════════════════════════════════════════════════════════════

class _InfoChip extends StatelessWidget {
  final Widget child;
  const _InfoChip({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

// ════════════════════════════════════════════════════════════
// 天氣圓點標記
// ════════════════════════════════════════════════════════════

class _WeatherDot extends StatelessWidget {
  final WaypointWeather w;
  final bool selected;

  const _WeatherDot({required this.w, required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = weatherColor(w.weather.weatherCode);
    return Container(
      decoration: BoxDecoration(
        color: selected ? color : color.withOpacity(0.85),
        shape: BoxShape.circle,
        border: Border.all(
            color: selected ? Colors.white : Colors.white70,
            width: selected ? 3 : 1.5),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: selected ? 8 : 4,
              spreadRadius: selected ? 2 : 0)
        ],
      ),
      // FittedBox 防止字體放大時溢出，確保天氣圖示完整可見
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(weatherIcon(w.weather.weatherCode),
                  color: Colors.white, size: 18),
              Text(
                '${w.weather.temp.round()}°',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 騎行設定底部表單
// ════════════════════════════════════════════════════════════

class _SettingsSheet extends StatefulWidget {
  final double speed;
  final DateTime departure;
  final double interval;
  final LabelMode labelMode;
  final void Function(double speed, DateTime departure, double interval,
      LabelMode labelMode) onChanged;

  const _SettingsSheet({
    required this.speed,
    required this.departure,
    required this.interval,
    required this.labelMode,
    required this.onChanged,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late double _speed;
  late DateTime _departure;
  late double _interval;
  late LabelMode _labelMode;
  late TextEditingController _speedCtrl;

  @override
  void initState() {
    super.initState();
    _speed = widget.speed;
    _departure = widget.departure;
    _interval = widget.interval;
    _labelMode = widget.labelMode;
    _speedCtrl = TextEditingController(text: _speed.round().toString());
  }

  @override
  void dispose() {
    _speedCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departure),
    );
    if (picked != null) {
      setState(() {
        _departure = DateTime(
          _departure.year, _departure.month, _departure.day,
          picked.hour, picked.minute,
        );
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _departure,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (picked != null) {
      setState(() {
        _departure = DateTime(
          picked.year, picked.month, picked.day,
          _departure.hour, _departure.minute,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(LanguageService.t('ride_settings'),
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),

          // 出發日期時間
          Text(LanguageService.t('departure_time'),
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                      '${_departure.month}/${_departure.day}'),
                  onPressed: _pickDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time, size: 16),
                  label: Text(
                      '${_departure.hour.toString().padLeft(2, '0')}:'
                      '${_departure.minute.toString().padLeft(2, '0')}'),
                  onPressed: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 平均速度
          Text(LanguageService.t('avg_speed'),
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _speedCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              suffixText: 'km/h',
              border: OutlineInputBorder(),
              isDense: true,
              hintText: '例：45',
            ),
            onChanged: (v) {
              final parsed = double.tryParse(v);
              if (parsed != null && parsed >= 1 && parsed <= 120) {
                setState(() => _speed = parsed);
              }
            },
          ),

          // 採樣間距
          Row(
            children: [
              Text(LanguageService.t('sample_interval'),
                  style: theme.textTheme.labelLarge),
              const Spacer(),
              Text('每 ${_interval.round()} km',
                  style: theme.textTheme.bodyMedium),
            ],
          ),
          Slider(
            value: _interval,
            min: 2,
            max: 30,
            divisions: 14,
            label: '每 ${_interval.round()} km',
            onChanged: (v) => setState(() => _interval = v),
          ),
          const SizedBox(height: 8),

          // 採樣點標示方式
          Text(LanguageService.t('sample_label_mode'),
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<LabelMode>(
              segments: [
                ButtonSegment(
                    value: LabelMode.km,
                    label: Text(LanguageService.t('mode_dist'))),
                ButtonSegment(
                    value: LabelMode.road,
                    label: Text(LanguageService.t('mode_road'))),
                ButtonSegment(
                    value: LabelMode.district,
                    label: Text(LanguageService.t('mode_district'))),
              ],
              selected: {_labelMode},
              onSelectionChanged: (s) =>
                  setState(() => _labelMode = s.first),
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                widget.onChanged(_speed, _departure, _interval, _labelMode);
                Navigator.pop(context);
              },
              child: Text(LanguageService.t('apply')),
            ),
          ),
        ],
      ),
    );
  }
}
