import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/auth_service.dart';
import '../../services/background_service.dart';
import '../../services/language_service.dart';
import '../../services/user_service.dart';
import '../../widgets/login_dialog.dart';

const _kSwatches = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFFF5F5F5),
  Color(0xFFE3F2FD),
  Color(0xFFE8F5E9),
  Color(0xFFFFF8E1),
  Color(0xFFFCE4EC),
  Color(0xFFEDE7F6),
  Color(0xFFE0F2F1),
  Color(0xFF1565C0),
  Color(0xFF212121),
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  BackgroundConfig _config = BackgroundService.notifier.value;
  String _username = '匿名';
  final _nameCtrl = TextEditingController();
  bool _bgExpanded = false;
  bool _langExpanded = false;

  // 暫存尚未儲存的背景選擇
  BackgroundConfig? _pending;

  @override
  void initState() {
    super.initState();
    BackgroundService.notifier.addListener(_onBgChanged);
    AuthService.notifier.addListener(_onAuthChanged);
    _loadUser();
  }

  @override
  void dispose() {
    BackgroundService.notifier.removeListener(_onBgChanged);
    AuthService.notifier.removeListener(_onAuthChanged);
    _nameCtrl.dispose();
    super.dispose();
  }

  void _onAuthChanged() => setState(() {});

  void _onBgChanged() =>
      setState(() => _config = BackgroundService.notifier.value);

  Future<void> _loadUser() async {
    final name = await UserService.getUsername();
    if (mounted) {
      setState(() => _username = name ?? '匿名');
      _nameCtrl.text = _username;
    }
  }

  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    await UserService.setUsername(name);
    setState(() => _username = name);
    if (mounted) {
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暱稱已更新')));
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: kIsWeb ? 80 : 85,
      // web 需縮圖，避免 base64 超過 localStorage 容量上限
      maxWidth: kIsWeb ? 1280 : null,
      maxHeight: kIsWeb ? 1280 : null,
    );
    if (picked == null) return;
    final BackgroundConfig cfg;
    if (kIsWeb) {
      // web 無檔案系統，改存 base64 影像資料
      final bytes = await picked.readAsBytes();
      cfg = BackgroundConfig(type: 'image', imageData: base64Encode(bytes));
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/bg_custom.jpg');
      await dest.writeAsBytes(await picked.readAsBytes());
      cfg = BackgroundConfig(type: 'image', imagePath: dest.path);
    }
    // 更新暫存並立即套用預覽（按儲存才永久保存）
    setState(() => _pending = cfg);
    BackgroundService.notifier.value = cfg;
  }

  Future<void> _saveBg() async {
    final p = _pending;
    if (p == null) return;

    // 立即更新 notifier（視覺馬上生效）
    BackgroundService.notifier.value = p;

    // 非同步持久化（不等待）
    if (p.type == 'color' && p.color != null) {
      BackgroundService.setColor(p.color!);
    } else if (p.type == 'image' && p.imageData != null) {
      BackgroundService.setImageData(p.imageData!);
    } else if (p.type == 'image' && p.imagePath != null) {
      BackgroundService.setImage(p.imagePath!);
    } else {
      BackgroundService.reset();
    }

    setState(() { _pending = null; _bgExpanded = false; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('msg_bg_saved'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<String>(
          valueListenable: LanguageService.notifier,
          builder: (_, __, ___) => Text(LanguageService.t('nav_profile')),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ── 帳號登入 ─────────────────────────────────────────────────
        _buildAuthSection(theme),
        const SizedBox(height: 12),
        // ── 暱稱 ──────────────────────────────────────────────────────
        Text(LanguageService.t('nickname'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: LanguageService.t('nickname_room_hint'),
                isDense: true,
              ),
              onSubmitted: (_) => _saveName(),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
              onPressed: _saveName,
              child: Text(LanguageService.t('save'))),
        ]),
        const Divider(height: 24),

        // ── 背景設定（可收合）─────────────────────────────────────────
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: Text(LanguageService.t('bg_settings')),
                subtitle: Text(
                  _config.type == 'color' ? '純色背景'
                    : _config.type == 'image' ? '照片背景'
                    : '預設背景',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Icon(_bgExpanded ? Icons.expand_less : Icons.expand_more),
                onTap: () => setState(() => _bgExpanded = !_bgExpanded),
              ),
              if (_bgExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 預覽（顯示暫存或目前設定）
                      Container(
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildPreview(_pending ?? _config),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          const cfg = BackgroundConfig();
                          setState(() => _pending = cfg);
                          BackgroundService.notifier.value = cfg;
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(LanguageService.t('reset_default')),
                      ),
                      const Divider(height: 24),
                      Text(LanguageService.t('solid_bg'),
                          style: theme.textTheme.labelMedium),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _kSwatches.map((c) {
                          final cur = _pending ?? _config;
                          final sel = cur.type == 'color' && cur.color == c;
                          return InkWell(
                            onTap: () {
                              final cfg =
                                  BackgroundConfig(type: 'color', color: c);
                              setState(() => _pending = cfg);
                              // 立即套用到整個 App（按儲存才永久保存）
                              BackgroundService.notifier.value = cfg;
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: sel
                                    ? Border.all(color: theme.colorScheme.primary, width: 3)
                                    : Border.all(color: Colors.grey.shade300),
                                boxShadow: sel
                                    ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.4), blurRadius: 6)]
                                    : null,
                              ),
                              child: sel
                                  ? Icon(Icons.check, size: 18,
                                      color: c.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const Divider(height: 24),
                      Text(LanguageService.t('custom_color'),
                          style: theme.textTheme.labelMedium),
                      const SizedBox(height: 8),
                      _ColorSliderPicker(
                        initial: (_pending ?? _config).type == 'color'
                            ? (_pending ?? _config).color
                            : null,
                        onChanged: (c) {
                          final cfg =
                              BackgroundConfig(type: 'color', color: c);
                          setState(() => _pending = cfg);
                          BackgroundService.notifier.value = cfg;
                        },
                      ),
                      const Divider(height: 24),
                      Text(LanguageService.t('photo_bg'),
                          style: theme.textTheme.labelMedium),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(LanguageService.t('from_gallery')),
                      ),
                      if ((_pending ?? _config).type == 'image' &&
                          ((_pending ?? _config).imageData != null ||
                              (_pending ?? _config).imagePath != null)) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: (_pending ?? _config).imageData != null
                              ? Image.memory(
                                  base64Decode((_pending ?? _config).imageData!),
                                  height: 120, width: double.infinity, fit: BoxFit.cover)
                              : Image.file(
                                  File((_pending ?? _config).imagePath!),
                                  height: 120, width: double.infinity, fit: BoxFit.cover),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // 儲存按鈕
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _pending != null ? _saveBg : null,
                          icon: const Icon(Icons.save),
                          label: Text(LanguageService.t('save_bg')),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        LanguageService.t('bg_hint'),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── 語言設定 ─────────────────────────────────────────────────
        _buildLanguageSection(theme),
        const SizedBox(height: 24),
      ]),
    );
  }

  // ── 語言設定卡片 ───────────────────────────────────────────────
  Widget _buildLanguageSection(ThemeData theme) {
    final lang = LanguageService.notifier.value;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(LanguageService.t('language')),
            subtitle: Text(
              LanguageService.displayName(lang),
              style: const TextStyle(fontSize: 12),
            ),
            trailing:
                Icon(_langExpanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _langExpanded = !_langExpanded),
          ),
          if (_langExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // 內建語言
                      ...LanguageService.presets.entries.map(
                        (e) => ChoiceChip(
                          label: Text(e.value,
                              style: const TextStyle(fontSize: 12)),
                          selected: lang == e.key,
                          onSelected: (_) async {
                            await LanguageService.setLang(e.key);
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                      // 自訂語言（可刪除）
                      ...LanguageService.customLangs.map(
                        (n) => InputChip(
                          label: Text(n,
                              style: const TextStyle(fontSize: 12)),
                          selected: lang == 'custom:$n',
                          onSelected: (_) async {
                            await LanguageService.setLang('custom:$n');
                            if (mounted) setState(() {});
                          },
                          onDeleted: () async {
                            await LanguageService.removeCustomLang(n);
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(LanguageService.t('add_language')),
                    onPressed: _showAddLangDialog,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    LanguageService.t('lang_hint'),
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showAddLangDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('新增語言'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: LanguageService.t('lang_name'),
            hintText: 'Tagalog / Burmese ...',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await LanguageService.addCustomLang(ctrl.text);
              if (!mounted) return;
              Navigator.pop(dialogCtx);
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(LanguageService.t('msg_name_invalid'))));
              }
              setState(() {});
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthSection(ThemeData theme) {
    final user = AuthService.currentUser;
    if (user != null) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
          title: Text(user.username,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(user.email,
              style: const TextStyle(fontSize: 12)),
          trailing: TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(LanguageService.t('logout')),
                  content: const Text('確定要登出嗎？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(LanguageService.t('logout'))),
                  ],
                ),
              );
              if (confirm == true) await AuthService.logout();
            },
            child: Text(LanguageService.t('logout')),
          ),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(LanguageService.t('not_logged_in')),
        subtitle: const Text('登入後才能上傳照片及建立相簿',
            style: TextStyle(fontSize: 12)),
        trailing: FilledButton(
          onPressed: () => LoginDialog.show(context),
          child: Text(LanguageService.t('login')),
        ),
      ),
    );
  }

  Widget _buildPreview(BackgroundConfig cfg) {
    if (cfg.type == 'color' && cfg.color != null) {
      return Container(color: cfg.color);
    }
    if (cfg.type == 'image' && cfg.imageData != null) {
      return Image.memory(base64Decode(cfg.imageData!), fit: BoxFit.cover);
    }
    if (!kIsWeb && cfg.type == 'image' && cfg.imagePath != null) {
      return Image.file(File(cfg.imagePath!), fit: BoxFit.cover);
    }
    return Container(
      color: Colors.grey.shade100,
      child: Center(
          child: Text(LanguageService.t('default_bg'),
              style: const TextStyle(color: Colors.grey))),
    );
  }
}

// ── RGB 滑桿 ────────────────────────────────────────────────────────────
class _ColorSliderPicker extends StatefulWidget {
  final Color? initial;
  final ValueChanged<Color> onChanged;
  const _ColorSliderPicker({this.initial, required this.onChanged});

  @override
  State<_ColorSliderPicker> createState() => _ColorSliderPickerState();
}

class _ColorSliderPickerState extends State<_ColorSliderPicker> {
  late double _r, _g, _b;

  @override
  void initState() {
    super.initState();
    final c = widget.initial ?? Colors.white;
    _r = c.red.toDouble();
    _g = c.green.toDouble();
    _b = c.blue.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color.fromRGBO(_r.round(), _g.round(), _b.round(), 1);
    return Column(
      children: [
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
        ),
        const SizedBox(height: 8),
        _buildSlider('R', _r, Colors.red, (v) {
          setState(() => _r = v);
          widget.onChanged(Color.fromRGBO(_r.round(), _g.round(), _b.round(), 1));
        }),
        _buildSlider('G', _g, Colors.green, (v) {
          setState(() => _g = v);
          widget.onChanged(Color.fromRGBO(_r.round(), _g.round(), _b.round(), 1));
        }),
        _buildSlider('B', _b, Colors.blue, (v) {
          setState(() => _b = v);
          widget.onChanged(Color.fromRGBO(_r.round(), _g.round(), _b.round(), 1));
        }),
      ],
    );
  }

  Widget _buildSlider(String label, double value, Color color, ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(
        width: 16,
        child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      ),
      Expanded(
        child: Slider(
          value: value,
          min: 0, max: 255, divisions: 255,
          activeColor: color,
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 28,
        child: Text(value.round().toString(),
            style: const TextStyle(fontSize: 11), textAlign: TextAlign.right),
      ),
    ]);
  }
}
