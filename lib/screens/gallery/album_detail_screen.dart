import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../api_client.dart';
import 'package:image_picker/image_picker.dart';
import '../../config.dart';
import '../../services/auth_service.dart';
import '../../widgets/login_dialog.dart';
import '../../services/language_service.dart';
import '../../services/user_service.dart';
import '../../utils/photo_actions.dart';

/// 依點讚數回傳愛心顏色（彩度隨梯度遞增）
Color _heartColor(int likes) {
  if (likes <= 50)   return const Color(0xFFFFCDD2); // 淡粉
  if (likes <= 150)  return const Color(0xFFEF9A9A); // 粉
  if (likes <= 350)  return const Color(0xFFE57373); // 淡紅
  if (likes <= 750)  return const Color(0xFFF44336); // 紅
  if (likes <= 1250) return const Color(0xFFE53935); // 深紅
  if (likes <= 2000) return const Color(0xFFC62828); // 更深紅
  return const Color(0xFFB71C1C);                    // 最深紅
}

class AlbumDetailScreen extends StatefulWidget {
  final Map album;
  const AlbumDetailScreen({super.key, required this.album});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<dynamic> _photos = [];
  bool _loading = true;
  String _username = '匿名';

  @override
  void initState() {
    super.initState();
    _loadUser();
    _load();
  }

  Future<void> _loadUser() async {
    final name = await UserService.getUsername();
    if (mounted) setState(() => _username = name ?? '匿名');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiClient.get(
        Uri.parse('${Config.baseUrl}/albums/${widget.album['id']}/photos'),
      );
      setState(() {
        _photos = jsonDecode(r.body);
        _loading = false;
      });
    } catch (e) {
      debugPrint('錯誤：$e');
      setState(() => _loading = false);
    }
  }

  Future<void> _like(String id) async {
    try {
      await ApiClient.post(Uri.parse('${Config.baseUrl}/album_photos/$id/like'));
      await _load();
    } catch (e) { debugPrint('錯誤：$e'); }
  }

  Future<void> _deletePhoto(String id) async {
    try {
      await ApiClient.delete(Uri.parse('${Config.baseUrl}/album_photos/$id'));
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('photo_deleted'))));
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${LanguageService.t('del_fail')}: $e')));
      }
    }
  }

  Future<void> _pickAndUpload() async {
    // 未登入先彈出登入對話框
    if (!AuthService.isLoggedIn) {
      final ok = await LoginDialog.show(context);
      if (!ok || !mounted) return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return;

    final captionCtrl = TextEditingController();
    final caption = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(LanguageService.t('photo_caption')),
        content: TextField(
          controller: captionCtrl,
          decoration:
              InputDecoration(hintText: LanguageService.t('caption_hint')),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(LanguageService.t('skip')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, captionCtrl.text.trim()),
            child: Text(LanguageService.t('confirm')),
          ),
        ],
      ),
    );
    if (caption == null) return;

    final uri = Uri.parse(
        '${Config.baseUrl}/albums/${widget.album['id']}/photos');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(AuthService.authHeader);
    request.fields['sender'] = _username;
    request.fields['caption'] = caption;

    final bytes = await picked.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes(
      'photo',
      bytes,
      filename: picked.name.isNotEmpty ? picked.name : 'photo.jpg',
    ));

    try {
      final resp = await request.send();
      final body = await resp.stream.bytesToString();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('photo_uploaded'))),
          );
        }
      } else {
        throw Exception('${resp.statusCode}: $body');
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${LanguageService.t('msg_upload_fail')}: $e')),
        );
      }
    }
  }

  void _showDetail(Map photo) {
    final isMine = photo['sender'] == _username;
    showDialog(
      context: context,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.82;
        return Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  height: 260,
                  child: _PhotoImage(url: photo['url'] ?? ''),
                ),
                if ((photo['caption'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(photo['caption'],
                        style: const TextStyle(fontSize: 15)),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.favorite, color: _heartColor((photo['likes'] ?? 0) as int), size: 18),
                    const SizedBox(width: 4),
                    Text(LanguageService.tp(
                        'likes_count', {'n': '${photo['likes'] ?? 0}'})),
                    const Spacer(),
                    Text(photo['sender'] ?? '',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13)),
                  ]),
                ),
                OverflowBar(children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _like(photo['id'].toString());
                    },
                    child: Text(LanguageService.t('like_btn')),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      showPhotoActions(context,
                          url: photo['url'] ?? '',
                          caption: photo['caption'] ?? '');
                    },
                    child: Text(LanguageService.t('share')),
                  ),
                  if (isMine)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _deletePhoto(photo['id'].toString());
                      },
                      child: Text(LanguageService.t('delete')),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(LanguageService.t('close')),
                  ),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    return Scaffold(
      appBar: AppBar(
        title: Text(album['title'] ?? LanguageService.t('nav_gallery')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
              ? Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    const Icon(Icons.photo_library_outlined,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(LanguageService.t('no_photos'),
                        style:
                            TextStyle(color: Colors.grey, fontSize: 16)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _pickAndUpload,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: Text(LanguageService.t('add_first_photo')),
                    ),
                  ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 80),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: _photos.length,
                    itemBuilder: (_, i) {
                      final p = _photos[i];
                      return GestureDetector(
                        onTap: () => _showDetail(p),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _PhotoImage(url: p['url'] ?? ''),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.6),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                                child: Row(children: [
                                  if ((p['caption'] ?? '').isNotEmpty)
                                    Expanded(
                                      child: Text(p['caption'],
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    )
                                  else
                                    const Spacer(),
                                  GestureDetector(
                                    onTap: () => _like(p['id'].toString()),
                                    behavior: HitTestBehavior.opaque,
                                    child: Row(children: [
                                      Icon(Icons.favorite,
                                          color: _heartColor((p['likes'] ?? 0) as int), size: 16),
                                      const SizedBox(width: 3),
                                      Text('${p['likes'] ?? 0}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12)),
                                    ]),
                                  ),
                                ]),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndUpload,
        child: const Icon(Icons.add_photo_alternate),
      ),
    );
  }
}

class _PhotoImage extends StatelessWidget {
  final String url;
  const _PhotoImage({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.image_not_supported_outlined,
            color: Colors.grey),
      );
    }
    final fullUrl = url.startsWith('http')
        ? url
        : 'http://${Config.serverIp}:${Config.serverPort}$url';
    return Image.network(
      fullUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
      ),
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
