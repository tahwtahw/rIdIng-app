import 'dart:io';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

// ════════════════════════════════════════════════════════════
// GPX 解析服務
// ════════════════════════════════════════════════════════════

class GpxService {
  /// 解析 GPX 檔案，回傳座標序列。
  /// 支援 <trk>/<trkseg>/<trkpt> 和 <rte>/<rtept>。
  /// 失敗或空檔案時回傳空 list。
  static List<LatLng> parse(File file) {
    try {
      final content = file.readAsStringSync();
      return parseString(content);
    } catch (e) {
      return [];
    }
  }

  static List<LatLng> parseString(String content) {
    try {
      final doc = XmlDocument.parse(content);
      final points = <LatLng>[];

      // 優先讀取 track points
      final trkpts = doc.findAllElements('trkpt');
      if (trkpts.isNotEmpty) {
        for (final pt in trkpts) {
          final lat = double.tryParse(pt.getAttribute('lat') ?? '');
          final lng = double.tryParse(pt.getAttribute('lon') ?? '');
          if (lat != null && lng != null) {
            points.add(LatLng(lat, lng));
          }
        }
        return points;
      }

      // fallback：route points
      final rtepts = doc.findAllElements('rtept');
      for (final pt in rtepts) {
        final lat = double.tryParse(pt.getAttribute('lat') ?? '');
        final lng = double.tryParse(pt.getAttribute('lon') ?? '');
        if (lat != null && lng != null) {
          points.add(LatLng(lat, lng));
        }
      }
      return points;
    } catch (e) {
      return [];
    }
  }

  /// 抽稀：每 [intervalKm] 公里保留一個點，避免點太密集。
  /// 起點和終點一定保留。
  static List<LatLng> decimate(List<LatLng> points, double intervalKm) {
    if (points.length < 2) return points;
    const distance = Distance();
    final result = <LatLng>[points.first];
    double accumulated = 0;

    for (int i = 1; i < points.length; i++) {
      accumulated +=
          distance.as(LengthUnit.Kilometer, points[i - 1], points[i]);
      if (accumulated >= intervalKm) {
        result.add(points[i]);
        accumulated = 0;
      }
    }

    if (result.last != points.last) result.add(points.last);
    return result;
  }
}
