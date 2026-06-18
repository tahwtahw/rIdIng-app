import 'package:flutter/material.dart';
import '../services/language_service.dart';
import '../services/moderation_service.dart';

/// 顯示檢舉對話框；送出成功回傳 true
Future<void> showReportDialog(
  BuildContext context, {
  required String targetType, // message | photo | album | outing | user
  required String targetId,
  String targetOwner = '',
}) async {
  const reasons = ['r_spam', 'r_harass', 'r_inappropriate', 'r_other'];
  String selected = reasons.first;
  final detailCtrl = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(LanguageService.t('report')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(LanguageService.t('report_reason'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ...reasons.map((r) => RadioListTile<String>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: r,
                    groupValue: selected,
                    onChanged: (v) => setLocal(() => selected = v!),
                    title: Text(LanguageService.t(r)),
                  )),
              const SizedBox(height: 8),
              TextField(
                controller: detailCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: LanguageService.t('detail_optional'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(LanguageService.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(LanguageService.t('report')),
          ),
        ],
      ),
    ),
  );

  if (ok != true) return;
  try {
    await ModerationService.report(
      targetType: targetType,
      targetId: targetId,
      targetOwner: targetOwner,
      reason: selected,
      detail: detailCtrl.text.trim(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanguageService.t('report_sent'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${LanguageService.t('report')}：$e')),
      );
    }
  }
}
