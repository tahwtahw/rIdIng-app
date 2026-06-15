import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../config.dart';

/// 把相對路徑轉成完整 URL
String fullImageUrl(String url) {
  if (url.isEmpty) return '';
  if (url.startsWith('http')) return url;
  return 'http://${Config.serverIp}:${Config.serverPort}$url';
}

/// 下載圖片到暫存資料夾，回傳 File
Future<File?> _downloadToTemp(String url) async {
  try {
    final resp = await ApiClient.get(Uri.parse(fullImageUrl(url)));
    if (resp.statusCode != 200) return null;
    final dir = await getTemporaryDirectory();
    final name = url.split('/').last.isNotEmpty
        ? url.split('/').last
        : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(resp.bodyBytes);
    return file;
  } catch (e) {
    debugPrint('錯誤：$e');
    return null;
  }
}

/// 底部選單：複製連結 / 分享 / 上傳至其他 APP
void showPhotoActions(
  BuildContext context, {
  required String url,
  String caption = '',
}) {
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('複製圖片連結'),
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: fullImageUrl(url)));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已複製連結到剪貼簿')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('分享照片'),
            onTap: () async {
              Navigator.pop(context);
              await _shareImage(context, url: url, caption: caption);
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('上傳至其他應用程式'),
            onTap: () async {
              Navigator.pop(context);
              await _shareImage(context, url: url, caption: caption);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _shareImage(
  BuildContext context, {
  required String url,
  String caption = '',
}) async {
  // Show loading
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Row(children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
        ),
        SizedBox(width: 12),
        Text('準備照片中...'),
      ]),
      duration: Duration(seconds: 10),
    ),
  );

  final file = await _downloadToTemp(url);
  ScaffoldMessenger.of(context).clearSnackBars();

  if (file == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('無法下載照片，請確認網路連線')),
    );
    return;
  }

  await Share.shareXFiles(
    [XFile(file.path)],
    text: caption.isNotEmpty ? caption : null,
  );
}
