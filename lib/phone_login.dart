import 'dart:async';
import 'package:flutter/material.dart';
import 'staff_auth.dart';

/// Operator access is granted by site administrator via a mobile number.
/// OTP is only used at login; the secure session is stored by StaffAuth.
class PhoneLogin extends StatefulWidget {
  const PhoneLogin({super.key, required this.onAuthenticated});
  final VoidCallback onAuthenticated;
  @override State<PhoneLogin> createState() => _PhoneLoginState();
}

class _PhoneLoginState extends State<PhoneLogin> {
  final _mobile = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false, _working = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override void dispose() {
    _timer?.cancel();
    _mobile.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_working || _cooldown > 0) return;
    setState(() { _working = true; _error = null; });
    try {
      await StaffAuth.instance.requestCode(_mobile.text);
      if (!mounted) return;
      setState(() { _sent = true; _cooldown = 90; });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) { timer.cancel(); return; }
        setState(() { _cooldown -= 1; });
        if (_cooldown <= 0) timer.cancel();
      });
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _working = false); }
  }

  Future<void> _verify() async {
    if (_working) return;
    setState(() { _working = true; _error = null; });
    try {
      await StaffAuth.instance.verifyCode(_mobile.text, _code.text);
      if (mounted) widget.onAuthenticated();
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _working = false); }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ورود مسئول ثبت‌نام'), centerTitle: true),
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 410),
        child: Card(elevation: 0, color: Colors.white, child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircleAvatar(radius: 36, backgroundColor: Color(0xFFE5F1ED),
              child: Icon(Icons.verified_user_outlined,
                size: 40, color: Color(0xFF165F5A))),
            const SizedBox(height: 12),
            const Text('جان فدا | وارثین',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            const Text('ورود با شماره همراهِ مجاز در سایت',
              textAlign: TextAlign.center),
            const SizedBox(height: 18),
            TextField(controller: _mobile, textDirection: TextDirection.ltr,
              keyboardType: TextInputType.phone,
              enabled: !_sent && !_working, maxLength: 11,
              decoration: const InputDecoration(
                labelText: 'شماره همراه مسئول',
                prefixIcon: Icon(Icons.phone_android),
                hintText: '09123456789')),
            if (_sent) ...[
              const SizedBox(height: 8),
              TextField(controller: _code, textDirection: TextDirection.ltr,
                keyboardType: TextInputType.number, maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'کد ۶ رقمی پیامک شده',
                  prefixIcon: Icon(Icons.sms_outlined))),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.all(10),
              child: Text(_error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _working ? null : (_sent ? _verify : _send),
              icon: Icon(_sent ? Icons.login : Icons.sms),
              label: Text(_working ? 'در حال بررسی…' :
                (_sent ? 'ورود به اپ' : 'دریافت کد پیامکی')))),
            if (_sent) ...[
              TextButton(
                onPressed: _working || _cooldown > 0 ? null : _send,
                child: Text(_cooldown > 0 ?
                  'ارسال دوباره تا $_cooldown ثانیه' : 'ارسال مجدد کد')),
              TextButton(
                onPressed: _working ? null : () => setState(() {
                  _sent = false; _code.clear(); _error = null;
                }), child: const Text('اصلاح شماره همراه')),
            ],
            const Divider(height: 25),
            const Text('مدیر سایت ابتدا باید شماره شما را در بخش «مسئولان جان‌فدا» مجاز کند. دریافت کد پیامکی به اینترنت نیاز دارد؛ ثبت‌نام پس از ورود اولیه، آفلاین نیز امکان‌پذیر است.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        )),
      ),
    ))),
  );
}
