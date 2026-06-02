import 'dart:io';
import 'package:flutter/material.dart';
import 'home/home_screen.dart';
import 'events/events_screen.dart';
import 'gallery/gallery_screen.dart';
import 'community/community_screen.dart';
import 'info/info_screen.dart';
import 'settings/background_settings_screen.dart';
import '../services/background_service.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    EventsScreen(),
    GalleryScreen(),
    CommunityScreen(),
    InfoScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BackgroundConfig>(
      valueListenable: BackgroundService.notifier,
      builder: (_, config, child) => Stack(
        fit: StackFit.expand,
        children: [
          // ── 背景層 ──────────────────────────────────────────────
          _buildBackground(config),
          // ── 主體 ────────────────────────────────────────────────
          child!,
        ],
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(index: _currentIndex, children: _screens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '首頁',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: '活動',
            ),
            NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: '相簿',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outlined),
              selectedIcon: Icon(Icons.people),
              label: '社群',
            ),
            NavigationDestination(
              icon: Icon(Icons.info_outline),
              selectedIcon: Icon(Icons.info),
              label: '資訊',
            ),
          ],
        ),
        // 右下角背景設定浮動按鈕（半透明小圓圈）
        floatingActionButton: _BgFab(),
        floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
      ),
    );
  }

  Widget _buildBackground(BackgroundConfig config) {
    if (config.type == 'color' && config.color != null) {
      return Container(color: config.color);
    }
    if (config.type == 'image' && config.imagePath != null) {
      final f = File(config.imagePath!);
      if (f.existsSync()) {
        return Image.file(f, fit: BoxFit.cover,
            width: double.infinity, height: double.infinity);
      }
    }
    return const SizedBox.shrink(); // 預設透明，由 MaterialApp 主題決定背景
  }
}

// 半透明調色盤小按鈕
class _BgFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 64), // 讓按鈕不被 NavigationBar 遮住
      child: FloatingActionButton.small(
        heroTag: 'bgFab',
        backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.85),
        elevation: 2,
        tooltip: '背景設定',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BackgroundSettingsScreen()),
        ),
        child: Icon(Icons.palette_outlined,
            color: Theme.of(context).colorScheme.primary, size: 20),
      ),
    );
  }
}
