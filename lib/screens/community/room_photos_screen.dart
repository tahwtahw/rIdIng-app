import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../config.dart';
import '../../services/user_service.dart';
import '../../utils/photo_actions.dart';

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
      final r = await http.get(
        Uri.parse('${Config.baseUrl}/rooms/${widget.roomId}/photos'),
      );
      setState(() {
        _photos = jsonDecode(r.body);
        _loading = false;
      });
    } catch (e) {
      debugPrint('錯誤：$e');
      setState(() { _error = '錯誤：$e'; _loading = false; });
    }
  }

  Future<void> _like(String photoId) async {
    try {
      await http.post(Uri.parse('${Config.baseUrl}/photos/$photoId/like'));
      await _load();
    } catch (e) { debugPrint('錯誤：$e'); }
  }

  Future<void> _pickAndUpload() async {
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
            const SnackBar(content: Text('照片上傳成功')),
          );
        }
      } else {
        throw Exception('status ${resp.statusCode}: $body');
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上傳失敗：$e')),
        );
      }
    }
  }

  Future<String?> _askCaption() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新增說明'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '照片說明（可略）'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('略過'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('確認'),
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
                    FilledButton(onPressed: _load, child: const Text('重試')),
                  ]),
                )
              : _photos.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.photo_library_outlined,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('還沒有照片',
                            style: TextStyle(color: Colors.grey, fontSize: 16)),
                        if (widget.roomId != 'public') ...[
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _pickAndUpload,
                            icon: const Icon(Icons.add_photo_alternate),
                            label: const Text('新增第一張照片'),
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
      await http.delete(Uri.parse('${Config.baseUrl}/photos/$photoId'));
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('照片已刪除')));
      }
    } catch (e) {
      debugPrint('錯誤：$e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('刪除失敗：$e')));
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
                    Icon(Icons.favorite, color: Colors.red.shade400, size: 18),
                    const SizedBox(width: 4),
                    Text('${photo['likes'] ?? 0} 個讚'),
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
                    child: const Text('分享'),
                  ),
                  if (isMine)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _deletePhoto(photo['id'].toString());
                      },
                      child: const Text('刪除'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('關閉'),
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
                    Colors.black.withOpacity(0.6),
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
                    const Icon(Icons.favorite,
                        color: Colors.red, size: 16),
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
