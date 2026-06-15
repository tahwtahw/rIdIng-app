import 'package:flutter/material.dart';
import 'screens/main_scaffold.dart';
import 'services/language_service.dart';

class RIdIngApp extends StatelessWidget {
  const RIdIngApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 語言改變時以新 key 重建整個 App，讓所有介面文字徹底更換
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.notifier,
      builder: (_, lang, __) => MaterialApp(
        key: ValueKey('app_$lang'),
        title: 'rIdIng',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
          ),
          useMaterial3: true,
        ),
        home: const MainScaffold(),
      ),
    );
  }
}
