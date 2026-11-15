import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as image_lib;
import 'package:share_plus/share_plus.dart';
import 'data.dart';
import 'portrait_camera.dart';
import 'staff_auth.dart';
import 'phone_login.dart';

const green = Color(0xFF075648);
const cream = Color(0xFFF8F2E9);
const gold = Color(0xFFBE9650);
const ink = Color(0xFF123C34);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JanFadaApp());
}

class JanFadaApp extends StatelessWidget {
  const JanFadaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'جان فدا | وارثین', debugShowCheckedModeBanner: false,
    locale: const Locale('fa', 'IR'),
    theme: ThemeData(
      useMaterial3: true, scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: green, primary: green, surface: cream),
      appBarTheme: const AppBarTheme(backgroundColor: cream, foregroundColor: ink, centerTitle: true),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
        prefixIconColor: green,
        labelStyle: const TextStyle(color: ink, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: green, fontWeight: FontWeight.w700),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: gold.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(17)),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: green, width: 1.5),
          borderRadius: BorderRadius.circular(17)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(17)),
      ),
    ),
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const SecureGateway(),
  );
}

class SecureGateway extends StatefulWidget {
  const SecureGateway({super.key});
  @override
  State<SecureGateway> createState() => _SecureGatewayState();
}
class _SecureGatewayState extends State<SecureGateway> with WidgetsBindingObserver {
  static const vault = FlutterSecureStorage();
  final pin = TextEditingController();
  final confirm = TextEditingController();
  String? stored;
  String? error;
  bool phoneReady = false;
  bool unlocked = false, loading = true, initializing = false;
  int attempts = 0;
  DateTime? backgroundedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) backgroundedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && unlocked && backgroundedAt != null &&
        DateTime.now().difference(backgroundedAt!).inMinutes >= 2) {
      if (mounted) setState(() => unlocked = false);
    }
  }

  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this); _load();
  }
  Future<void> _load() async {
    try {
      stored = await vault.read(key: 'operator_pin_hash_v1');
      phoneReady = (await StaffAuth.instance.token())?.isNotEmpty ?? false;
    } catch (_) { error = 'دسترسی به حافظه امن ممکن نیست.'; }
    if (mounted) setState(() => loading = false);
  }
  Future<String> _hash(String value, String salt) async {
    final digest = await Sha256().hash('$salt:$value'.codeUnits);
    return digest.bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }
  Future<void> _submit() async {
    if (initializing) return;
    final code = pin.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) { setState(() => error = 'رمز باید شش رقم باشد.'); return; }
    setState(() { initializing = true; error = null; });
    try {
      if (stored == null) {
        if (code != confirm.text.trim()) throw Exception('تکرار رمز یکسان نیست.');
        final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
        stored = '$salt:${await _hash(code, salt)}';
        await vault.write(key: 'operator_pin_hash_v1', value: stored);
      } else {
        final idx = stored!.indexOf(':');
        if (idx < 1 || await _hash(code, stored!.substring(0, idx)) != stored!.substring(idx + 1)) {
          attempts++;
          throw Exception(attempts >= 5 ? 'ورود ناموفق مکرر؛ اپ را ببندید و مجدد تلاش کنید.' : 'رمز اشتباه است.');
        }
      }
      if (attempts >= 5) throw Exception('ورود موقتاً محدود شده است.');
      await LocalStore.instance.initialize();
      pin.clear(); confirm.clear();
      if (mounted) setState(() => unlocked = true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => initializing = false); }
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); pin.dispose(); confirm.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (unlocked) return Dashboard(onSignOut: () { if (mounted) setState(() { unlocked = false; phoneReady = false; }); });
    if (!loading && !phoneReady) return PhoneLogin(onAuthenticated: () { if (mounted) setState(() => phoneReady = true); });
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 390), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.local_florist_outlined, size: 56, color: gold), const SizedBox(height: 14),
          const Text('جان فدا | وارثین', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900, color: ink)),
          const SizedBox(height: 6), const Text('ثبت‌نام و مدیریت پرونده‌های میدانی'),
          const SizedBox(height: 30),
          if (loading) const CircularProgressIndicator() else ...[
            Text(stored == null ? 'برای محافظت از اطلاعات، رمز ۶ رقمی تعیین کنید.' : 'رمز مسئول ثبت‌نام را وارد کنید.'),
            const SizedBox(height: 14),
            TextField(controller: pin, keyboardType: TextInputType.number, obscureText: true,
              maxLength: 6, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'رمز ۶ رقمی')),
            if (stored == null) TextField(controller: confirm, keyboardType: TextInputType.number, obscureText: true,
              maxLength: 6, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'تکرار رمز')),
            if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: initializing || attempts >= 5 ? null : _submit,
              child: Text(initializing ? 'در حال بررسی...' : 'ورود به ثبت‌نام'),
            )),
            const SizedBox(height: 10),
            const Text('اطلاعات و عکس‌ها رمزنگاری می‌شوند. رمز را به خاطر بسپارید.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 12)),
          ],
        ],
      )),
    ))));
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.onSignOut});
  final VoidCallback onSignOut;
  @override State<Dashboard> createState() => _DashboardState();
}
class _DashboardState extends State<Dashboard> {
  final store = LocalStore.instance;
  late final syncService = FormSync(store);
  StreamSubscription<List<ConnectivityResult>>? internetSubscription;
  Timer? retryTimer;
  List<Registrant> people = [];
  int selected = 0;
  bool syncing = false, exporting = false, online = false;

  @override
  void initState() {
    super.initState(); _refresh();
    Connectivity().checkConnectivity().then(_connectivityChanged);
    internetSubscription = Connectivity().onConnectivityChanged.listen(_connectivityChanged);
    retryTimer = Timer.periodic(const Duration(minutes: 10), (_) { if (online && !syncing) _sync(); });
  }
  void _connectivityChanged(List<ConnectivityResult> options) {
    if (!mounted) return;
    final wasOnline = online;
    setState(() => online = options.any((v) => v != ConnectivityResult.none));
    if (online && !wasOnline) _sync();
  }
  Future<void> _refresh() async { final list = await store.all(); if (mounted) setState(() => people = list); }
  Future<void> _sync() async {
    if (syncing || !online) return;
    if ((await StaffAuth.instance.token() ?? '').isEmpty) {
      if (mounted) await _phoneLogin();
      if ((await StaffAuth.instance.token() ?? '').isEmpty) return;
    }
    if (!mounted) return;
    setState(() => syncing = true);
    final result = await syncService.sync();
    await _refresh();
    if (mounted) {
      setState(() => syncing = false);
      if (result.$1 > 0 || result.$2 > 0) _info('${result.$1} پرونده ارسال شد؛ ${result.$2} مورد نیازمند تلاش مجدد است.');
    }
  }
  void _info(String message) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  Future<void> _phoneLogin() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (loginContext) => PhoneLogin(
        onAuthenticated: () => Navigator.of(loginContext).pop(),
      )));
  }

  Future<void> _staffSettings() async {
    if (!mounted) return;
    final phone = await StaffAuth.instance.mobile();
    if (!mounted) return;
    final action = await showDialog<String>(context: context, builder: (ctx) =>
      AlertDialog(title: const Text('حساب مسئول ثبت‌نام'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified_user_outlined, color: green, size: 42),
          const SizedBox(height: 10),
          Text(phone ?? 'ورود انجام نشده است', textDirection: TextDirection.ltr),
          const SizedBox(height: 12),
          const Text('دسترسی این شماره توسط مدیر سایت وارثین تعیین می‌شود. رمز اتصال مشترک نیاز نیست.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          FilledButton.tonal(onPressed: () => Navigator.pop(ctx, 'logout'),
            child: const Text('خروج و تغییر شماره')),
        ],
      ));
    if (action == 'logout') {
      await StaffAuth.instance.logout();
      if (mounted) widget.onSignOut();
    }
  }

  Future<void> _export() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final result = await DossierExporter(store).export();
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        text: 'خروجی ثبت‌نام پویش جان‌فدا ـ اکسل و بسته کامل تصاویر',
        files: [XFile(result.xlsx.path), XFile(result.zip.path)],
      ));
    } catch (e) { if (mounted) _info('خطا در ساخت اکسل: $e'); }
    finally { if (mounted) setState(() => exporting = false); }
  }
  @override
  void dispose() { internetSubscription?.cancel(); retryTimer?.cancel(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final pending = people.where((p) => p.status != 'synced').length;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        titleSpacing: 4,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('جان فدا | وارثین', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: ink)),
            SizedBox(height: 4),
            Text('شناسایی نیرو برای جذب در گردان امام حسین(ع)',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: ink)),
          ]),
        actions: [
          IconButton(onPressed: _staffSettings, icon: const Icon(Icons.admin_panel_settings_outlined), tooltip: 'حساب مسئول ثبت‌نام'),
          Padding(padding: const EdgeInsetsDirectional.only(end: 12), child: Tooltip(message: online ? 'شبکه متصل' : 'آفلاین',
            child: Icon(online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              color: online ? green : Colors.deepOrange))),
        ]),
      body: SafeArea(child: Column(children: [
        Container(width: double.infinity, margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          padding: const EdgeInsets.all(16), decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [green, Color(0xFF0C4747)]),
            borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('وضعیت ثبت‌نام‌ها', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 12),
            Row(children: [
              _counter('کل ثبت‌نام‌ها', people.length.toString()),
              const SizedBox(width: 12),
              _counter('در انتظار ارسال', pending.toString()),
              const SizedBox(width: 12),
              _counter('ثبت‌شده در سایت', (people.length - pending).toString()),
            ]),
          ])),
        Expanded(child: selected == 0
          ? RegistrationForm(onSaved: () async { await _refresh(); if (online) _sync(); })
          : RecordsView(people: people, onSync: _sync, syncing: syncing,
              export: _export, exporting: exporting, onReload: _refresh)),
      ])),
      bottomNavigationBar: NavigationBar(
        height: 74, backgroundColor: Colors.white, selectedIndex: selected,
        onDestinationSelected: (v) => setState(() => selected = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.person_add_alt_1_outlined), selectedIcon: Icon(Icons.person_add_alt_1), label: 'ثبت‌نام جدید'),
          NavigationDestination(icon: Icon(Icons.folder_copy_outlined), selectedIcon: Icon(Icons.folder_copy), label: 'پرونده‌ها و اکسل'),
        ],
      ),
    );
  }
  Widget _counter(String label, String value) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
    Text(label, style: const TextStyle(color: Color(0xFFE8EFEB), fontSize: 11)),
  ]));
}

class RegistrationForm extends StatefulWidget {
  const RegistrationForm({super.key, required this.onSaved, this.initial});
  final VoidCallback onSaved;
  final Registrant? initial;
  @override State<RegistrationForm> createState() => _RegistrationFormState();
}
class _RegistrationFormState extends State<RegistrationForm> {
  final key = GlobalKey<FormState>();
  final controllers = <String, TextEditingController>{
    for (final name in ['first_name','last_name','father_name','mobile','birth_date','city','address','notes'])
      name: TextEditingController(),
  };
  Uint8List? image;
  bool consent = false, saving = false;
  final picker = ImagePicker();
  @override
  void initState() {
    super.initState();
    final old = widget.initial;
    if (old != null) {
      for (final item in controllers.entries) { item.value.text = old.data[item.key] ?? ''; }
      consent = true;
      LocalStore.instance.readImage(old.photo).then((data) {
        if (mounted) setState(() => image = data);
      }).catchError((Object _) {});
    }
  }
  Future<void> guidedPhoto() async {
    final jpeg = await Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => const PortraitCamera()));
    if (jpeg != null && mounted) setState(() => image = jpeg);
  }
  Future<void> pick(ImageSource source) async {
    try {
      final result = await picker.pickImage(source: source, maxWidth: 1200, maxHeight: 1600, imageQuality: 75);
      if (result == null) return;
      final bytes = await result.readAsBytes();
      final decodedImage = image_lib.decodeImage(bytes);
      if (decodedImage == null) throw Exception('فرمت عکس پشتیبانی نمی‌شود.');
      final jpeg = Uint8List.fromList(image_lib.encodeJpg(decodedImage, quality: 77));
      if (jpeg.length > 5 * 1024 * 1024) throw Exception('حجم تصویر بیش از ۵ مگابایت است.');
      if (mounted) setState(() => image = jpeg);
      // image_picker caches a copy. Never leave a camera copy unencrypted in our app cache.
      if (result.path.contains('/cache/')) { try { await File(result.path).delete(); } catch (_) {} }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('انتخاب عکس انجام نشد: $e')));
    }
  }
  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    if (image == null) { _message('لطفاً عکس را ثبت کنید.'); return; }
    if (!consent) { _message('رضایت فرد برای ثبت مشخصات و عکس الزامی است.'); return; }
    setState(() => saving = true);
    try {
      final d = {for (final e in controllers.entries) e.key: _digits(e.value.text.trim())};
      if (widget.initial == null && await LocalStore.instance.isDuplicate(d['first_name']!, d['last_name']!, d['mobile']!)) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('احتمال ثبت تکراری'),
          content: const Text('این نام و شماره همراه قبلاً ثبت شده است. باز هم پرونده جدید ساخته شود؟'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت دوباره'))],
        ));
        if (proceed != true) return;
      }
      if (widget.initial == null) {
        await LocalStore.instance.create(d, image!);
        for (final c in controllers.values) { c.clear(); }
        key.currentState?.reset();
        setState(() { image = null; consent = false; });
      } else {
        await LocalStore.instance.edit(widget.initial!, d, image!);
      }
      if (mounted) _message('پرونده در گوشی ذخیره شد.');
      widget.onSaved();
    } catch (e) { _message('ذخیره ناموفق بود: $e'); }
    finally { if (mounted) setState(() => saving = false); }
  }
  String _digits(String value) => value.replaceAllMapped(RegExp(r'[۰-۹٠-٩]'), (m) {
    final c = m.group(0)!.codeUnitAt(0);
    return ((c >= 0x6f0 && c <= 0x6f9) ? c - 0x6f0 : c - 0x660).toString();
  });
  void _message(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Widget field(String name, String label, {bool required = false, int lines = 1, TextInputType? type, String? hint}) =>
    Padding(padding: const EdgeInsets.only(bottom: 13), child: TextFormField(
      controller: controllers[name], keyboardType: type, maxLines: lines,
      textDirection: name == 'mobile' ? TextDirection.ltr : TextDirection.rtl,
      decoration: InputDecoration(
        labelText: label, hintText: hint,
        prefixIcon: Icon({
          'first_name': Icons.person_outline,
          'last_name': Icons.badge_outlined,
          'father_name': Icons.people_outline,
          'mobile': Icons.phone_android_outlined,
          'birth_date': Icons.calendar_month_outlined,
          'city': Icons.place_outlined,
          'address': Icons.home_outlined,
          'notes': Icons.notes_outlined,
        }[name] ?? Icons.edit_outlined, size: 22),
      ),
      validator: (val) {
        final v = (val ?? '').trim();
        if (required && v.isEmpty) return 'این مورد الزامی است';
        if (name == 'mobile' && !RegExp(r'^09\d{9}$').hasMatch(_digits(v))) return 'شماره همراه باید ۱۱ رقم و با ۰۹ آغاز شود';
        if (name == 'birth_date' && v.isNotEmpty && !RegExp(r'^(13|14)\d{2}/(0?[1-9]|1[0-2])/(0?[1-9]|[12]\d|3[01])$').hasMatch(_digits(v))) return 'مثال: ۱۳۸۵/۰۵/۱۵';
        return null;
      },
    ));
  @override void dispose() { for (final c in controllers.values) { c.dispose(); } super.dispose(); }

  @override Widget build(BuildContext context) => Form(key: key, child: Center(
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 660), child: ListView(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24), children: [
      const Padding(padding: EdgeInsetsDirectional.only(start: 6),
        child: Row(children: [
          Icon(Icons.edit_note_outlined, color: gold, size: 25),
          SizedBox(width: 8),
          Text('مشخصات فردی', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: ink)),
        ])),
      const SizedBox(height: 12),
      field('first_name', 'نام *', required: true),
      field('last_name', 'نام خانوادگی *', required: true),
      field('father_name', 'نام پدر'),
      field('mobile', 'شماره همراه *', required: true, type: TextInputType.phone),
      field('birth_date', 'تاریخ تولد شمسی', hint: '۱۳۸۵/۰۵/۱۵'),
      field('city', 'شهر یا روستا *', required: true),
      field('address', 'نشانی', lines: 2),
      field('notes', 'توضیحات', lines: 3),
      const SizedBox(height: 5), const Text('عکس فرد *', style: TextStyle(fontWeight: FontWeight.bold, color: ink)),
      const SizedBox(height: 8),
      Container(height: 190, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: gold.withValues(alpha: .5)), borderRadius: BorderRadius.circular(14)),
        child: image == null ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_a_photo_outlined, size: 42, color: gold), SizedBox(height: 8), Text('عکس هنوز انتخاب نشده است')]))
          : ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(image!, fit: BoxFit.contain)),
      ),
      const SizedBox(height: 10),
      const Text('دوربین هوشمند وضعیت چهره، نور و وضوح را با درصد نمایش می‌دهد. وقتی دور کادر کاملاً سبز شد عکس بگیرید.', style: TextStyle(fontSize: 12, color: ink)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: guidedPhoto, icon: const Icon(Icons.camera_alt_outlined), label: const Text('دوربین هوشمند'))),
        const SizedBox(width: 9),
        Expanded(child: OutlinedButton.icon(onPressed: () => pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('گالری'))),
      ]),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero, value: consent, activeColor: green,
        title: const Text('فرد با ثبت و نگهداری مشخصات و تصویر خود برای مدیریت پویش موافقت کرده است.', style: TextStyle(fontSize: 13)),
        onChanged: (v) => setState(() => consent = v ?? false),
      ),
      const SizedBox(height: 6),
      FilledButton.icon(onPressed: saving ? null : save,
        icon: const Icon(Icons.save_alt_outlined), label: Text(saving ? 'در حال ذخیره‌سازی...' : (widget.initial == null ? 'ثبت و ذخیره پرونده' : 'ذخیره تغییرات'))),
      const SizedBox(height: 8),
      const Text('در حالت آفلاین اطلاعات روی گوشی ذخیره می‌شود. پس از ارسال موفق در سایت، پیامک تأیید برای شماره همراه ارسال می‌شود. متن پیامک از پنل مدیریت قابل تنظیم است.',
        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
    ],
  )));
}

class RecordsView extends StatefulWidget {
  const RecordsView({super.key, required this.people, required this.onSync, required this.syncing, required this.export, required this.exporting, required this.onReload});
  final List<Registrant> people;
  final Future<void> Function() onSync;
  final bool syncing;
  final Future<void> Function() export;
  final bool exporting;
  final Future<void> Function() onReload;
  @override State<RecordsView> createState() => _RecordsViewState();
}
class _RecordsViewState extends State<RecordsView> {
  String filter = '';
  @override Widget build(BuildContext context) {
    final items = widget.people.where((p) => p.name.contains(filter) || p.mobile.contains(filter) || p.code.contains(filter)).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: TextField(
        onChanged: (v) => setState(() => filter = v.trim()),
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'جست‌وجو نام، تلفن یا کد رهگیری'),
      )),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7), child: Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: widget.syncing ? null : widget.onSync,
          icon: widget.syncing ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
          label: const Text('همگام‌سازی'),
        )),
        const SizedBox(width: 8),
        Expanded(child: FilledButton.icon(
          onPressed: widget.exporting || items.isEmpty ? null : widget.export,
          icon: const Icon(Icons.table_view_outlined), label: const Text('خروجی اکسل'),
        )),
      ])),
      Expanded(child: items.isEmpty ? const Center(child: Text('هنوز پرونده‌ای ثبت نشده است.')) : ListView.builder(
        itemCount: items.length, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemBuilder: (ctx, i) {
          final r = items[i]; final saved = r.status == 'synced';
          return Card(color: Colors.white, elevation: 0, child: ListTile(
            leading: CircleAvatar(backgroundColor: saved ? const Color(0xFFE5F3EF) : const Color(0xFFFDF0D8),
              child: Icon(saved ? Icons.cloud_done : Icons.cloud_upload_outlined, color: saved ? green : gold)),
            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${r.mobile}   •   ${saved ? 'ثبت‌شده در سایت' : 'در انتظار ارسال'}${r.code.isEmpty ? '' : '\nکد: ${r.code}'}'),
            isThreeLine: r.code.isNotEmpty,
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordDetail(record: r, onEdited: widget.onReload))),
          ));
        },
      )),
    ]);
  }
}

class RecordDetail extends StatefulWidget {
  const RecordDetail({super.key, required this.record, required this.onEdited});
  final Registrant record;
  final Future<void> Function() onEdited;
  @override State<RecordDetail> createState() => _RecordDetailState();
}
class _RecordDetailState extends State<RecordDetail> {
  Uint8List? photo;
  @override void initState() { super.initState(); LocalStore.instance.readImage(widget.record.photo).then((p) {
    if (mounted) setState(() => photo = p);
  }).catchError((Object _) {}); }
  @override Widget build(BuildContext context) {
    final r = widget.record;
    final labels = {'first_name':'نام', 'last_name':'نام خانوادگی', 'father_name':'نام پدر', 'mobile':'شماره همراه',
      'birth_date':'تاریخ تولد', 'city':'شهر / روستا', 'address':'نشانی', 'activity':'حوزه همکاری', 'notes':'توضیحات'};
    return Scaffold(appBar: AppBar(title: Text('پرونده ${r.name}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (photo != null) ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.memory(photo!, height: 230)),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('شناسه آفلاین: ${r.id}', style: const TextStyle(fontSize: 12)),
          Text('کد نگارفرم: ${r.code.isEmpty ? 'هنوز ثبت نشده' : r.code}'),
          Text(r.status == 'synced' ? 'وضعیت: ارسال شده' : 'وضعیت: در انتظار ارسال', style: TextStyle(color: r.status == 'synced' ? green : Colors.deepOrange)),
          if (r.error.isNotEmpty) Text(r.error, style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
        ]))),
        if (r.status != 'synced') Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: FilledButton.icon(
            icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش پرونده آفلاین'),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (editContext) => Scaffold(
                appBar: AppBar(title: const Text('ویرایش پرونده آفلاین')),
                body: RegistrationForm(initial: r, onSaved: () async {
                  await widget.onEdited();
                  if (editContext.mounted) Navigator.pop(editContext);
                  if (context.mounted) Navigator.pop(context);
                }),
              )));
            },
          ),
        ),
        ...labels.entries.map((e) => Card(child: ListTile(title: Text(e.value), subtitle: Text(r.data[e.key] ?? '—')))),
      ]),
    );
  }
}
