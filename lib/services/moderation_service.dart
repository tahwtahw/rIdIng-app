import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../api_client.dart';
import '../config.dart';
import 'auth_service.dart';

/// 內容審查：檢舉與封鎖
class ModerationService {
  /// 目前使用者封鎖的暱稱集合；變動時通知 UI 重新過濾
  static final ValueNotifier<Set<String>> blocked =
      ValueNotifier<Set<String>>(<String>{});

  /// 登入後載入封鎖名單；未登入則清空
  static Future<void> load() async {
    if (!AuthService.isLoggedIn) {
      blocked.value = <String>{};
      return;
    }
    try {
      final res = await ApiClient.get(
        Uri.parse('${Config.baseUrl}/blocks'),
        headers: AuthService.authHeader,
      );
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List).map((e) => e.toString());
        blocked.value = list.toSet();
      }
    } catch (e) {
      debugPrint('載入封鎖名單失敗：$e');
    }
  }

  static bool isBlocked(String? name) =>
      name != null && blocked.value.contains(name);

  /// 封鎖某位使用者（以暱稱）
  static Future<void> block(String name) async {
    final res = await ApiClient.post(
      Uri.parse('${Config.baseUrl}/blocks'),
      headers: {...AuthService.authHeader, 'Content-Type': 'application/json'},
      body: jsonEncode({'blocked': name}),
    );
    if (res.statusCode != 200) throw Exception('封鎖失敗 (${res.statusCode})');
    blocked.value = {...blocked.value, name};
  }

  /// 解除封鎖
  static Future<void> unblock(String name) async {
    final res = await ApiClient.delete(
      Uri.parse('${Config.baseUrl}/blocks/${Uri.encodeComponent(name)}'),
      headers: AuthService.authHeader,
    );
    if (res.statusCode != 200) throw Exception('解除封鎖失敗 (${res.statusCode})');
    blocked.value = {...blocked.value}..remove(name);
  }

  /// 送出檢舉
  static Future<void> report({
    required String targetType, // message | photo | album | outing | user
    required String targetId,
    String targetOwner = '',
    required String reason,
    String detail = '',
  }) async {
    final res = await ApiClient.post(
      Uri.parse('${Config.baseUrl}/reports'),
      headers: {...AuthService.authHeader, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'target_type': targetType,
        'target_id': targetId,
        'target_owner': targetOwner,
        'reason': reason,
        'detail': detail,
      }),
    );
    if (res.statusCode != 200) throw Exception('檢舉失敗 (${res.statusCode})');
  }
}
