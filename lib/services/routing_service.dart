import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../api_client.dart';
import 'language_service.dart';

// ════════════════════════════════════════════════════════════
// 路線規劃服務（OSRM）
// ════════════════════════════════════════════════════════════

/// 單一轉彎指示
class RouteStep {
  final String instruction; // 中文指示文字，如「左轉進入 中山路」
  final String type;        // OSRM maneuver type
  final String modifier;    // OSRM maneuver modifier
  final double distanceM;   // 此步驟長度（公尺）
  final LatLng location;    // 轉彎點座標
  final String roadName;    // 道路名稱

  const RouteStep({
    required this.instruction,
    required this.type,
    required this.modifier,
    required this.distanceM,
    required this.location,
    required this.roadName,
  });
}

/// 一條完整的備選路線
class RouteOption {
  final List<LatLng> points;   // 完整路線幾何
  final double distanceKm;     // OSRM 回傳的總距離
  final double durationMin;    // OSRM 回傳的行車時間（參考用）
  final List<RouteStep> steps; // 轉彎指示

  const RouteOption({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
    required this.steps,
  });
}

class RoutingService {
  // 距離計算器：roundResult 必須為 false，
  // 否則每段距離會被四捨五入成整數 km（短段全變 0，造成總距離過短、採樣點丟失）
  static const Distance _dist = Distance(roundResult: false);

  /// 查詢路線（含備選路線與轉彎指示）。
  /// 只有起點+終點（無中繼點）時才會要求備選路線。
  /// 失敗時回傳空 List。
  static Future<List<RouteOption>> getRoutes(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return [];
    final coords =
        waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    final wantAlternatives = waypoints.length == 2;
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$coords'
      '?overview=full&geometries=geojson&steps=true'
      '${wantAlternatives ? '&alternatives=true' : ''}',
    );
    try {
      final res = await ApiClient.get(url).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      if (data['code'] != 'Ok') return [];
      final routes = data['routes'] as List;
      final options = <RouteOption>[];
      for (final r in routes) {
        final coords2 = r['geometry']['coordinates'] as List;
        final pts = coords2
            .map((c) =>
                LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        final steps = <RouteStep>[];
        for (final leg in (r['legs'] as List)) {
          for (final st in (leg['steps'] as List? ?? [])) {
            final man = st['maneuver'] as Map? ?? {};
            final loc = man['location'] as List? ?? [0, 0];
            final type = man['type'] as String? ?? '';
            final modifier = man['modifier'] as String? ?? '';
            final name = st['name'] as String? ?? '';
            steps.add(RouteStep(
              instruction: instructionText(type, modifier, name),
              type: type,
              modifier: modifier,
              distanceM: (st['distance'] as num? ?? 0).toDouble(),
              location: LatLng(
                  (loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
              roadName: name,
            ));
          }
        }
        options.add(RouteOption(
          points: pts,
          distanceKm: (r['distance'] as num).toDouble() / 1000,
          durationMin: (r['duration'] as num).toDouble() / 60,
          steps: steps,
        ));
      }
      return options;
    } catch (e) {
      debugPrint('OSRM 錯誤：$e');
      return [];
    }
  }

  /// 舊版 API：只回傳第一條路線的幾何（保留相容）
  static Future<List<LatLng>?> getRoute(List<LatLng> waypoints) async {
    final options = await getRoutes(waypoints);
    if (options.isEmpty) return null;
    return options.first.points;
  }

  /// OSRM maneuver → 指示文字（依語言顯示）
  static String instructionText(String type, String modifier, String road) {
    final t = LanguageService.t;
    final onto = road.isNotEmpty ? ' ${t('n_onto')} $road' : '';
    switch (type) {
      case 'depart':
        return road.isNotEmpty
            ? LanguageService.tp('n_depart_from', {'road': road})
            : t('n_depart');
      case 'arrive':
        return t('n_arrive');
      case 'roundabout':
      case 'rotary':
        return '${t('n_roundabout')}$onto';
      case 'exit roundabout':
      case 'exit rotary':
        return '${t('n_roundabout_exit')}$onto';
      case 'merge':
        return '${t('n_merge')}$onto';
      case 'on ramp':
        return '${t('n_ramp_on')}$onto';
      case 'off ramp':
        return '${t('n_ramp_off')}$onto';
      case 'fork':
        return '${_modifierText(modifier)} · ${t('n_fork')}$onto';
      case 'new name':
      case 'continue':
        return modifier == 'straight' || modifier.isEmpty
            ? '${t('n_straight_cont')}$onto'
            : '${_modifierText(modifier)}$onto';
      default:
        return '${_modifierText(modifier)}$onto';
    }
  }

  static String _modifierText(String modifier) {
    final t = LanguageService.t;
    switch (modifier) {
      case 'left':
        return t('m_left');
      case 'right':
        return t('m_right');
      case 'slight left':
        return t('m_slight_left');
      case 'slight right':
        return t('m_slight_right');
      case 'sharp left':
        return t('m_sharp_left');
      case 'sharp right':
        return t('m_sharp_right');
      case 'uturn':
        return t('m_uturn');
      case 'straight':
        return t('m_straight');
      default:
        return t('m_continue');
    }
  }

  /// maneuver → 圖示
  static IconData maneuverIcon(String type, String modifier) {
    if (type == 'arrive') return Icons.sports_score;
    if (type == 'depart') return Icons.trip_origin;
    if (type == 'roundabout' || type == 'rotary') return Icons.sync;
    if (type == 'merge') return Icons.merge;
    if (type == 'on ramp' || type == 'off ramp') return Icons.ramp_right;
    switch (modifier) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'sharp left':
        return Icons.turn_sharp_left;
      case 'sharp right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      default:
        return Icons.straight;
    }
  }

  /// 沿路線每隔 [intervalKm] 公里採樣一個座標點。
  /// 第一個點（起點）和最後一個點（終點）一定包含。
  static List<({LatLng point, double distanceKm})> sampleRoute(
      List<LatLng> route, double intervalKm) {
    if (route.isEmpty) return [];
    final samples = <({LatLng point, double distanceKm})>[];
    double accumulated = 0;
    double nextSample = 0;

    samples.add((point: route.first, distanceKm: 0));

    for (int i = 1; i < route.length; i++) {
      // 不可用 distance.as(Kilometer)：會四捨五入成整數 km
      final seg = _dist.distance(route[i - 1], route[i]) / 1000.0;
      if (seg <= 0) continue;
      accumulated += seg;
      while (nextSample + intervalKm <= accumulated) {
        nextSample += intervalKm;
        // 線性插值找出精確的採樣點
        final ratio = (nextSample - (accumulated - seg)) / seg;
        final lat = route[i - 1].latitude +
            (route[i].latitude - route[i - 1].latitude) * ratio;
        final lng = route[i - 1].longitude +
            (route[i].longitude - route[i - 1].longitude) * ratio;
        samples.add((point: LatLng(lat, lng), distanceKm: nextSample));
      }
    }

    // 終點
    final totalKm = accumulated;
    if (samples.last.distanceKm < totalKm - 0.1) {
      samples.add((point: route.last, distanceKm: totalKm));
    }

    return samples;
  }

  /// 計算路線總長度（km）
  static double totalDistance(List<LatLng> route) {
    if (route.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < route.length; i++) {
      total += _dist.distance(route[i - 1], route[i]) / 1000.0;
    }
    return total;
  }

  /// 路線每個點的累積距離（km），供導航計算進度
  static List<double> cumulativeKm(List<LatLng> route) {
    final cum = <double>[0];
    for (int i = 1; i < route.length; i++) {
      cum.add(cum.last + _dist.distance(route[i - 1], route[i]) / 1000.0);
    }
    return cum;
  }

  /// 找出距離 [p] 最近的路線點 index
  static int nearestIndex(List<LatLng> route, LatLng p) {
    int best = 0;
    double bestD = double.infinity;
    for (int i = 0; i < route.length; i++) {
      final d = _dist.distance(route[i], p);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// 從兩點距離計算 Haversine（備用）
  static double haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(a.latitude)) *
            cos(_rad(b.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return 2 * r * asin(sqrt(h));
  }

  static double _rad(double deg) => deg * pi / 180;
}
