import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/language_service.dart';

/// 呼叫 LoginDialog.show(context)
/// 回傳 true 表示登入/註冊成功
class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoginDialog(),
    );
    return result == true;
  }

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  bool _isLogin = true;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _formKey      = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 通知系統結束自動填入，確保 controller 拿到最新文字
    TextInput.finishAutofillContext();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _error = null; });
    try {
      if (_isLogin) {
        await AuthService.login(_emailCtrl.text.trim(), _passwordCtrl.text);
      } else {
        await AuthService.register(
            _emailCtrl.text.trim(), _passwordCtrl.text, _nameCtrl.text.trim());
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isLogin
          ? LanguageService.t('login_title')
          : LanguageService.t('register_title')),
      content: SizedBox(
        width: 320,
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!_isLogin) ...[
                TextFormField(
                  controller: _nameCtrl,
                  autofillHints: const [AutofillHints.nickname],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: LanguageService.t('nickname'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? LanguageService.t('v_need_nickname')
                      : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _emailCtrl,
                autofillHints: const [AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return LanguageService.t('v_need_email');
                  }
                  if (!v.contains('@')) {
                    return LanguageService.t('v_email_bad');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                autofillHints: _isLogin
                    ? const [AutofillHints.password]
                    : const [AutofillHints.newPassword],
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onEditingComplete: _submit,
                decoration: InputDecoration(
                  labelText: LanguageService.t('password'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return LanguageService.t('v_need_pw');
                  }
                  if (!_isLogin && v.length < 6) {
                    return LanguageService.t('v_pw_short');
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
              ],
              const SizedBox(height: 4),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(() {
                          _isLogin = !_isLogin;
                          _error = null;
                        }),
                child: Text(_isLogin
                    ? LanguageService.t('to_register')
                    : LanguageService.t('to_login')),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: Text(LanguageService.t('cancel')),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_isLogin
                  ? LanguageService.t('login')
                  : LanguageService.t('register')),
        ),
      ],
    );
  }
}
