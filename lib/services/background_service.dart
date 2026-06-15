import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundConfig {
  final String type; // 'default' | 'color' | 'image'
  final Color? color;
  final String? imagePath; // local file path（原生平台）
  final String? imageData; // base64 編碼影像（web：無檔案系統，改存資料）

  const BackgroundConfig({
    this.type = 'default',
    this.color,
    this.imagePath,
    this.imageData,
  });
}

class BackgroundService {
  static const _kType      = 'bg_type';
  static const _kColor     = 'bg_color';
  static const _kImage     = 'bg_image';
  static const _kImageData = 'bg_image_data';

  static final notifier = ValueNotifier<BackgroundConfig>(const BackgroundConfig());

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final type      = p.getString(_kType) ?? 'default';
    final colorVal  = p.getInt(_kColor);
    final imagePath = p.getString(_kImage);
    final imageData = p.getString(_kImageData);
    notifier.value = BackgroundConfig(
      type:      type,
      color:     colorVal != null ? Color(colorVal) : null,
      imagePath: imagePath,
      imageData: imageData,
    );
  }

  static Future<void> setColor(Color c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kType, 'color');
    await p.setInt(_kColor, c.toARGB32());
    await p.remove(_kImage);
    await p.remove(_kImageData);
    notifier.value = BackgroundConfig(type: 'color', color: c);
  }

  /// 原生平台：以本機檔案路徑儲存
  static Future<void> setImage(String path) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kType, 'image');
    await p.setString(_kImage, path);
    await p.remove(_kImageData);
    notifier.value = BackgroundConfig(type: 'image', imagePath: path);
  }

  /// web 平台：以 base64 影像資料儲存（無檔案系統可用）
  static Future<void> setImageData(String data) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kType, 'image');
    await p.setString(_kImageData, data);
    await p.remove(_kImage);
    notifier.value = BackgroundConfig(type: 'image', imageData: data);
  }

  static Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kType);
    await p.remove(_kColor);
    await p.remove(_kImage);
    await p.remove(_kImageData);
    notifier.value = const BackgroundConfig();
  }
}
