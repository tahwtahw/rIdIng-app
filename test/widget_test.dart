import 'package:flutter_test/flutter_test.dart';
import 'package:riding_app/services/language_service.dart';

void main() {
  test('LanguageService 翻譯回退測試', () {
    // 預設語言為繁中
    LanguageService.notifier.value = 'zh-TW';
    expect(LanguageService.t('nav_home'), '首頁');

    // 切換英文
    LanguageService.notifier.value = 'en';
    expect(LanguageService.t('nav_home'), 'Home');

    // 不存在的 key 回傳 key 本身
    expect(LanguageService.t('__no_such_key__'), '__no_such_key__');

    // 參數替換
    LanguageService.notifier.value = 'zh-TW';
    expect(
      LanguageService.tp('room_joined', {'x': '測試'}),
      '已加入「測試」',
    );
  });
}
