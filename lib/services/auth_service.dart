import 'dart:convert';
import 'package:flutter/material.dart';
import '../api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class AuthUser {
  final String id;
  final String email;
  final String username;
  final String token;

  const AuthUser({
    required this.id,
    required this.email,
    required this.username,
    required this.token,
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] ?? '',
        email: j['email'] ?? '',
        username: j['username'] ?? '',
        token: j['token'] ?? '',
      );
}

class AuthService {
  static const _kToken = 'auth_token';

  /// 目前登入的用戶，null 表示未登入
  static final notifier = ValueNotifier<AuthUser?>(null);

  static bool get isLoggedIn => notifier.value != null;
  static AuthUser? get currentUser => notifier.value;

  /// App 啟動時呼叫：從本機讀 token 並向後端驗證
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kToken);
    if (token == null || token.isEmpty) return;
    try {
      final res = await ApiClient.get(
        Uri.parse('${Config.baseUrl}/auth/verify'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        notifier.value = AuthUser.fromJson(jsonDecode(res.body));
      } else {
        // Token 失效，清除
        await prefs.remove(_kToken);
      }
    } catch (_) {
      // 網路問題，不強制登出，下次重試
    }
  }

  /// 登入，成功回傳 AuthUser，失敗拋出錯誤訊息
  static Future<AuthUser> login(String email, String password) async {
    final res = await ApiClient.post(
      Uri.parse('${Config.baseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw body['error'] ?? '登入失敗';
    final user = AuthUser.fromJson(body);
    await _save(user);
    return user;
  }

  /// 註冊，成功回傳 AuthUser，失敗拋出錯誤訊息
  static Future<AuthUser> register(
      String email, String password, String username) async {
    final res = await ApiClient.post(
      Uri.parse('${Config.baseUrl}/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'username': username.trim(),
      }),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw body['error'] ?? '註冊失敗';
    }
    final user = AuthUser.fromJson(body);
    await _save(user);
    return user;
  }

  /// 登出
  static Future<void> logout() async {
    final token = notifier.value?.token;
    if (token != null) {
      try {
        await ApiClient.post(
          Uri.parse('${Config.baseUrl}/auth/logout'),
          headers: {'Authorization': 'Bearer $token'},
        );
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    notifier.value = null;
  }

  static Future<void> _save(AuthUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, user.token);
    notifier.value = user;
  }

  /// 回傳目前 token 的 Authorization header，供上傳請求使用
  static Map<String, String> get authHeader {
    final token = notifier.value?.token ?? '';
    return token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {};
  }
}
