import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackgroundConfig {
  final String type; // 'default' | 'color' | 'image'
  final Color? color;
  final String? imagePath; // local file path

  const BackgroundConfig({
    this.type = 'default',
    this.color,
    this.imagePath,
  });
}

class BackgroundService {
  static const _kType  = 'bg_type';
  static const _kColor = 'bg_color';
  static const _kImage = 'bg_image';

  static final notifier = ValueNotifier<BackgroundConfig>(const BackgroundConfig());

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final type      = p.getString(_kType) ?? 'default';
    final colorVal  = p.getInt(_kColor);
    final imagePath = p.getString(_kImage);
    notifier.value = BackgroundConfig(
      type:      type,
      color:     colorVal != null ? Color(colorVal) : null,
      imagePath: imagePath,
    );
  }

  static Future<void> setColor(Color c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kType, 'color');
    await p.setInt(_kColor, c.value);
    notifier.value = BackgroundConfig(type: 'color', color: c);
  }

  static Future<void> setImage(String path) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kType, 'image');
    await p.setString(_kImage, path);
    notifier.value = BackgroundConfig(type: 'image', imagePath: path);
  }

  static Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kType);
    await p.remove(_kColor);
    await p.remove(_kImage);
    notifier.value = const BackgroundConfig();
  }
}
