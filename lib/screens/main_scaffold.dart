import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'home/home_screen.dart';
import 'events/events_screen.dart';
import 'gallery/gallery_screen.dart';
import 'community/community_screen.dart';
import 'info/info_screen.dart';
import 'profile/profile_screen.dart';
import '../services/background_service.dart';
import '../services/language_service.dart';

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
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    BackgroundService.notifier.addListener(_onBgChanged);
    LanguageService.notifier.addListener(_onBgChanged);
  }

  @override
  void dispose() {
    BackgroundService.notifier.removeListener(_onBgChanged);
    LanguageService.notifier.removeListener(_onBgChanged);
    super.dispose();
  }

  void _onBgChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final config = BackgroundService.notifier.value;

    final nav = NavigationBar(
      selectedIndex: _currentIndex,
      onDestinationSelected: (i) => setState(() => _currentIndex = i),
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: LanguageService.t('nav_home'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.calendar_month_outlined),
          selectedIcon: const Icon(Icons.calendar_month),
          label: LanguageService.t('nav_events'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.photo_library_outlined),
          selectedIcon: const Icon(Icons.photo_library),
          label: LanguageService.t('nav_gallery'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.people_outlined),
          selectedIcon: const Icon(Icons.people),
          label: LanguageService.t('nav_community'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.info_outline),
          selectedIcon: const Icon(Icons.info),
          label: LanguageService.t('nav_info'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_outline),
          selectedIcon: const Icon(Icons.person),
          label: LanguageService.t('nav_profile'),
        ),
      ],
    );

    if (kIsWeb) {
      final bgColor = config.type == 'color' && config.color != null
          ? config.color!
          : Theme.of(context).colorScheme.surface;
      return ColoredBox(
        color: bgColor,
        child: Theme(
          data: Theme.of(context).copyWith(
            scaffoldBackgroundColor: Colors.transparent,
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: IndexedStack(index: _currentIndex, children: _screens),
            bottomNavigationBar: nav,
          ),
        ),
      );
    }

    // ── Mobile: Stack + 透明 Scaffold ────────────────────────────
    // 自訂背景時，內頁各自的 Scaffold 也必須透明（透過 Theme 覆寫），
    // 否則內頁的不透明 Scaffold 會把背景蓋住（背景設定失效的原因）
    final hasCustomBg = (config.type == 'color' && config.color != null) ||
        (config.type == 'image' && config.imagePath != null);

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackground(config),
        Theme(
          data: hasCustomBg
              ? Theme.of(context).copyWith(
                  scaffoldBackgroundColor: Colors.transparent,
                )
              : Theme.of(context),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: IndexedStack(index: _currentIndex, children: _screens),
            bottomNavigationBar: nav,
          ),
        ),
      ],
    );
  }

  Widget _buildBackground(BackgroundConfig config) {
    if (config.type == 'color' && config.color != null) {
      return Container(color: config.color);
    }
    if (config.type == 'image' && config.imageData != null) {
      return Image.memory(base64Decode(config.imageData!),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity);
    }
    if (!kIsWeb && config.type == 'image' && config.imagePath != null) {
      final f = File(config.imagePath!);
      if (f.existsSync()) {
        return Image.file(f,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity);
      }
    }
    return const SizedBox.shrink();
  }
}
