import 'dart:convert';
import 'package:flutter/material.dart';
import '../api_client.dart';
import 'language_service.dart';

// ════════════════════════════════════════════════════════════
// 資料模型
// ════════════════════════════════════════════════════════════

class HourWeather {
  final double temp;
  final int weatherCode;
  final double windSpeed;
  final double windDir; // 風向（度，風的來向）
  final int precipProb;
  final double precip;

  const HourWeather({
    required this.temp,
    required this.weatherCode,
    required this.windSpeed,
    this.windDir = 0,
    required this.precipProb,
    required this.precip,
  });
}

class DayForecast {
  final String date;
  final int weatherCode;
  final double tempMax;
  final double tempMin;
  final int precipProb;
  final double windMax;

  const DayForecast({
    required this.date,
    required this.weatherCode,
    required this.tempMax,
    required this.tempMin,
    required this.precipProb,
    required this.windMax,
  });
}

class PointWeather {
  final String locationName;
  final HourWeather current;
  final List<DayForecast> daily;

  const PointWeather({
    required this.locationName,
    required this.current,
    required this.daily,
  });
}

/// 路線上某個採樣點的天氣（含 ETA）
class WaypointWeather {
  final double lat;
  final double lng;
  final String label;         // 顯示名稱，如「km 45」
  final double distanceKm;    // 距起點距離
  final DateTime eta;         // 預計到達時間
  final HourWeather weather;

  const WaypointWeather({
    required this.lat,
    required this.lng,
    required this.label,
    required this.distanceKm,
    required this.eta,
    required this.weather,
  });
}

// ════════════════════════════════════════════════════════════
// 天氣代碼轉換
// ════════════════════════════════════════════════════════════

String weatherLabel(int code) {
  String k;
  if (code == 0) {
    k = 'w_clear';
  } else if (code <= 2) {
    k = 'w_cloudy';
  } else if (code == 3) {
    k = 'w_overcast';
  } else if (code <= 48) {
    k = 'w_fog';
  } else if (code <= 57) {
    k = 'w_drizzle';
  } else if (code <= 67) {
    k = 'w_rain';
  } else if (code <= 77) {
    k = 'w_snow';
  } else if (code <= 82) {
    k = 'w_shower';
  } else if (code <= 84) {
    k = 'w_hail';
  } else if (code <= 94) {
    k = 'w_storm';
  } else {
    k = 'w_storm2';
  }
  return LanguageService.t(k);
}

IconData weatherIcon(int code) {
  if (code == 0) return Icons.wb_sunny;
  if (code <= 2) return Icons.wb_cloudy;
  if (code == 3) return Icons.cloud;
  if (code <= 48) return Icons.foggy;
  if (code <= 67) return Icons.grain;
  if (code <= 77) return Icons.ac_unit;
  if (code <= 82) return Icons.umbrella;
  return Icons.thunderstorm;
}

Color weatherColor(int code) {
  if (code == 0) return Colors.orange;
  if (code <= 2) return Colors.amber;
  if (code == 3) return Colors.blueGrey;
  if (code <= 48) return Colors.grey;
  if (code <= 82) return Colors.blue;
  return Colors.deepPurple;
}

/// 風向角度 → 方位（風的來向，依語言顯示）
String windDirText(double deg) {
  const keys = ['d_n', 'd_ne', 'd_e', 'd_se', 'd_s', 'd_sw', 'd_w', 'd_nw'];
  final idx = (((deg + 22.5) % 360) / 45).floor();
  return LanguageService.t(keys[idx]);
}

/// 騎行防護建議（機車/重機，永遠至少回傳基本防護；依語言顯示）
List<({IconData icon, String text})> ridingAdvice(HourWeather w) {
  final advice = <({IconData icon, String text})>[];
  final t = LanguageService.t;
  final n = '${w.windSpeed.round()}';

  // 溫度 → 裝備與補水
  if (w.temp >= 32) {
    advice.add((icon: Icons.thermostat, text: t('adv_hot')));
  } else if (w.temp >= 28) {
    advice.add((icon: Icons.wb_sunny_outlined, text: t('adv_warm')));
  } else if (w.temp >= 18) {
    advice.add((icon: Icons.checkroom, text: t('adv_mild')));
  } else if (w.temp >= 10) {
    advice.add((icon: Icons.checkroom, text: t('adv_cool')));
  } else {
    advice.add((icon: Icons.ac_unit, text: t('adv_cold')));
  }

  // 降雨
  if (w.precipProb >= 60 || w.precip > 0.5) {
    advice.add((icon: Icons.umbrella, text: t('adv_rain_high')));
  } else if (w.precipProb >= 30) {
    advice.add((icon: Icons.water_drop_outlined, text: t('adv_rain_mid')));
  }

  // 風
  if (w.windSpeed >= 30) {
    advice.add((
      icon: Icons.air,
      text: LanguageService.tp('adv_wind_strong', {'n': n})
    ));
  } else if (w.windSpeed >= 20) {
    advice.add((
      icon: Icons.air,
      text: LanguageService.tp('adv_wind_mid', {'n': n})
    ));
  }

  // 能見度
  if (w.weatherCode == 45 || w.weatherCode == 48) {
    advice.add((icon: Icons.lightbulb_outline, text: t('adv_fog')));
  }

  // 基本防護（永遠顯示）
  advice.add((icon: Icons.health_and_safety_outlined, text: t('adv_basic')));

  return advice;
}

/// 騎行警示標籤（依語言顯示）
List<String> ridingAlerts(HourWeather w) {
  final t = LanguageService.t;
  final alerts = <String>[];
  if (w.weatherCode >= 95) alerts.add(t('al_storm'));
  if (w.weatherCode >= 51 && w.weatherCode <= 82 || w.precip > 0) {
    alerts.add(t('al_wet'));
  }
  if (w.temp > 30 && w.weatherCode <= 3) alerts.add(t('al_hot'));
  if (w.temp < 10) alerts.add(t('al_cold'));
  if (w.windSpeed > 40) alerts.add(t('al_wind'));
  if (w.weatherCode == 45 || w.weatherCode == 48) alerts.add(t('al_fog'));
  return alerts;
}

// ════════════════════════════════════════════════════════════
// API 呼叫
// ════════════════════════════════════════════════════════════

/// 取得某座標在指定時間的逐小時天氣（用於 ETA 預測）
Future<HourWeather?> fetchHourAt(
    double lat, double lng, DateTime target) async {
  try {
    final res = await ApiClient.get(Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lng'
      '&hourly=temperature_2m,precipitation_probability,precipitation,'
      'weathercode,windspeed_10m,winddirection_10m'
      '&timezone=auto&forecast_days=3',
    )).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final h = jsonDecode(res.body)['hourly'];
    final times = h['time'] as List;
    int best = 0, bestDiff = 999999;
    for (int i = 0; i < times.length; i++) {
      final diff =
          DateTime.parse(times[i] as String).difference(target).inMinutes.abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return HourWeather(
      temp: (h['temperature_2m'][best] as num).toDouble(),
      weatherCode: (h['weathercode'][best] as num).toInt(),
      windSpeed: (h['windspeed_10m'][best] as num).toDouble(),
      windDir: (h['winddirection_10m'][best] as num? ?? 0).toDouble(),
      precipProb:
          (h['precipitation_probability'][best] as num? ?? 0).toInt(),
      precip: (h['precipitation'][best] as num? ?? 0).toDouble(),
    );
  } catch (e) {
    debugPrint('fetchHourAt 錯誤：$e');
    return null;
  }
}

/// 取得某座標的目前天氣 + 7 天預報
Future<PointWeather?> fetchPointWeather(
    double lat, double lng, String name) async {
  try {
    final res = await ApiClient.get(Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lng'
      '&current=temperature_2m,apparent_temperature,relative_humidity_2m,'
      'precipitation,weathercode,windspeed_10m'
      '&daily=weathercode,temperature_2m_max,temperature_2m_min,'
      'precipitation_probability_max,windspeed_10m_max'
      '&timezone=auto&forecast_days=7',
    )).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    final cur = data['current'];
    final d = data['daily'];
    final dates = d['time'] as List;
    final daily = <DayForecast>[];
    for (int i = 0; i < dates.length; i++) {
      final p = (dates[i] as String).split('-');
      daily.add(DayForecast(
        date: '${p[1]}/${p[2]}',
        weatherCode: (d['weathercode'][i] as num).toInt(),
        tempMax: (d['temperature_2m_max'][i] as num).toDouble(),
        tempMin: (d['temperature_2m_min'][i] as num).toDouble(),
        precipProb:
            (d['precipitation_probability_max'][i] as num? ?? 0).toInt(),
        windMax: (d['windspeed_10m_max'][i] as num).toDouble(),
      ));
    }
    return PointWeather(
      locationName: name,
      current: HourWeather(
        temp: (cur['temperature_2m'] as num).toDouble(),
        weatherCode: (cur['weathercode'] as num).toInt(),
        windSpeed: (cur['windspeed_10m'] as num).toDouble(),
        precipProb: 0,
        precip: (cur['precipitation'] as num).toDouble(),
      ),
      daily: daily,
    );
  } catch (e) {
    debugPrint('fetchPointWeather 錯誤：$e');
    return null;
  }
}
