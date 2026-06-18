import 'package:flutter/material.dart';
import '../../services/language_service.dart';
import '../../services/moderation_service.dart';

class BlockedListScreen extends StatelessWidget {
  const BlockedListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LanguageService.t('blocked_list'))),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: ModerationService.blocked,
        builder: (context, blocked, _) {
          final names = blocked.toList()..sort();
          if (names.isEmpty) {
            return Center(
              child: Text(LanguageService.t('no_blocked'),
                  style: const TextStyle(color: Colors.grey)),
            );
          }
          return ListView.separated(
            itemCount: names.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final name = names[i];
              return ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: Text(name),
                trailing: TextButton(
                  onPressed: () async {
                    try {
                      await ModerationService.unblock(name);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content:
                                Text(LanguageService.t('unblocked_ok'))));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  child: Text(LanguageService.t('unblock')),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
