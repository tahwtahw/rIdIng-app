import 'package:flutter/material.dart';
import 'app.dart';
import 'services/auth_service.dart';
import 'services/background_service.dart';
import 'services/language_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    BackgroundService.load(),
    AuthService.load(),
  ]);
  await LanguageService.load(); // 需在 AuthService 之後（依帳號讀取自訂語言）
  runApp(const RIdIngApp());
}
