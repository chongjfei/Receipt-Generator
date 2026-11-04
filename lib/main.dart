import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() => runApp(const ReceiptApp());

/// Change this to switch currency everywhere (UI + PDF).
const String kCurrency = 'RM';

String money(double v) => '$kCurrency ${v.toStringAsFixed(2)}';

/// Brand palette
class AppColors {
  static const teal = Color(0xFF0E8F82);
  static const deepTeal = Color(0xFF08786D);
  static const gold = Color(0xFFF8E692);
  static const background = Color(0xFFF5FAF9);
  static const text = Color(0xFF183C38);
}

// ===========================================================================
// APP + THEME
// ===========================================================================
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
// MODEL (UI and PDF both read from this, so template changes stay in the UI)
// ===========================================================================
class ReceiptItem {
  final String name;
  final int qty;
  final double price;
  const ReceiptItem({
    required this.name,
    required this.qty,
    required this.price,
  });

  double get total => qty * price;
}

class ReceiptData {
  final String businessName;
  final String address;
  final String phone;
  final String receiptNo;
  final DateTime date;
  final String customerName;
  final String paymentMethod;
  final List<ReceiptItem> items;
  final double taxPercent;
  final double discount;
  final String notes;

  const ReceiptData({
    required this.businessName,
    required this.address,
    required this.phone,
    required this.receiptNo,
    required this.date,
    required this.customerName,
    required this.paymentMethod,
    required this.items,
    required this.taxPercent,
    required this.discount,
    required this.notes,
  });

  double get subtotal => items.fold(0.0, (s, i) => s + i.total);
  double get appliedDiscount => discount > subtotal ? subtotal : discount;
  double get tax => (subtotal - appliedDiscount) * taxPercent / 100;
  double get total => subtotal - appliedDiscount + tax;

  String get formattedDate => DateFormat('dd MMM yyyy, hh:mm a').format(date);
}

// ===========================================================================
// PAGE 1: FORM
// ===========================================================================
class _ItemFields {
  final name = TextEditingController();
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();

  void dispose() {
    name.dispose();
    qty.dispose();
    price.dispose();
  }
}

String? _req(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Required' : null;

String? _posInt(String? v) {
  final n = int.tryParse((v ?? '').trim());
  return (n == null || n <= 0) ? 'Invalid' : null;
}

String? _num(String? v) {
  final n = double.tryParse((v ?? '').trim());
  return (n == null || n < 0) ? 'Invalid' : null;
}

String? _optNum(String? v) =>
    (v == null || v.trim().isEmpty) ? null : _num(v);

class ReceiptFormPage extends StatefulWidget {
  const ReceiptFormPage({super.key});

  @override
  State<ReceiptFormPage> createState() => _ReceiptFormPageState();
}

class _ReceiptFormPageState extends State<ReceiptFormPage> {
  static const _methods = ['Cash', 'Card', 'E-wallet', 'Bank transfer'];

  final _formKey = GlobalKey<FormState>();
  final _business = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _receiptNo = TextEditingController(
    text: 'RCP-${DateFormat('yyyyMMdd').format(DateTime.now())}-001',
  );
  final _customer = TextEditingController();
  final _tax = TextEditingController(text: '0');
  final _discount = TextEditingController(text: '0');
  final _notes = TextEditingController();

  final List<_ItemFields> _items = [_ItemFields()];
  DateTime _date = DateTime.now();
  String _payment = _methods.first;

  @override
  void dispose() {
    for (final c in [
      _business,
      _address,
      _phone,
      _receiptNo,
      _customer,
      _tax,
      _discount,
      _notes,
    ]) {
      c.dispose();
    }
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day,
            _date.hour, _date.minute);
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final data = ReceiptData(
      businessName: _business.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      receiptNo: _receiptNo.text.trim(),
      date: _date,
      customerName: _customer.text.trim(),
      paymentMethod: _payment,
      items: _items
          .map((f) => ReceiptItem(
                name: f.name.text.trim(),
                qty: int.parse(f.qty.text.trim()),
                price: double.parse(f.price.text.trim()),
              ))
          .toList(),
      taxPercent: double.tryParse(_tax.text.trim()) ?? 0,
      discount: double.tryParse(_discount.text.trim()) ?? 0,
      notes: _notes.text.trim(),
    );

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiptPage(data: data)),
    );
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
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Generator')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            _section('Business details'),
            TextFormField(
              controller: _business,
              decoration: const InputDecoration(labelText: 'Business name'),
              validator: _req,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),

            _section('Receipt details'),
            TextFormField(
              controller: _receiptNo,
              decoration: const InputDecoration(labelText: 'Receipt no.'),
              validator: _req,
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(DateFormat('dd MMM yyyy').format(_date)),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _customer,
              decoration:
                  const InputDecoration(labelText: 'Customer name (optional)'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _payment,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: _methods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _payment = v ?? _payment),
            ),

            _section('Items'),
            for (int i = 0; i < _items.length; i++) _itemRow(i),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _items.add(_ItemFields())),
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
            ),

            _section('Totals'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _tax,
                    decoration: const InputDecoration(labelText: 'Tax (%)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: _optNum,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _discount,
                    decoration: InputDecoration(
                        labelText: 'Discount ($kCurrency)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: _optNum,
                  ),
                ),
              ],
            ),

            _section('Notes'),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),

            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Generate receipt'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(int i) {
    final f = _items[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: TextFormField(
              controller: f.name,
              decoration: InputDecoration(labelText: 'Item ${i + 1}'),
              validator: _req,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: f.qty,
              decoration: const InputDecoration(labelText: 'Qty'),
              keyboardType: TextInputType.number,
              validator: _posInt,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: f.price,
              decoration: const InputDecoration(labelText: 'Price'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _num,
            ),
          ),
          IconButton(
            tooltip: 'Remove item',
            icon: const Icon(Icons.delete_outline),
            onPressed: _items.length <= 1
                ? null
                : () => setState(() => _items.removeAt(i).dispose()),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// PAGE 2: RECEIPT UI + EXPORT
// ===========================================================================
class ReceiptPage extends StatelessWidget {
  final ReceiptData data;
  const ReceiptPage({super.key, required this.data});

  String get _fileName {
    final safe = data.receiptNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'receipt_$safe.pdf';
  }

  Future<void> _export(BuildContext context) async {
    try {
      final bytes = await buildReceiptPdf(data);
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _preview(BuildContext context) async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) => buildReceiptPdf(data),
        name: _fileName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Print failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                _ReceiptPaper(data: data),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _export(context),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Export PDF'),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _preview(context),
                    icon: const Icon(Icons.print),
                    label: const Text('Print / Preview'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit details'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The on-screen receipt. Restyle this widget to match a template later.
class _ReceiptPaper extends StatelessWidget {
  final ReceiptData data;
  const _ReceiptPaper({required this.data});

  Widget _line(String l, String r, {bool bold = false, double size = 14}) {
    final style = TextStyle(
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l, style: style),
          const SizedBox(width: 12),
          Flexible(child: Text(r, style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text(
            data.businessName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.deepTeal,
            ),
          ),
          if (data.address.isNotEmpty)
            Text(data.address, textAlign: TextAlign.center),
          if (data.phone.isNotEmpty)
            Text(data.phone, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const _DashedLine(),
          const SizedBox(height: 8),

          // Meta
          _line('Receipt no.', data.receiptNo),
          _line('Date', data.formattedDate),
          if (data.customerName.isNotEmpty) _line('Customer', data.customerName),
          _line('Payment', data.paymentMethod),
          const SizedBox(height: 8),
          const _DashedLine(),
          const SizedBox(height: 8),

          // Items header
          const Row(
            children: [
              Expanded(
                  child: Text('Item',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              SizedBox(
                  width: 36,
                  child: Text('Qty',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold))),
              SizedBox(
                  width: 84,
                  child: Text('Amount',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 6),

          // Items
          for (final item in data.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name),
                        Text(
                          '@ ${money(item.price)}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                      width: 36,
                      child: Text('${item.qty}', textAlign: TextAlign.center)),
                  SizedBox(
                      width: 84,
                      child: Text(money(item.total), textAlign: TextAlign.right)),
                ],
              ),
            ),

          const SizedBox(height: 6),
          const _DashedLine(),
          const SizedBox(height: 8),

          // Totals
          _line('Subtotal', money(data.subtotal)),
          if (data.appliedDiscount > 0)
            _line('Discount', '- ${money(data.appliedDiscount)}'),
          if (data.taxPercent > 0)
            _line('Tax (${data.taxPercent.toStringAsFixed(data.taxPercent % 1 == 0 ? 0 : 1)}%)',
                money(data.tax)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(6),
            ),
            child: _line('TOTAL', money(data.total), bold: true, size: 17),
          ),

          if (data.notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Notes: ${data.notes}',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),
          const Text(
            'Thank you!',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepTeal),
          ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = (c.maxWidth / 7).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          n,
          (_) => Container(width: 4, height: 1, color: Colors.black38),
        ),
      );
    });
  }
}

// ===========================================================================
// PDF (80mm receipt roll). Mirror any template changes here too.
// ===========================================================================
Future<Uint8List> buildReceiptPdf(ReceiptData d) async {
  final doc = pw.Document();

  final deepTeal = PdfColor.fromHex('#08786D');
  final gold = PdfColor.fromHex('#F8E692');
  final textColor = PdfColor.fromHex('#183C38');

  pw.TextStyle st({double size = 9, bool bold = false, PdfColor? color}) =>
      pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color ?? textColor,
      );

  pw.Widget row(String l, String r, {bool bold = false, double size = 9}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(l, style: st(size: size, bold: bold)),
            pw.SizedBox(width: 8),
            pw.Flexible(
              child: pw.Text(r,
                  style: st(size: size, bold: bold),
                  textAlign: pw.TextAlign.right),
            ),
          ],
        ),
      );

  pw.Widget divider() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Divider(thickness: 0.6, color: PdfColors.grey600, height: 1),
      );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(14),
      build: (ctx) => pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(d.businessName,
              textAlign: pw.TextAlign.center,
              style: st(size: 14, bold: true, color: deepTeal)),
          if (d.address.isNotEmpty)
            pw.Text(d.address,
                textAlign: pw.TextAlign.center, style: st(size: 8)),
          if (d.phone.isNotEmpty)
            pw.Text(d.phone,
                textAlign: pw.TextAlign.center, style: st(size: 8)),
          divider(),
          row('Receipt no.', d.receiptNo, size: 8),
          row('Date', d.formattedDate, size: 8),
          if (d.customerName.isNotEmpty)
            row('Customer', d.customerName, size: 8),
          row('Payment', d.paymentMethod, size: 8),
          divider(),
          for (final item in d.items)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(item.name, style: st(bold: true)),
                  row('${item.qty} x ${money(item.price)}', money(item.total),
                      size: 8),
                ],
              ),
            ),
          divider(),
          row('Subtotal', money(d.subtotal)),
          if (d.appliedDiscount > 0)
            row('Discount', '- ${money(d.appliedDiscount)}'),
          if (d.taxPercent > 0)
            row(
                'Tax (${d.taxPercent.toStringAsFixed(d.taxPercent % 1 == 0 ? 0 : 1)}%)',
                money(d.tax)),
          pw.SizedBox(height: 6),
          pw.Container(
            color: gold,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: row('TOTAL', money(d.total), bold: true, size: 12),
          ),
          if (d.notes.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Notes: ${d.notes}', style: st(size: 8)),
          ],
          pw.SizedBox(height: 10),
          pw.Text('Thank you!',
              textAlign: pw.TextAlign.center,
              style: st(size: 10, bold: true, color: deepTeal)),
        ],
      ),
    ),
  );

  return doc.save();
}