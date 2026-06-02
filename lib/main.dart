import 'package:flutter/material.dart';
import 'app.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundService.load();
  runApp(const RIdIngApp());
}
