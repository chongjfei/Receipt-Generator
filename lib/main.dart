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
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Currency shown on the receipt amount.
const String kCurrency = 'RM';

/// Global store for saved business profiles.
final AppStore store = AppStore();

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
    // The whole app takes the active business's color, so it is always
    // obvious which business a receipt is about to be issued for.
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: 'Receipt Generator',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(store.selected?.color ?? AppColors.teal),
        home: const HomePage(),
      ),
    );
  }
}

ThemeData buildTheme(Color primary) {
  final scheme = ColorScheme.fromSeed(seedColor: primary).copyWith(
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.gold,
    onPrimaryContainer: AppColors.text,
    secondary: primary,
    surface: AppColors.background,
    onSurface: AppColors.text,
    surfaceContainerLow: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: primary.withAlpha(45),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
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
        borderSide: BorderSide(color: primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
    ),
  );
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
  final String customerPhone;

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
    this.customerPhone = '',
  });

  String get issuedText => fmtDate(issuedAt);
  String get stayText => _sameDay(stayStart, stayEnd)
      ? fmtDate(stayStart)
      : '${fmtDate(stayStart)} - ${fmtDate(stayEnd)}';
  String get amountText => '$kCurrency ${amount.toStringAsFixed(2)}';
}

// ===========================================================================
// CUSTOMERS, PACKAGES, ORDERS + STORAGE (shared_preferences)
// ===========================================================================

/// A customer: contact details only. Bookings live in [Order].
class Customer {
  final String id;
  final String businessId;
  String name;
  String phone;
  String email;
  String note;

  Customer({
    required this.id,
    required this.businessId,
    required this.name,
    this.phone = '',
    this.email = '',
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'businessId': businessId,
        'name': name,
        'phone': phone,
        'email': email,
        'note': note,
      };

  // Older saved customers had extra fields (package, amount...). They are ignored.
  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        businessId: j['businessId'] as String,
        name: (j['name'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        note: (j['note'] ?? '') as String,
      );
}

/// A package a business sells (e.g. "6 Bilik 6 Bilik Air").
class StayPackage {
  final String id;
  final String businessId;
  String name;
  double price;

  StayPackage({
    required this.id,
    required this.businessId,
    required this.name,
    this.price = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'businessId': businessId,
        'name': name,
        'price': price,
      };

  factory StayPackage.fromJson(Map<String, dynamic> j) => StayPackage(
        id: j['id'] as String,
        businessId: j['businessId'] as String,
        name: (j['name'] ?? '') as String,
        price: ((j['price'] ?? 0) as num).toDouble(),
      );
}

/// One transaction. Everything needed to rebuild the receipt is stored here.
class Order {
  final String id;
  final String businessId;
  final String? customerId;
  final String customerName; // snapshot, so old receipts never change
  final String receiptNo;
  final DateTime issuedAt;
  final DateTime stayStart;
  final DateTime stayEnd;
  final String duration;
  final String package;
  final double amount;
  final String payment;

  const Order({
    required this.id,
    required this.businessId,
    required this.customerId,
    required this.customerName,
    required this.receiptNo,
    required this.issuedAt,
    required this.stayStart,
    required this.stayEnd,
    required this.duration,
    required this.package,
    required this.amount,
    required this.payment,
  });

  String get stayText => _sameDay(stayStart, stayEnd)
      ? fmtDate(stayStart)
      : '${fmtDate(stayStart)} - ${fmtDate(stayEnd)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'businessId': businessId,
        'customerId': customerId,
        'customerName': customerName,
        'receiptNo': receiptNo,
        'issuedAt': issuedAt.toIso8601String(),
        'stayStart': stayStart.toIso8601String(),
        'stayEnd': stayEnd.toIso8601String(),
        'duration': duration,
        'package': package,
        'amount': amount,
        'payment': payment,
      };

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id'] as String,
        businessId: j['businessId'] as String,
        customerId: j['customerId'] as String?,
        customerName: (j['customerName'] ?? '') as String,
        receiptNo: (j['receiptNo'] ?? '') as String,
        issuedAt: DateTime.parse(j['issuedAt'] as String),
        stayStart: DateTime.parse(j['stayStart'] as String),
        stayEnd: DateTime.parse(j['stayEnd'] as String),
        duration: (j['duration'] ?? '') as String,
        package: (j['package'] ?? '') as String,
        amount: ((j['amount'] ?? 0) as num).toDouble(),
        payment: (j['payment'] ?? '') as String,
      );
}

class AppStore extends ChangeNotifier {
  List<BusinessProfile> profiles = [];
  List<Customer> customers = [];
  List<StayPackage> packages = [];
  List<Order> orders = [];
  String? selectedId;
  SharedPreferences? _prefs;

  BusinessProfile? get selected {
    for (final p in profiles) {
      if (p.id == selectedId) return p;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  // --- queries ------------------------------------------------------------
  List<Customer> customersFor(String businessId) {
    final list = customers.where((c) => c.businessId == businessId).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<StayPackage> packagesFor(String businessId) {
    final list = packages.where((p) => p.businessId == businessId).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Newest first.
  List<Order> ordersFor(String businessId) {
    final list = orders.where((o) => o.businessId == businessId).toList();
    list.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return list;
  }

  /// Newest first.
  List<Order> ordersForCustomer(String customerId) {
    final list = orders.where((o) => o.customerId == customerId).toList();
    list.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return list;
  }

  /// Rebuilds the receipt for a saved order (null if its business was deleted).
  ReceiptData? receiptFor(Order o) {
    final b = profiles.where((p) => p.id == o.businessId).firstOrNull;
    if (b == null) return null;
    final c = customers.where((c) => c.id == o.customerId).firstOrNull;
    return ReceiptData(
      business: b,
      receiptNo: o.receiptNo,
      issuedAt: o.issuedAt,
      customer: o.customerName,
      stayStart: o.stayStart,
      stayEnd: o.stayEnd,
      duration: o.duration,
      package: o.package,
      amount: o.amount,
      payment: o.payment,
      customerPhone: c?.phone ?? '',
    );
  }

  // --- load / save --------------------------------------------------------
  List<T> _decode<T>(String key, T Function(Map<String, dynamic>) from) {
    final raw = _prefs!.getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => from(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final firstLaunch = _prefs!.getString('profiles') == null;
    profiles = firstLaunch
        ? [BusinessProfile.sample()]
        : _decode('profiles', BusinessProfile.fromJson);
    customers = _decode('customers', Customer.fromJson);
    packages = _decode('packages', StayPackage.fromJson);
    orders = _decode('orders', Order.fromJson);
    selectedId = _prefs!.getString('selectedId');
    if (firstLaunch) await save();
  }

  Future<void> save() async {
    await _prefs?.setString(
        'profiles', jsonEncode(profiles.map((e) => e.toJson()).toList()));
    await _prefs?.setString(
        'customers', jsonEncode(customers.map((e) => e.toJson()).toList()));
    await _prefs?.setString(
        'packages', jsonEncode(packages.map((e) => e.toJson()).toList()));
    await _prefs?.setString(
        'orders', jsonEncode(orders.map((e) => e.toJson()).toList()));
    if (selectedId != null) {
      await _prefs?.setString('selectedId', selectedId!);
    }
    notifyListeners();
  }

  // --- businesses ---------------------------------------------------------
  Future<void> upsert(BusinessProfile p) async {
    final i = profiles.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      profiles[i] = p;
    } else {
      profiles.add(p);
      selectedId = p.id; // newly added business becomes the active one
    }
    await save();
  }

  Future<void> remove(String id) async {
    profiles.removeWhere((p) => p.id == id);
    customers.removeWhere((c) => c.businessId == id);
    packages.removeWhere((p) => p.businessId == id);
    orders.removeWhere((o) => o.businessId == id);
    if (selectedId == id) {
      selectedId = profiles.isEmpty ? null : profiles.first.id;
    }
    await save();
  }

  Future<void> select(String id) async {
    selectedId = id;
    await save();
  }

  // --- customers ----------------------------------------------------------
  Future<void> upsertCustomer(Customer c) async {
    final i = customers.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      customers[i] = c;
    } else {
      customers.add(c);
    }
    await save();
  }

  /// Orders stay in the history (they keep the customer's name).
  Future<void> removeCustomer(String id) async {
    customers.removeWhere((c) => c.id == id);
    await save();
  }

  // --- packages -----------------------------------------------------------
  Future<void> upsertPackage(StayPackage p) async {
    final i = packages.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      packages[i] = p;
    } else {
      packages.add(p);
    }
    await save();
  }

  /// Orders stay in the history (they keep the package name).
  Future<void> removePackage(String id) async {
    packages.removeWhere((p) => p.id == id);
    await save();
  }

  // --- orders -------------------------------------------------------------
  Future<void> addOrder(Order o) async {
    orders.add(o);
    await save();
  }

  Future<void> removeOrder(String id) async {
    orders.removeWhere((o) => o.id == id);
    await save();
  }

  // --- receipt numbers ----------------------------------------------------
  /// Issues the next receipt number (sequential increments the saved counter).
  Future<String> issueReceiptNo(BusinessProfile p) async {
    if (p.randomNumbering) {
      return '${p.prefix}${100000 + Random().nextInt(900000)}';
    }
    final no = '${p.prefix}${p.nextNumber}';
    p.nextNumber += 1;
    await save();
    return no;
  }
}

// ===========================================================================
// HOME (tabs) + SHARED WIDGETS
// ===========================================================================
const kPaymentOptions = ['Deposit', 'Bayaran Penuh', 'Baki'];
const _addBusinessValue = '__add_business__';

/// Country code added to local numbers that start with 0 (60 = Malaysia).
const String kDefaultCountryCode = '60';

String moneyText(double v) => '$kCurrency ${v.toStringAsFixed(2)}';

/// Days + nights label, e.g. 21 -> 22 Nov = "2H1M" (2 hari 1 malam).
String durationLabel(DateTimeRange r) {
  final nights = r.end.difference(r.start).inDays;
  return '${nights + 1}H${nights}M';
}

/// "010-325 7723" -> "60103257723" (digits only, with country code).
String? whatsappNumber(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  if (d.isEmpty) return null;
  final hasPlus = d.startsWith('+');
  d = d.replaceAll('+', '');
  if (d.startsWith('00')) {
    d = d.substring(2);
  } else if (!hasPlus && d.startsWith('0')) {
    d = kDefaultCountryCode + d.substring(1);
  }
  return d.length < 8 ? null : d;
}

/// Opens a WhatsApp chat with [phone] (optionally with a pre-typed message).
Future<void> openWhatsApp(BuildContext context, String phone,
    {String? message}) async {
  final n = whatsappNumber(phone);
  void toast(String m) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  if (n == null) {
    toast('This customer has no valid phone number.');
    return;
  }
  try {
    final uri = Uri.https(
        'wa.me', '/$n', message == null ? null : {'text': message});
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) toast('Could not open WhatsApp.');
  } catch (_) {
    toast('Could not open WhatsApp.');
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.selected;
        return Scaffold(
          appBar: AppBar(
            title: Text(_tab == 0 ? 'Orders' : 'Customers'),
            actions: [
              if (p != null)
                IconButton(
                  tooltip: 'Packages',
                  icon: const Icon(Icons.inventory_2_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => PackagesPage(business: p)),
                  ),
                ),
              IconButton(
                tooltip: 'Manage businesses',
                icon: const Icon(Icons.storefront),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfilesPage()),
                ),
              ),
            ],
          ),
          body: p == null
              ? const _EmptyBusiness()
              : IndexedStack(
                  index: _tab,
                  children: [
                    OrdersTab(business: p),
                    CustomersTab(business: p),
                  ],
                ),
          bottomNavigationBar: p == null
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long),
                      label: 'Orders',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: 'Customers',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _EmptyBusiness extends StatelessWidget {
  const _EmptyBusiness();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront,
                size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            const Text('Add your business details first.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileEditorPage()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add business'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Business switcher. Shown in the business's own color on every tab so it
/// is always clear which business you are working in.
class BusinessSelector extends StatelessWidget {
  final BusinessProfile current;
  const BusinessSelector({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(
        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: current.color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ISSUING AS',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 10, letterSpacing: 1),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    value: current.id,
                    iconEnabledColor: Colors.white,
                    items: [
                      for (final b in store.profiles)
                        DropdownMenuItem(
                          value: b.id,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                    color: b.color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(b.name,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                      DropdownMenuItem(
                        value: _addBusinessValue,
                        child: Row(
                          children: [
                            Icon(Icons.add_circle_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Add new business',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // What the closed dropdown shows (white on the color bar)
                    selectedItemBuilder: (_) => [
                      for (final b in store.profiles)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(b.name,
                              overflow: TextOverflow.ellipsis, style: white),
                        ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Add new business', style: white),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      if (v == _addBusinessValue) {
                        // The new business is selected automatically on save.
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ProfileEditorPage()),
                        );
                      } else if (v != current.id) {
                        store.select(v);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Static version of the banner (no dropdown) for sheets and sub-pages.
class IssuingBanner extends StatelessWidget {
  final BusinessProfile business;
  const IssuingBanner({super.key, required this.business});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: business.color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ISSUING AS',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 10, letterSpacing: 1),
                ),
                Text(
                  business.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentChips extends StatelessWidget {
  final TextEditingController controller;
  const PaymentChips(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final o in kPaymentOptions)
          ActionChip(label: Text(o), onPressed: () => controller.text = o),
      ],
    );
  }
}

// ===========================================================================
// PAGE 2: RECEIPT + EXPORT
// ===========================================================================
String _two(int n) => n.toString().padLeft(2, '0');

/// 2026-11-12
String isoDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// File name without extension: customer name + issue date,
/// e.g. "SANIZAH_BT_SANIP_2026-11-12".
String receiptFileBase(ReceiptData d) {
  final name = d.customer
      .trim()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return '${name.isEmpty ? 'receipt' : name}_${isoDate(d.issuedAt)}';
}

class ReceiptPage extends StatefulWidget {
  final ReceiptData data;
  const ReceiptPage({super.key, required this.data});

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  final GlobalKey _boundaryKey = GlobalKey();

  String get _base => receiptFileBase(widget.data);

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

  Future<void> _exportPdf() async {
    try {
      await Printing.sharePdf(bytes: await _buildPdf(), filename: '$_base.pdf');
    } catch (e) {
      _toast('Export failed: $e');
    }
  }

  Future<void> _exportImage() async {
    try {
      final png = await _capturePng();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(png, mimeType: 'image/png')],
          fileNameOverrides: ['$_base.png'],
          title: _base,
        ),
      );
    } catch (e) {
      _toast('Export failed: $e');
    }
  }

  Future<void> _preview() async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) => _buildPdf(),
        name: '$_base.pdf',
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
    final d = widget.data;
    return Scaffold(
      appBar: AppBar(title: Text('Receipt ${d.receiptNo}')),
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
                      child: ReceiptSheet(data: d),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'File name: $_base',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Export PDF'),
                    ),
                    FilledButton.icon(
                      onPressed: _exportImage,
                      icon: const Icon(Icons.image),
                      label: const Text('Export Image'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _preview,
                      icon: const Icon(Icons.print),
                      label: const Text('Print / Preview'),
                    ),
                    if (d.customerPhone.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => openWhatsApp(
                          context,
                          d.customerPhone,
                          message: 'Salam ${d.customer}, terima kasih. '
                              'Berikut resit anda (No. ${d.receiptNo}) '
                              'daripada ${d.business.name}.',
                        ),
                        icon: const Icon(Icons.chat),
                        label: const Text('WhatsApp customer'),
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
// TAB 1: ORDERS / TRANSACTION HISTORY
// ===========================================================================
const _addNew = '__add_new__';

/// Opens the "new order" sheet, then shows the generated receipt.
Future<void> startNewOrder(BuildContext context, BusinessProfile b,
    {String? customerId}) async {
  final data = await showModalBottomSheet<ReceiptData>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    builder: (_) => NewOrderSheet(business: b, initialCustomerId: customerId),
  );
  if (data == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ReceiptPage(data: data)),
  );
}

class OrdersTab extends StatefulWidget {
  final BusinessProfile business;
  const OrdersTab({super.key, required this.business});

  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = store.ordersFor(widget.business.id);
    final q = _q.toLowerCase();
    final list = q.isEmpty
        ? all
        : all
            .where((o) =>
                o.customerName.toLowerCase().contains(q) ||
                o.receiptNo.toLowerCase().contains(q) ||
                o.package.toLowerCase().contains(q))
            .toList();
    final total = list.fold<double>(0, (s, o) => s + o.amount);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => startNewOrder(context, widget.business),
        icon: const Icon(Icons.add),
        label: const Text('New order'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          BusinessSelector(current: widget.business),
          const SizedBox(height: 12),
          if (all.isNotEmpty) ...[
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, receipt no. or package',
              ),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${list.length} order${list.length == 1 ? '' : 's'}'
                '  •  ${moneyText(total)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  const Text(
                    'No orders yet.\nTap "New order" to create the first receipt.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No order matches your search.')),
            )
          else
            for (final o in list) OrderCard(order: o),
        ],
      ),
    );
  }
}

class OrderCard extends StatelessWidget {
  final Order order;
  final bool showCustomer;
  const OrderCard({super.key, required this.order, this.showCustomer = true});

  void _open(BuildContext context) {
    final d = store.receiptFor(order);
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The business for this order no longer exists.')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiptPage(data: d)),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete order?'),
        content: Text(
            'Receipt #${order.receiptNo} for ${order.customerName} will be '
            'removed from the history.'),
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
    if (ok == true) await store.removeOrder(order.id);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final phone = store.customers
            .where((c) => c.id == order.customerId)
            .firstOrNull
            ?.phone ??
        '';
    final what = [order.package, order.duration]
        .where((e) => e.isNotEmpty)
        .join('  •  ');

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#${order.receiptNo}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: primary)),
                        const SizedBox(width: 8),
                        Text(fmtDate(order.issuedAt),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (showCustomer)
                      Text(order.customerName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    if (what.isNotEmpty) Text(what),
                    Text(order.stayText,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withAlpha(150),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(order.payment,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 10, top: 2),
                    child: Text(moneyText(order.amount),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'view') _open(context);
                      if (v == 'wa') {
                        openWhatsApp(context, phone,
                            message: 'Salam ${order.customerName}, '
                                'berkenaan resit No. ${order.receiptNo}.');
                      }
                      if (v == 'delete') _delete(context);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'view', child: Text('View receipt')),
                      if (phone.isNotEmpty)
                        const PopupMenuItem(
                            value: 'wa', child: Text('WhatsApp customer')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New order sheet: pick customer + package (or add new), confirm, generate.
// ---------------------------------------------------------------------------
class NewOrderSheet extends StatefulWidget {
  final BusinessProfile business;
  final String? initialCustomerId;
  const NewOrderSheet(
      {super.key, required this.business, this.initialCustomerId});

  @override
  State<NewOrderSheet> createState() => _NewOrderSheetState();
}

class _NewOrderSheetState extends State<NewOrderSheet> {
  final _key = GlobalKey<FormState>();
  final _duration = TextEditingController();
  final _amount = TextEditingController();
  final _payment = TextEditingController(text: 'Deposit');

  String? _customerId;
  String? _packageId;
  late DateTimeRange _stay;
  int _nonce = 0; // forces the dropdowns to rebuild after "add new"

  @override
  void initState() {
    super.initState();
    final today = _today();
    _stay = DateTimeRange(start: today, end: today.add(const Duration(days: 1)));
    _duration.text = durationLabel(_stay);
    if (widget.initialCustomerId != null) {
      _customerId = widget.initialCustomerId;
      _prefillFrom(_customerId!);
    }
  }

  @override
  void dispose() {
    _duration.dispose();
    _amount.dispose();
    _payment.dispose();
    super.dispose();
  }

  DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Recurring customer: start from their last order with this business.
  void _prefillFrom(String customerId) {
    final last = store
        .ordersForCustomer(customerId)
        .where((o) => o.businessId == widget.business.id)
        .firstOrNull;
    if (last == null) return;
    final nights = last.stayEnd.difference(last.stayStart).inDays;
    final today = _today();
    _stay = DateTimeRange(
        start: today, end: today.add(Duration(days: nights < 0 ? 0 : nights)));
    _duration.text = durationLabel(_stay);
    _amount.text = last.amount.toStringAsFixed(2);
    _payment.text = last.payment;
    _packageId = store
        .packagesFor(widget.business.id)
        .where((p) => p.name == last.package)
        .firstOrNull
        ?.id;
  }

  void _applyPackage(StayPackage p) {
    _packageId = p.id;
    if (p.price > 0) _amount.text = p.price.toStringAsFixed(2);
  }

  Future<void> _onCustomer(String? v) async {
    if (v == null) return;
    if (v == _addNew) {
      final c = await showCustomerQuickAdd(context, widget.business);
      if (!mounted) return;
      setState(() {
        _nonce++;
        if (c != null) _customerId = c.id;
      });
      return;
    }
    setState(() {
      _nonce++;
      _customerId = v;
      _prefillFrom(v);
    });
  }

  Future<void> _onPackage(String? v) async {
    if (v == null) return;
    if (v == _addNew) {
      final p = await showPackageDialog(context, widget.business);
      if (!mounted) return;
      setState(() {
        _nonce++;
        if (p != null) _applyPackage(p);
      });
      return;
    }
    final p = store.packages.firstWhere((e) => e.id == v);
    setState(() {
      _nonce++;
      _applyPackage(p);
    });
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
        _duration.text = durationLabel(r);
      });
    }
  }

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    final b = widget.business;
    final cust = store.customers.firstWhere((c) => c.id == _customerId);
    final pkg = store.packages.firstWhere((p) => p.id == _packageId);

    final no = await store.issueReceiptNo(b); // auto receipt number
    final now = DateTime.now(); // auto date
    final order = Order(
      id: now.microsecondsSinceEpoch.toString(),
      businessId: b.id,
      customerId: cust.id,
      customerName: cust.name,
      receiptNo: no,
      issuedAt: now,
      stayStart: _stay.start,
      stayEnd: _stay.end,
      duration: _duration.text.trim(),
      package: pkg.name,
      amount: double.parse(_amount.text.trim()),
      payment: _payment.text.trim(),
    );
    await store.addOrder(order);
    if (!mounted) return;
    Navigator.pop(
      context,
      ReceiptData(
        business: b,
        receiptNo: no,
        issuedAt: now,
        customer: cust.name,
        stayStart: order.stayStart,
        stayEnd: order.stayEnd,
        duration: order.duration,
        package: order.package,
        amount: order.amount,
        payment: order.payment,
        customerPhone: cust.phone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.business;
    final primary = Theme.of(context).colorScheme.primary;
    final customers = store.customersFor(b.id);
    final packages = store.packagesFor(b.id);
    final nextNo = b.randomNumbering ? 'random' : '${b.prefix}${b.nextNumber}';

    Widget addItem(IconData icon, String label) => Row(
          children: [
            Icon(icon, size: 18, color: primary),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
          ],
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IssuingBanner(business: b),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _AutoChip('Receipt no.', nextNo)),
                  const SizedBox(width: 10),
                  Expanded(child: _AutoChip('Date', fmtDate(DateTime.now()))),
                ],
              ),
              const SizedBox(height: 14),

              // Customer
              DropdownButtonFormField<String>(
                key: ValueKey('cust-$_customerId-$_nonce'),
                initialValue: _customerId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Customer (Nama)'),
                items: [
                  for (final c in customers)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
                  DropdownMenuItem(
                    value: _addNew,
                    child: addItem(Icons.person_add_alt_1, 'Add new customer'),
                  ),
                ],
                validator: (v) => v == null ? 'Select a customer' : null,
                onChanged: _onCustomer,
              ),
              const SizedBox(height: 10),

              // Package
              DropdownButtonFormField<String>(
                key: ValueKey('pkg-$_packageId-$_nonce'),
                initialValue: _packageId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Package (Pakej)'),
                items: [
                  for (final p in packages)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        p.price > 0 ? '${p.name}  •  ${moneyText(p.price)}' : p.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  DropdownMenuItem(
                    value: _addNew,
                    child: addItem(Icons.add_circle_outline, 'Add new package'),
                  ),
                ],
                validator: (v) => v == null ? 'Select a package' : null,
                onChanged: _onPackage,
              ),
              const SizedBox(height: 10),

              // Dates
              InkWell(
                onTap: _pickStay,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Stay dates (Tarikh)',
                    suffixIcon: Icon(Icons.date_range, size: 20),
                  ),
                  child: Text(_sameDay(_stay.start, _stay.end)
                      ? fmtDate(_stay.start)
                      : '${fmtDate(_stay.start)} - ${fmtDate(_stay.end)}'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _duration,
                      decoration: const InputDecoration(
                        labelText: 'Stay (Penginapan)',
                        helperText: 'Auto from dates',
                      ),
                      validator: _req,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _amount,
                      decoration: const InputDecoration(
                        labelText: 'Amount (Jumlah)',
                        prefixText: '$kCurrency ',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: _amountValidator,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _payment,
                decoration:
                    const InputDecoration(labelText: 'Payment (Bayaran)'),
                validator: _req,
              ),
              const SizedBox(height: 6),
              PaymentChips(_payment),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.receipt_long),
                label: Text('Generate receipt for ${b.name}',
                    overflow: TextOverflow.ellipsis),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoChip extends StatelessWidget {
  final String label;
  final String value;
  const _AutoChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
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
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick "add new customer" dialog (name + phone) used by the order sheet.
// ---------------------------------------------------------------------------
Future<Customer?> showCustomerQuickAdd(
    BuildContext context, BusinessProfile b) {
  return showDialog<Customer>(
    context: context,
    builder: (_) => _QuickCustomerDialog(business: b),
  );
}

class _QuickCustomerDialog extends StatefulWidget {
  final BusinessProfile business;
  const _QuickCustomerDialog({required this.business});

  @override
  State<_QuickCustomerDialog> createState() => _QuickCustomerDialogState();
}

class _QuickCustomerDialogState extends State<_QuickCustomerDialog> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final c = Customer(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      businessId: widget.business.id,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
    );
    await store.upsertCustomer(c);
    if (mounted) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New customer'),
      content: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: _req,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Add')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Packages: add / edit dialog + management page
// ---------------------------------------------------------------------------
Future<StayPackage?> showPackageDialog(BuildContext context, BusinessProfile b,
    {StayPackage? existing}) {
  return showDialog<StayPackage>(
    context: context,
    builder: (_) => _PackageDialog(business: b, existing: existing),
  );
}

class _PackageDialog extends StatefulWidget {
  final BusinessProfile business;
  final StayPackage? existing;
  const _PackageDialog({required this.business, this.existing});

  @override
  State<_PackageDialog> createState() => _PackageDialogState();
}

class _PackageDialogState extends State<_PackageDialog> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _price = TextEditingController(
        text: (e == null || e.price == 0) ? '' : e.price.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final p = widget.existing ??
        StayPackage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          businessId: widget.business.id,
          name: '',
        );
    p.name = _name.text.trim();
    p.price = double.tryParse(_price.text.trim()) ?? 0;
    await store.upsertPackage(p);
    if (mounted) Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New package' : 'Edit package'),
      content: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Package name'),
              validator: _req,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Default price (optional)',
                prefixText: '$kCurrency ',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? null : _amountValidator(v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class PackagesPage extends StatelessWidget {
  final BusinessProfile business;
  const PackagesPage({super.key, required this.business});

  Future<void> _confirmDelete(BuildContext context, StayPackage p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete package?'),
        content: Text(
            '"${p.name}" will be removed. Past orders keep their package name.'),
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
    if (ok == true) await store.removePackage(p.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Packages')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showPackageDialog(context, business),
        icon: const Icon(Icons.add),
        label: const Text('Add package'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final list = store.packagesFor(business.id);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              IssuingBanner(business: business),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No packages yet for this business.\n'
                    'Add one here, or from the "Package" dropdown when '
                    'creating an order.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final p in list)
                  Card(
                    color: Colors.white,
                    child: ListTile(
                      title: Text(p.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle:
                          Text(p.price > 0 ? moneyText(p.price) : 'No default price'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => showPackageDialog(
                                context, business,
                                existing: p),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(context, p),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

// ===========================================================================
// TAB 2: CUSTOMERS (contact details only)
// ===========================================================================
class CustomersTab extends StatefulWidget {
  final BusinessProfile business;
  const CustomersTab({super.key, required this.business});

  @override
  State<CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<CustomersTab> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openEditor([Customer? c]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CustomerEditorPage(business: widget.business, customer: c),
      ),
    );
  }

  Future<void> _confirmDelete(Customer c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete customer?'),
        content: Text(
            '"${c.name}" will be removed. Their past orders stay in the history.'),
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
    if (ok == true) await store.removeCustomer(c.id);
  }

  @override
  Widget build(BuildContext context) {
    final all = store.customersFor(widget.business.id);
    final q = _q.toLowerCase();
    final list = q.isEmpty
        ? all
        : all
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.phone.contains(q) ||
                c.email.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add customer'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          BusinessSelector(current: widget.business),
          const SizedBox(height: 12),
          if (all.isNotEmpty) ...[
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, phone or email',
              ),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
            const SizedBox(height: 10),
          ],
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              child: Column(
                children: [
                  Icon(Icons.people_outline,
                      size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  const Text(
                    'No customers yet for this business.\n'
                    'Tap "Add customer", or add one while creating an order.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No customer matches your search.')),
            )
          else
            for (final c in list) _card(c),
        ],
      ),
    );
  }

  Widget _card(Customer c) {
    final orders = store.ordersForCustomer(c.id);
    final spent = orders.fold<double>(0, (s, o) => s + o.amount);
    final stats = orders.isEmpty
        ? 'No orders yet'
        : '${orders.length} order${orders.length == 1 ? '' : 's'}'
            '  •  ${moneyText(spent)}'
            '  •  last ${fmtDate(orders.first.issuedAt)}';

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                CustomerDetailPage(business: widget.business, customerId: c.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: widget.business.color,
                child: Text(
                  c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    if (c.phone.isNotEmpty) Text(c.phone),
                    if (c.email.isNotEmpty)
                      Text(c.email, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(stats,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              if (c.phone.isNotEmpty)
                IconButton(
                  tooltip: 'WhatsApp',
                  icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                  onPressed: () => openWhatsApp(context, c.phone),
                ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') _openEditor(c);
                  if (v == 'delete') _confirmDelete(c);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A customer's details and all of their orders.
class CustomerDetailPage extends StatelessWidget {
  final BusinessProfile business;
  final String customerId;
  const CustomerDetailPage(
      {super.key, required this.business, required this.customerId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = store.customers.where((e) => e.id == customerId).firstOrNull;
        if (c == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Customer')),
            body: const Center(child: Text('This customer was deleted.')),
          );
        }
        final orders = store.ordersForCustomer(c.id);
        final spent = orders.fold<double>(0, (s, o) => s + o.amount);

        return Scaffold(
          appBar: AppBar(
            title: Text(c.name),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        CustomerEditorPage(business: business, customer: c),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => startNewOrder(context, business, customerId: c.id),
            icon: const Icon(Icons.add),
            label: const Text('New order'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              IssuingBanner(business: business),
              const SizedBox(height: 12),
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  c.phone.isEmpty ? 'No phone number' : c.phone)),
                          if (c.phone.isNotEmpty)
                            FilledButton.icon(
                              onPressed: () => openWhatsApp(context, c.phone),
                              icon: const Icon(Icons.chat, size: 18),
                              label: const Text('WhatsApp'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF25D366)),
                            ),
                        ],
                      ),
                      if (c.email.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.email_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(c.email)),
                          ],
                        ),
                      ],
                      if (c.note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(c.note,
                            style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.black54)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Orders  •  ${orders.length}  •  ${moneyText(spent)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No orders yet for this customer.')),
                )
              else
                for (final o in orders) OrderCard(order: o, showCustomer: false),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit a customer (contact details only)
// ---------------------------------------------------------------------------
class CustomerEditorPage extends StatefulWidget {
  final BusinessProfile business;
  final Customer? customer;
  const CustomerEditorPage({super.key, required this.business, this.customer});

  @override
  State<CustomerEditorPage> createState() => _CustomerEditorPageState();
}

class _CustomerEditorPageState extends State<CustomerEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _name = TextEditingController(text: c?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _note = TextEditingController(text: c?.note ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final c = widget.customer ??
        Customer(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          businessId: widget.business.id,
          name: '',
        );
    c.name = _name.text.trim();
    c.phone = _phone.text.trim();
    c.email = _email.text.trim();
    c.note = _note.text.trim();
    await store.upsertCustomer(c);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer == null ? 'Add customer' : 'Edit customer'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            IssuingBanner(business: widget.business),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (Nama)'),
              textCapitalization: TextCapitalization.characters,
              validator: _req,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(
                labelText: 'Phone / WhatsApp',
                helperText: 'e.g. 012-345 6789 (a leading 0 becomes +60)',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email (optional)'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                final t = (v ?? '').trim();
                return (t.isNotEmpty && !t.contains('@'))
                    ? 'Enter a valid email'
                    : null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save customer'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
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
        content: Text(
            '"${p.name}" and all of its customers, packages and orders will be removed from this device.'),
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
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary)),
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