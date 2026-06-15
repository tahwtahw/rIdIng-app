import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/background_service.dart';
import '../../services/language_service.dart';

// 預設色票
const _kSwatches = <Color>[
  Color(0xFFFFFFFF), // 純白
  Color(0xFFF5F5F5), // 淺灰
  Color(0xFFE3F2FD), // 淡藍
  Color(0xFFE8F5E9), // 淡綠
  Color(0xFFFFF8E1), // 淡黃
  Color(0xFFFCE4EC), // 淡粉
  Color(0xFFEDE7F6), // 淡紫
  Color(0xFFE0F2F1), // 淡青
  Color(0xFF1565C0), // 深藍
  Color(0xFF212121), // 深黑
];

class BackgroundSettingsScreen extends StatefulWidget {
  const BackgroundSettingsScreen({super.key});

  @override
  State<BackgroundSettingsScreen> createState() =>
      _BackgroundSettingsScreenState();
}

class _BackgroundSettingsScreenState extends State<BackgroundSettingsScreen> {
  BackgroundConfig _config = BackgroundService.notifier.value;

  @override
  void initState() {
    super.initState();
    BackgroundService.notifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    BackgroundService.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() => _config = BackgroundService.notifier.value);

  // 選擇相片作為背景
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
    if (kIsWeb) {
      // web 無檔案系統，改存 base64 影像資料
      final bytes = await picked.readAsBytes();
      await BackgroundService.setImageData(base64Encode(bytes));
    } else {
      // 複製到 app 文件目錄以確保永久存取
      final dir  = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/bg_custom.jpg');
      await dest.writeAsBytes(await picked.readAsBytes());
      await BackgroundService.setImage(dest.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(LanguageService.t('bg_settings'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ── 目前預覽 ────────────────────────────────────────────────
        Text(LanguageService.t('current_bg'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildPreview(_config),
        ),
        const SizedBox(height: 20),

        // ── 重設為預設 ───────────────────────────────────────────────
        OutlinedButton.icon(
          onPressed: BackgroundService.reset,
          icon: const Icon(Icons.refresh),
          label: Text(LanguageService.t('reset_default')),
        ),
        const Divider(height: 32),

        // ── 選擇純色 ─────────────────────────────────────────────────
        Text(LanguageService.t('solid_bg'),
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _kSwatches.map((c) {
            final selected = _config.type == 'color' && _config.color == c;
            return GestureDetector(
              onTap: () => BackgroundService.setColor(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(color: theme.colorScheme.primary, width: 3)
                      : Border.all(color: Colors.grey.shade300),
                  boxShadow: selected
                      ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.4), blurRadius: 6)]
                      : null,
                ),
                child: selected
                    ? Icon(Icons.check,
                        size: 20,
                        color: c.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
        const Divider(height: 32),

        // ── 選擇自訂色 ───────────────────────────────────────────────
        Text(LanguageService.t('custom_color'),
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        _ColorSliderPicker(
          initial: _config.type == 'color' ? _config.color : null,
          onChanged: BackgroundService.setColor,
        ),
        const Divider(height: 32),

        // ── 選擇照片 ─────────────────────────────────────────────────
        Text(LanguageService.t('photo_bg'),
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.image_outlined),
          label: Text(LanguageService.t('from_gallery')),
        ),
        if (_config.type == 'image' &&
            (_config.imageData != null || _config.imagePath != null)) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _config.imageData != null
                ? Image.memory(
                    base64Decode(_config.imageData!),
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  )
                : Image.file(
                    File(_config.imagePath!),
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
          ),
        ],
      ]),
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
      child: Center(child: Text(LanguageService.t('default_bg'), style: const TextStyle(color: Colors.grey))),
    );
  }
}

// ── 簡易 RGB 滑桿色彩選擇 ─────────────────────────────────────────────
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

  void _notify() => widget.onChanged(
      Color.fromARGB(255, _r.round(), _g.round(), _b.round()));

  @override
  Widget build(BuildContext context) {
    final preview = Color.fromARGB(255, _r.round(), _g.round(), _b.round());
    return Column(children: [
      Row(children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: preview,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade300))),
        const SizedBox(width: 12),
        Text('#${preview.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
            style: const TextStyle(fontFamily: 'monospace')),
      ]),
      const SizedBox(height: 8),
      _Slider('R', _r, Colors.red,  (v) { setState(() => _r = v); _notify(); }),
      _Slider('G', _g, Colors.green,(v) { setState(() => _g = v); _notify(); }),
      _Slider('B', _b, Colors.blue, (v) { setState(() => _b = v); _notify(); }),
    ]);
  }

  Widget _Slider(String label, double val, Color color, ValueChanged<double> onChange) {
    return Row(children: [
      SizedBox(width: 14, child: Text(label, style: const TextStyle(fontSize: 12))),
      Expanded(
        child: Slider(
          value: val,
          min: 0, max: 255,
          activeColor: color,
          onChanged: onChange,
        ),
      ),
      SizedBox(width: 28,
          child: Text(val.round().toString(),
              style: const TextStyle(fontSize: 12), textAlign: TextAlign.right)),
    ]);
  }
}
