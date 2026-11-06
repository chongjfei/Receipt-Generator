import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Currency shown on the receipt amount.
const String kCurrency = 'RM';

/// Global store for saved business profiles.
final ProfileStore store = ProfileStore();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  runApp(const ReceiptApp());
}

// ===========================================================================
// APP THEME (app UI uses the teal brand; each receipt uses its business color)
// ===========================================================================
class AppColors {
  static const teal = Color(0xFF0E8F82);
  static const deepTeal = Color(0xFF08786D);
  static const gold = Color(0xFFF8E692);
  static const background = Color(0xFFF5FAF9);
  static const text = Color(0xFF183C38);
}

class ReceiptApp extends StatelessWidget {
  const ReceiptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.teal).copyWith(
          primary: AppColors.teal,
          onPrimary: Colors.white,
          primaryContainer: AppColors.gold,
          onPrimaryContainer: AppColors.deepTeal,
          secondary: AppColors.deepTeal,
          surface: AppColors.background,
          onSurface: AppColors.text,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.teal,
          foregroundColor: Colors.white,
        ),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: AppColors.text,
              displayColor: AppColors.text,
            ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.teal, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.teal,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: const ReceiptFormPage(),
    );
  }
}

// ===========================================================================
// HELPERS
// ===========================================================================
const _ms = [
  'Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun',
  'Jul', 'Ogos', 'Sep', 'Okt', 'Nov', 'Dis',
];

/// Malay short date, e.g. "15 Okt 2026".
String fmtDate(DateTime d) => '${d.day} ${_ms[d.month - 1]} ${d.year}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String? _req(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Required' : null;

String? _amountValidator(String? v) {
  final n = double.tryParse((v ?? '').trim());
  return (n == null || n < 0) ? 'Enter a valid amount' : null;
}

// ===========================================================================
// MODELS
// ===========================================================================
class BusinessProfile {
  final String id;
  String name;
  String address;
  String phone;
  String website;
  String social;
  String noticeTitle;
  String terms; // one point per line, **bold** supported
  int brandColor;
  String? logoB64;
  String? signatureB64;

  // Receipt numbering
  bool randomNumbering;
  String prefix;
  int nextNumber;

  BusinessProfile({
    required this.id,
    required this.name,
    this.address = '',
    this.phone = '',
    this.website = '',
    this.social = '',
    this.noticeTitle = 'PERHATIAN !',
    this.terms = '',
    this.brandColor = 0xFF0B4FA8,
    this.logoB64,
    this.signatureB64,
    this.randomNumbering = false,
    this.prefix = '',
    this.nextNumber = 1,
  });

  Color get color => Color(brandColor);
  Uint8List? get logoBytes =>
      logoB64 == null ? null : base64Decode(logoB64!);
  Uint8List? get signatureBytes =>
      signatureB64 == null ? null : base64Decode(signatureB64!);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'phone': phone,
        'website': website,
        'social': social,
        'noticeTitle': noticeTitle,
        'terms': terms,
        'brandColor': brandColor,
        'logoB64': logoB64,
        'signatureB64': signatureB64,
        'randomNumbering': randomNumbering,
        'prefix': prefix,
        'nextNumber': nextNumber,
      };

  factory BusinessProfile.fromJson(Map<String, dynamic> j) => BusinessProfile(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        address: (j['address'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        website: (j['website'] ?? '') as String,
        social: (j['social'] ?? '') as String,
        noticeTitle: (j['noticeTitle'] ?? 'PERHATIAN !') as String,
        terms: (j['terms'] ?? '') as String,
        brandColor: (j['brandColor'] ?? 0xFF0B4FA8) as int,
        logoB64: j['logoB64'] as String?,
        signatureB64: j['signatureB64'] as String?,
        randomNumbering: (j['randomNumbering'] ?? false) as bool,
        prefix: (j['prefix'] ?? '') as String,
        nextNumber: (j['nextNumber'] ?? 1) as int,
      );

  /// Starter profile created on first launch (edit or delete it freely).
  factory BusinessProfile.sample() => BusinessProfile(
        id: 'sample',
        name: "Homestay Astana Ria D'Raja",
        address: 'Lot 16786, Jln Tuanku Antah, Jln Rahang Kecil,\n'
            'Kg Semarak, Seremban, Negeri Sembilan',
        phone: '+60 10-325 7723',
        website: 'www.astanariadraja.com',
        social: '@astana_ria_draja',
        noticeTitle: 'PERHATIAN !',
        terms: 'Tahniah! Tempahan anda telah berjaya.\n'
            'Bayaran deposit mengesahkan tempahan anda untuk tarikh yang '
            'dipilih. Kami tidak akan menerima tempahan dari bakal penyewa '
            'lain untuk tarikh yang telah kami khususkan untuk anda tersebut. '
            'Bayaran deposit **TIDAK AKAN DIKEMBALIKAN** sekiranya berlaku '
            '**PEMBATALAN**.\n'
            'Sebarang pertukaran tarikh penginapan adalah '
            '**TIDAK DIBENARKAN**.\n'
            'Sekiranya berlaku sebarang **KEROSAKAN**, kos ganti rugi akan '
            'ditolak dari wang deposit dan selebihnya akan dipulangkan semula.',
      );
}

class ReceiptData {
  final BusinessProfile business;
  final String receiptNo;
  final DateTime issuedAt;
  final String customer;
  final DateTime stayStart;
  final DateTime stayEnd;
  final String duration;
  final String package;
  final double amount;
  final String payment;

  const ReceiptData({
    required this.business,
    required this.receiptNo,
    required this.issuedAt,
    required this.customer,
    required this.stayStart,
    required this.stayEnd,
    required this.duration,
    required this.package,
    required this.amount,
    required this.payment,
  });

  String get issuedText => fmtDate(issuedAt);
  String get stayText => _sameDay(stayStart, stayEnd)
      ? fmtDate(stayStart)
      : '${fmtDate(stayStart)} - ${fmtDate(stayEnd)}';
  String get amountText => '$kCurrency ${amount.toStringAsFixed(2)}';
}

// ===========================================================================
// STORAGE (shared_preferences)
// ===========================================================================
class ProfileStore extends ChangeNotifier {
  List<BusinessProfile> profiles = [];
  String? selectedId;
  SharedPreferences? _prefs;

  BusinessProfile? get selected {
    for (final p in profiles) {
      if (p.id == selectedId) return p;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString('profiles');
    if (raw == null) {
      profiles = [BusinessProfile.sample()]; // first launch only
    } else {
      try {
        profiles = (jsonDecode(raw) as List)
            .map((e) => BusinessProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        profiles = [];
      }
    }
    selectedId = _prefs!.getString('selectedId');
    if (raw == null) await save();
  }

  Future<void> save() async {
    await _prefs?.setString(
        'profiles', jsonEncode(profiles.map((p) => p.toJson()).toList()));
    if (selectedId != null) {
      await _prefs?.setString('selectedId', selectedId!);
    }
    notifyListeners();
  }

  Future<void> upsert(BusinessProfile p) async {
    final i = profiles.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      profiles[i] = p;
    } else {
      profiles.add(p);
      selectedId = p.id;
    }
    await save();
  }

  Future<void> remove(String id) async {
    profiles.removeWhere((p) => p.id == id);
    if (selectedId == id) {
      selectedId = profiles.isEmpty ? null : profiles.first.id;
    }
    await save();
  }

  Future<void> select(String id) async {
    selectedId = id;
    await save();
  }
}

// ===========================================================================
// PAGE 1: FORM
// ===========================================================================
class ReceiptFormPage extends StatefulWidget {
  const ReceiptFormPage({super.key});

  @override
  State<ReceiptFormPage> createState() => _ReceiptFormPageState();
}

class _ReceiptFormPageState extends State<ReceiptFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _customer = TextEditingController();
  final _duration = TextEditingController();
  final _package = TextEditingController();
  final _amount = TextEditingController();
  final _payment = TextEditingController(text: 'Deposit');
  static const _paymentOptions = ['Deposit', 'Bayaran Penuh', 'Baki'];

  DateTimeRange? _stay;

  // Receipt number handling
  String? _issuedNo; // locked once the receipt has been generated
  String? _randomNo; // preview for random mode

  @override
  void dispose() {
    for (final c in [_customer, _duration, _package, _amount, _payment]) {
      c.dispose();
    }
    super.dispose();
  }

  String _displayNo(BusinessProfile p) {
    if (_issuedNo != null) return _issuedNo!;
    if (p.randomNumbering) {
      return _randomNo ??=
          '${p.prefix}${100000 + Random().nextInt(900000)}';
    }
    return '${p.prefix}${p.nextNumber}';
  }

  String _durationLabel(DateTimeRange r) {
    final nights = r.end.difference(r.start).inDays;
    return '${nights + 1}H${nights}M'; // e.g. 2H1M = 2 hari 1 malam
  }

  Future<void> _pickStay() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _stay,
    );
    if (r != null) {
      setState(() {
        _stay = r;
        _duration.text = _durationLabel(r);
      });
    }
  }

  Future<void> _submit(BusinessProfile p) async {
    if (!_formKey.currentState!.validate()) return;

    final no = _displayNo(p);
    if (_issuedNo == null) {
      _issuedNo = no;
      if (!p.randomNumbering) {
        p.nextNumber += 1; // increment for the next receipt
        await store.save();
      }
    }

    final data = ReceiptData(
      business: p,
      receiptNo: no,
      issuedAt: DateTime.now(), // auto date
      customer: _customer.text.trim(),
      stayStart: _stay!.start,
      stayEnd: _stay!.end,
      duration: _duration.text.trim(),
      package: _package.text.trim(),
      amount: double.parse(_amount.text.trim()),
      payment: _payment.text.trim(),
    );

    if (!mounted) return;
    final startNew = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReceiptPage(data: data)),
    );
    if (startNew == true) _resetForm();
  }

  void _resetForm() {
    setState(() {
      _customer.clear();
      _duration.clear();
      _package.clear();
      _amount.clear();
      _payment.text = 'Deposit';
      _stay = null;
      _issuedNo = null;
      _randomNo = null;
    });
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.deepTeal,
              ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.selected;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Receipt Generator'),
            actions: [
              IconButton(
                tooltip: 'Manage businesses',
                icon: const Icon(Icons.storefront),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfilesPage()),
                ),
              ),
            ],
          ),
          body: p == null ? _emptyState() : _form(p),
        );
      },
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront, size: 56, color: AppColors.teal),
              const SizedBox(height: 12),
              const Text('Add your business details first.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ProfileEditorPage()),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add business'),
              ),
            ],
          ),
        ),
      );

  Widget _form(BusinessProfile p) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _section('Business'),
          DropdownButtonFormField<String>(
            key: ValueKey(p.id),
            initialValue: p.id,
            decoration: const InputDecoration(labelText: 'Issue receipt as'),
            items: store.profiles
                .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                .toList(),
            onChanged: (id) {
              if (id == null) return;
              setState(() {
                _issuedNo = null;
                _randomNo = null;
              });
              store.select(id);
            },
          ),
          const SizedBox(height: 10),

          // Auto fields (read-only)
          Row(
            children: [
              Expanded(child: _autoChip('Receipt no.', _displayNo(p))),
              const SizedBox(width: 10),
              Expanded(child: _autoChip('Date', fmtDate(DateTime.now()))),
            ],
          ),

          _section('Booking details'),
          TextFormField(
            controller: _customer,
            decoration: const InputDecoration(labelText: 'Name (Nama)'),
            textCapitalization: TextCapitalization.characters,
            validator: _req,
          ),
          const SizedBox(height: 10),
          FormField<DateTimeRange>(
            validator: (_) => _stay == null ? 'Select stay dates' : null,
            builder: (state) => InkWell(
              onTap: () async {
                await _pickStay();
                state.validate();
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Stay dates (Tarikh)',
                  errorText: state.errorText,
                  suffixIcon: const Icon(Icons.date_range, size: 20),
                ),
                child: Text(
                  _stay == null
                      ? 'Tap to select check-in & check-out'
                      : (_sameDay(_stay!.start, _stay!.end)
                          ? fmtDate(_stay!.start)
                          : '${fmtDate(_stay!.start)} - ${fmtDate(_stay!.end)}'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _package,
                  decoration:
                      const InputDecoration(labelText: 'Package (Pakej)'),
                  validator: _req,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _duration,
                  decoration: const InputDecoration(
                    labelText: 'Stay (Penginapan)',
                    helperText: 'Auto from dates, editable',
                  ),
                  validator: _req,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _amount,
            decoration: const InputDecoration(
              labelText: 'Amount (Jumlah)',
              prefixText: '$kCurrency ',
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            validator: _amountValidator,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _payment,
            decoration: const InputDecoration(labelText: 'Payment (Bayaran)'),
            validator: _req,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final o in _paymentOptions)
                ActionChip(
                  label: Text(o),
                  onPressed: () => setState(() => _payment.text = o),
                ),
            ],
          ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _submit(p),
            icon: const Icon(Icons.receipt_long),
            label: const Text('Generate receipt'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ],
      ),
    );
  }

  Widget _autoChip(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.gold.withAlpha(110),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label (auto)', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      );
}

// ===========================================================================
// PAGE 2: RECEIPT + EXPORT
// ===========================================================================
class ReceiptPage extends StatefulWidget {
  final ReceiptData data;
  const ReceiptPage({super.key, required this.data});

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  final GlobalKey _boundaryKey = GlobalKey();

  String get _fileName {
    final safe =
        widget.data.receiptNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'receipt_$safe.pdf';
  }

  /// Renders exactly what is on screen to a high-resolution PNG.
  Future<Uint8List> _capturePng() async {
    final boundary = _boundaryKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  Future<Uint8List> _buildPdf() async {
    final png = await _capturePng();
    final doc = pw.Document();
    final img = pw.MemoryImage(png);
    // Same aspect ratio as the receipt sheet (800 x 690)
    final format = PdfPageFormat(595, 595 * ReceiptSheet.h / ReceiptSheet.w);
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(img, fit: pw.BoxFit.fill),
        ),
      ),
    );
    return doc.save();
  }

  Future<void> _export() async {
    try {
      await Printing.sharePdf(bytes: await _buildPdf(), filename: _fileName);
    } catch (e) {
      _toast('Export failed: $e');
    }
  }

  Future<void> _preview() async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) => _buildPdf(),
        name: _fileName,
      );
    } catch (e) {
      _toast('Print failed: $e');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Receipt ${widget.data.receiptNo}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 12,
                          offset: Offset(0, 4)),
                    ],
                  ),
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: ReceiptSheet(data: widget.data),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _export,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Export PDF'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _preview,
                      icon: const Icon(Icons.print),
                      label: const Text('Print / Preview'),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit details'),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.add),
                      label: const Text('New receipt'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// THE RECEIPT TEMPLATE (fixed 800 x 690 design, scaled to any screen)
// ===========================================================================
class ReceiptSheet extends StatelessWidget {
  static const double w = 800;
  static const double h = 690;

  final ReceiptData data;
  const ReceiptSheet({super.key, required this.data});

  static const _ink = Color(0xFF1A1A1A);
  static const _lineGrey = Color(0xFF8A8A8A);
  static const _noticeGold = Color(0xFFFFD84A);

  @override
  Widget build(BuildContext context) {
    final b = data.business;
    final brand = b.color;
    final logo = b.logoBytes;
    final sig = b.signatureBytes;

    return SizedBox(
      width: w,
      height: h,
      child: ColoredBox(
        color: Colors.white,
        child: DefaultTextStyle(
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            decoration: TextDecoration.none,
            fontWeight: FontWeight.normal,
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Watermark
              Positioned(
                left: 90,
                right: 90,
                top: 225,
                height: 260,
                child: Center(
                  child: Opacity(
                    opacity: 0.05,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: 620,
                        child: Text(
                          b.name.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 84,
                            height: 1.05,
                            color: brand,
                            fontFamilyFallback: const [
                              'Times New Roman',
                              'Georgia',
                              'serif',
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Header: name, address, phone
              Positioned(
                left: 41,
                top: 34,
                width: 540,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    b.name,
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                      color: brand,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 41,
                top: 72,
                width: 540,
                height: 56,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 540,
                    child: Text(
                      b.address,
                      style: const TextStyle(fontSize: 18, height: 1.45),
                    ),
                  ),
                ),
              ),
              if (b.phone.isNotEmpty)
                Positioned(
                  left: 41,
                  top: 130,
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFF25D366),
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          'WA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(b.phone, style: const TextStyle(fontSize: 19)),
                    ],
                  ),
                ),

              // No + Tarikh (auto)
              Positioned(
                left: 41,
                top: 160,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('No:', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    _Dotted(width: 96, value: data.receiptNo),
                    const SizedBox(width: 10),
                    const Text('Tarikh:', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    _Dotted(width: 150, value: data.issuedText),
                  ],
                ),
              ),

              // Logo + RESIT RASMI
              Positioned(
                left: 614,
                top: 42,
                width: 120,
                height: 120,
                child: _Logo(bytes: logo, name: b.name, brand: brand),
              ),
              Positioned(
                left: 624,
                top: 173,
                width: 100,
                height: 18,
                child: Container(
                  color: brand,
                  alignment: Alignment.center,
                  child: const Text(
                    'RESIT RASMI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // Divider
              Positioned(
                left: 41,
                right: 41,
                top: 213,
                height: 1,
                child: const ColoredBox(color: Color(0xFF777777)),
              ),

              // Fields (left column)
              _label('Nama', 41, 258),
              _colon(108, 258),
              _box(data.customer, 128, 258, 301),
              _label('Tarikh', 41, 338),
              _colon(108, 338),
              _box(data.stayText, 128, 338, 301),
              _label('Jumlah', 41, 418),
              _colon(108, 418),
              _box(data.amountText, 128, 418, 301),

              // Fields (right column)
              _label('Pakej', 464, 258),
              _colon(568, 258),
              _box(data.package, 590, 258, 169),
              _label('Penginapan', 464, 338),
              _colon(568, 338),
              _box(data.duration, 590, 338, 169),
              _label('Bayaran', 464, 418),
              _colon(568, 418),
              _box(data.payment, 590, 418, 169),

              // Terms
              _terms(b, brand),

              // Signature
              if (sig != null)
                Positioned(
                  left: 572,
                  top: 490,
                  width: 187,
                  height: 100,
                  child: Image.memory(
                    sig,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Positioned(
                left: 572,
                top: 591,
                width: 187,
                child: Column(
                  children: [
                    const ColoredBox(
                      color: Colors.black,
                      child: SizedBox(height: 1, width: double.infinity),
                    ),
                    const SizedBox(height: 3),
                    const Text('Tandatangan/Cop',
                        style: TextStyle(fontSize: 14)),
                    const Text(
                      'Resit ini adalah cetakan komputer.',
                      style: TextStyle(
                          fontSize: 9.5, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),

              // Footer bar
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 31.5,
                child: Container(
                  color: brand,
                  alignment: Alignment.center,
                  child: Text(
                    [b.website, b.social]
                        .where((e) => e.isNotEmpty)
                        .join('        '),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- small builders -----------------------------------------------------
  static Widget _label(String t, double left, double top) => Positioned(
        left: left,
        top: top,
        height: 40,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(t,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      );

  static Widget _colon(double left, double top) => Positioned(
        left: left,
        top: top,
        height: 40,
        child: const Align(
          alignment: Alignment.centerLeft,
          child: Text(':',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      );

  static Widget _box(String v, double left, double top, double width) =>
      Positioned(
        left: left,
        top: top,
        width: width,
        height: 40,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _lineGrey, width: 1),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(v, style: const TextStyle(fontSize: 21)),
          ),
        ),
      );

  static Widget _terms(BusinessProfile b, Color brand) {
    final lines = b.terms
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    const base = TextStyle(fontSize: 13.5, height: 1.3, color: _ink);

    List<TextSpan> spans(String s) {
      final parts = s.split('**');
      return [
        for (int i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i],
            style: i.isOdd ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
      ];
    }

    return Positioned(
      left: 41,
      top: 476,
      width: 402,
      height: 180,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 402,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('${i + 1}.', style: base),
                      ),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: spans(lines[i])),
                          style: base,
                          textAlign: i == 0 ? TextAlign.left : TextAlign.justify,
                        ),
                      ),
                      if (i == 0 && b.noticeTitle.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          color: brand,
                          child: Text(
                            b.noticeTitle,
                            style: const TextStyle(
                              color: _noticeGold,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "......value......" style field used for No. and Tarikh.
class _Dotted extends StatelessWidget {
  final double width;
  final String value;
  const _Dotted({required this.width, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 30,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          ClipRect(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                '.' * 80,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(fontSize: 19)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uploaded logo, or a generated round badge when no logo is set.
class _Logo extends StatelessWidget {
  final Uint8List? bytes;
  final String name;
  final Color brand;
  const _Logo({required this.bytes, required this.name, required this.brand});

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return ClipOval(
        child: Image.memory(
          bytes!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: brand, width: 4),
      ),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: brand),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 80,
            child: Text(
              name.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                height: 1.15,
                fontFamilyFallback: ['Times New Roman', 'Georgia', 'serif'],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// BUSINESS PROFILES: list + editor
// ===========================================================================
class ProfilesPage extends StatelessWidget {
  const ProfilesPage({super.key});

  Future<void> _confirmDelete(BuildContext context, BusinessProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete business?'),
        content: Text('"${p.name}" will be removed from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.remove(p.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My businesses')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileEditorPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add business'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.profiles.isEmpty) {
            return const Center(child: Text('No businesses saved yet.'));
          }
          final selId = store.selected?.id;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: store.profiles.length,
            itemBuilder: (context, i) {
              final p = store.profiles[i];
              final isSel = p.id == selId;
              return Card(
                color: Colors.white,
                child: ListTile(
                  onTap: () async {
                    await store.select(p.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  leading: CircleAvatar(
                    backgroundColor: p.color,
                    child: Text(
                      p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(p.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${isSel ? 'In use  •  ' : ''}'
                    'Next no.: ${p.randomNumbering ? 'random' : '${p.prefix}${p.nextNumber}'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => ProfileEditorPage(profile: p)),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, p),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ProfileEditorPage extends StatefulWidget {
  final BusinessProfile? profile;
  const ProfileEditorPage({super.key, this.profile});

  @override
  State<ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<ProfileEditorPage> {
  static const _swatches = <int>[
    0xFF0B4FA8, 0xFF0E8F82, 0xFF2E7D32, 0xFF8E24AA,
    0xFFC62828, 0xFFEF6C00, 0xFF37474F, 0xFF6D4C41,
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _website;
  late final TextEditingController _social;
  late final TextEditingController _notice;
  late final TextEditingController _terms;
  late final TextEditingController _prefix;
  late final TextEditingController _next;
  late int _color;
  String? _logo;
  String? _signature;
  late bool _random;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p?.name ?? '');
    _address = TextEditingController(text: p?.address ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _website = TextEditingController(text: p?.website ?? '');
    _social = TextEditingController(text: p?.social ?? '');
    _notice = TextEditingController(text: p?.noticeTitle ?? 'PERHATIAN !');
    _terms = TextEditingController(text: p?.terms ?? '');
    _prefix = TextEditingController(text: p?.prefix ?? '');
    _next = TextEditingController(text: '${p?.nextNumber ?? 1}');
    _color = p?.brandColor ?? _swatches.first;
    _logo = p?.logoB64;
    _signature = p?.signatureB64;
    _random = p?.randomNumbering ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _name, _address, _phone, _website, _social,
      _notice, _terms, _prefix, _next,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _pickImage() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 700,
      maxHeight: 700,
    );
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    if (bytes.lengthInBytes > 1500 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Image is too large. Please use one under 1.5 MB.')));
      }
      return null;
    }
    return base64Encode(bytes);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final p = BusinessProfile(
      id: widget.profile?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      website: _website.text.trim(),
      social: _social.text.trim(),
      noticeTitle: _notice.text.trim(),
      terms: _terms.text.trim(),
      brandColor: _color,
      logoB64: _logo,
      signatureB64: _signature,
      randomNumbering: _random,
      prefix: _prefix.text.trim(),
      nextNumber: int.tryParse(_next.text.trim()) ?? 1,
    );
    await store.upsert(p);
    if (mounted) Navigator.pop(context);
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold, color: AppColors.deepTeal)),
      );

  Widget _imageRow({
    required String label,
    required String? b64,
    required VoidCallback onPick,
    required VoidCallback onRemove,
    required bool round,
  }) {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: round ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: round ? null : BorderRadius.circular(8),
            border: Border.all(color: Colors.black26),
          ),
          clipBehavior: Clip.antiAlias,
          child: b64 == null
              ? const Icon(Icons.image_outlined, color: Colors.black38)
              : Image.memory(base64Decode(b64), fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        TextButton(onPressed: onPick, child: Text(b64 == null ? 'Choose' : 'Change')),
        if (b64 != null)
          IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(Icons.close)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? 'Add business' : 'Edit business'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          children: [
            _section('Company details'),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Business name'),
              validator: _req,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              decoration:
                  const InputDecoration(labelText: 'Phone / WhatsApp'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _website,
              decoration: const InputDecoration(labelText: 'Website'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _social,
              decoration:
                  const InputDecoration(labelText: 'Social handle (footer)'),
            ),

            _section('Branding'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in _swatches)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c ? Colors.black : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: _color == c
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _imageRow(
              label: 'Logo (optional)',
              b64: _logo,
              round: true,
              onPick: () async {
                final v = await _pickImage();
                if (v != null) setState(() => _logo = v);
              },
              onRemove: () => setState(() => _logo = null),
            ),
            const SizedBox(height: 10),
            _imageRow(
              label: 'Signature / stamp (optional)',
              b64: _signature,
              round: false,
              onPick: () async {
                final v = await _pickImage();
                if (v != null) setState(() => _signature = v);
              },
              onRemove: () => setState(() => _signature = null),
            ),

            _section('Notice / terms'),
            TextFormField(
              controller: _notice,
              decoration: const InputDecoration(labelText: 'Notice badge text'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _terms,
              decoration: const InputDecoration(
                labelText: 'Terms (one point per line)',
                helperText: 'Wrap words in **double asterisks** to make them bold',
                alignLabelWithHint: true,
              ),
              maxLines: 8,
            ),

            _section('Receipt numbering'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    icon: Icon(Icons.format_list_numbered),
                    label: Text('Sequential')),
                ButtonSegment(
                    value: true,
                    icon: Icon(Icons.shuffle),
                    label: Text('Random')),
              ],
              selected: {_random},
              onSelectionChanged: (s) => setState(() => _random = s.first),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _prefix,
                    decoration:
                        const InputDecoration(labelText: 'Prefix (optional)'),
                  ),
                ),
                if (!_random) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _next,
                      decoration:
                          const InputDecoration(labelText: 'Next number'),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          int.tryParse((v ?? '').trim()) == null ? 'Invalid' : null,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save business'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }
}