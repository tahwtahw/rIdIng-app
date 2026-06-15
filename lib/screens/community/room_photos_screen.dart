import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../api_client.dart';
import 'package:image_picker/image_picker.dart';
import '../../config.dart';
import '../../services/auth_service.dart';
import '../../services/language_service.dart';
import '../../services/user_service.dart';
import '../../utils/photo_actions.dart';
import '../../widgets/login_dialog.dart';

Color _heartColor(int likes) {
  if (likes <= 50)   return const Color(0xFFFFCDD2);
  if (likes <= 150)  return const Color(0xFFEF9A9A);
  if (likes <= 350)  return const Color(0xFFE57373);
  if (likes <= 750)  return const Color(0xFFF44336);
  if (likes <= 1250) return const Color(0xFFE53935);
  if (likes <= 2000) return const Color(0xFFC62828);
  return const Color(0xFFB71C1C);
}

class RoomPhotosScreen extends StatefulWidget {
  final String roomId;
  final bool isPublic;

  const RoomPhotosScreen({
    super.key,
    required this.roomId,
    required this.isPublic,
  });

  @override
  State<RoomPhotosScreen> createState() => _RoomPhotosScreenState();
}

class _RoomPhotosScreenState extends State<RoomPhotosScreen> {
  List<dynamic> _photos = [];
  bool _loading = true;
  String? _error;
  String _username = '我';

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
    setState(() { _loading = true; _error = null; });
    try {
      final r = await ApiClient.get(
        Uri.parse('${Config.baseUrl}/rooms/${widget.roomId}/photos'),
      );
      setState(() {
        _photos = jsonDecode(r.body);
        _loading = false;
      });
    } catch (e) {
      debugPrint('錯誤：$e');
      setState(() {
        _error = '${LanguageService.t('error')}: $e';
        _loading = false;
      });
    }
  }

  Future<void> _like(String photoId) async {
    try {
      await ApiClient.post(Uri.parse('${Config.baseUrl}/photos/$photoId/like'));
      await _load();
    } catch (e) { debugPrint('錯誤：$e'); }
  }

  Future<void> _pickAndUpload() async {
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

    // Show caption dialog
    final caption = await _askCaption();

    final uri = Uri.parse('${Config.baseUrl}/rooms/${widget.roomId}/photos');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(AuthService.authHeader);
    request.fields['sender'] = _username;
    request.fields['caption'] = caption ?? '';

    // Use readAsBytes for reliable Android cross-version support
    final bytes = await picked.readAsBytes();
    final filename = picked.name.isNotEmpty ? picked.name : 'photo.jpg';
    request.files.add(http.MultipartFile.fromBytes(
      'photo',
      bytes,
      filename: filename,
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
        throw Exception('status ${resp.statusCode}: $body');
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

  Future<String?> _askCaption() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(LanguageService.t('add_caption')),
        content: TextField(
          controller: ctrl,
          decoration:
              InputDecoration(hintText: LanguageService.t('caption_opt')),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(LanguageService.t('skip')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text(LanguageService.t('confirm')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.image_not_supported_outlined,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: _load,
                        child: Text(LanguageService.t('retry'))),
                  ]),
                )
              : _photos.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.photo_library_outlined,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(LanguageService.t('no_photos'),
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 16)),
                        if (widget.roomId != 'public') ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _pickAndUpload,
                            icon: const Icon(Icons.add_photo_alternate),
                            label:
                                Text(LanguageService.t('add_first_photo')),
                          ),
                        ],
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(4),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                          childAspectRatio: 1,
                        ),
                        itemCount: _photos.length,
                        itemBuilder: (_, i) {
                          final p = _photos[i];
                          return _PhotoCard(
                            photo: p,
                            onLike: () => _like(p['id'].toString()),
                            onTap: () => _showDetail(p),
                          );
                        },
                      ),
                    ),
      floatingActionButton: widget.roomId == 'public'
          ? null
          : FloatingActionButton(
              onPressed: _pickAndUpload,
              child: const Icon(Icons.add_photo_alternate),
            ),
    );
  }

  Future<void> _deletePhoto(String photoId) async {
    try {
      await ApiClient.delete(Uri.parse('${Config.baseUrl}/photos/$photoId'));
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
                SnackBar(content: Text(LanguageService.t('photo_deleted'))));
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(
                content: Text('${LanguageService.t('del_fail')}: $e')));
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
                  child: _NetworkOrFileImage(url: photo['url'] ?? ''),
                ),
                if ((photo['caption'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(photo['caption'],
                        style: const TextStyle(fontSize: 15)),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
}

class _PhotoCard extends StatelessWidget {
  final Map photo;
  final VoidCallback onLike;
  final VoidCallback onTap;

  const _PhotoCard({
    required this.photo,
    required this.onLike,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _NetworkOrFileImage(url: photo['url'] ?? ''),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                if ((photo['caption'] ?? '').isNotEmpty)
                  Expanded(
                    child: Text(
                      photo['caption'],
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                GestureDetector(
                  onTap: onLike,
                  child: Row(children: [
                    Icon(Icons.favorite,
                        color: _heartColor((photo['likes'] ?? 0) as int), size: 16),
                    const SizedBox(width: 2),
                    Text(
                      '${photo['likes'] ?? 0}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkOrFileImage extends StatelessWidget {
  final String url;
  const _NetworkOrFileImage({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.image_not_supported_outlined,
            color: Colors.grey),
      );
    }
    // Full URL (uploaded file served by backend)
    final fullUrl = url.startsWith('http')
        ? url
        : '${Config.serverIp.isEmpty ? '' : 'http://${Config.serverIp}:${Config.serverPort}'}$url';

    return Image.network(
      fullUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
      ),
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
