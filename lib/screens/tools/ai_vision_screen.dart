import 'dart:io';

import 'package:add_2_calendar/add_2_calendar.dart' as cal;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/ai_service.dart';
import '../../services/office_export.dart';
import '../../providers/subscription_provider.dart';
import '../../widgets/ai_badge.dart';
import '../../widgets/ai_error.dart';
import '../../widgets/image_source_sheet.dart';
import '../../widgets/tool_widgets.dart';

/// Rasm → AI natija: jadval (Excel), masala yechimi yoki formula (LaTeX).
class AiVisionScreen extends StatefulWidget {
  final AiVisionTask task;

  const AiVisionScreen({super.key, required this.task});

  @override
  State<AiVisionScreen> createState() => _AiVisionScreenState();
}

class _AiVisionScreenState extends State<AiVisionScreen> {
  File? _image;
  Map<String, dynamic>? _result;
  bool _busy = false;

  String get _key => switch (widget.task) {
    AiVisionTask.table => 'excel',
    AiVisionTask.solve => 'solver',
    AiVisionTask.formula => 'formula',
    AiVisionTask.explain => 'explain',
    AiVisionTask.deadlines => 'deadlines',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  Future<void> _pick() async {
    final files = await pickImages(context, multiple: false);
    if (files.isEmpty) return;
    setState(() {
      _image = files.first;
      _result = null;
    });
    await _run();
  }

  Future<void> _run() async {
    final image = _image;
    if (image == null) return;
    final sub = context.read<SubscriptionProvider>();
    setState(() => _busy = true);
    try {
      final error = sub.quota?.check(1);
      if (error != null) throw error;
      final out = await AiService.vision(
        await image.readAsBytes(),
        task: widget.task,
        lang: context.locale.toLanguageTag(),
      );
      sub.updateQuota(out.quota);
      if (mounted) setState(() => _result = out.result);
    } catch (e) {
      if (mounted) await showAiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showToolMessage(context, 'ocr_copied'.tr());
  }

  List<({String name, List<List<String>> rows})> get _tables => [
    for (final t in (_result?['tables'] as List? ?? const []))
      (
        name: '${t['name'] ?? ''}',
        rows: [
          for (final r in (t['rows'] as List? ?? const []))
            [for (final c in r as List) '$c'],
        ],
      ),
  ];

  Future<void> _saveExcel() async {
    final tables = _tables.where((t) => t.rows.isNotEmpty).toList();
    if (tables.isEmpty) return;
    final file = await OfficeExport.save(
      OfficeExport.xlsx(tables),
      tables.first.name.isEmpty ? 'jadval' : tables.first.name,
      'xlsx',
    );
    if (mounted) await showSavedFileSheet(context, file);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      appBar: AppBar(
        title: AiTitle('feature_$_key'.tr()),
        actions: [
          if (image != null && !_busy)
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _pick,
            ),
        ],
      ),
      body: image == null
          ? ToolEmptyState(
              icon: Icons.add_a_photo_outlined,
              title: 'feature_$_key'.tr(),
              hint: '${_key}_hint'.tr(),
              buttonText: 'pick_image'.tr(),
              onPressed: _pick,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Image.file(image, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 16),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_result != null)
                  ..._buildResult()
                else
                  // Xato yoki kirish oynasidan keyin — shu rasm bilan qayta
                  Center(
                    child: FilledButton.icon(
                      onPressed: _run,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text('ai_retry'.tr()),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar:
          widget.task == AiVisionTask.table && _tables.isNotEmpty && !_busy
          ? ToolActionBar(
              label: 'excel_save'.tr(),
              icon: Icons.table_view_rounded,
              onPressed: _saveExcel,
            )
          : null,
    );
  }

  List<Widget> _buildResult() {
    final r = _result!;
    return switch (widget.task) {
      AiVisionTask.table => [
        for (final t in _tables) _TablePreview(t.name, t.rows),
      ],
      AiVisionTask.solve => [
        _Section(title: 'solver_problem'.tr(), text: '${r['problem'] ?? ''}'),
        for (final (i, step) in (r['steps'] as List? ?? const []).indexed)
          _Section(
            title: 'solver_step'.tr(namedArgs: {'n': '${i + 1}'}),
            text: '$step',
          ),
        _Section(
          title: 'solver_answer'.tr(),
          text: '${r['answer'] ?? ''}',
          highlight: true,
          onCopy: () => _copy('${r['answer'] ?? ''}'),
        ),
      ],
      AiVisionTask.formula => [
        _Section(
          title: 'formula_text'.tr(),
          text: '${r['text'] ?? ''}',
          onCopy: () => _copy('${r['text'] ?? ''}'),
        ),
        _Section(
          title: 'LaTeX',
          text: '${r['latex'] ?? ''}',
          mono: true,
          highlight: true,
          onCopy: () => _copy('${r['latex'] ?? ''}'),
        ),
        Text(
          'formula_word_hint'.tr(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      AiVisionTask.explain => [
        _Section(
          title: '${r['doc_type'] ?? ''}',
          text: '${r['summary'] ?? ''}',
          highlight: true,
          onCopy: () => _copy(_explainText(r)),
        ),
        for (final (key, icon) in const [
          ('key_points', Icons.lightbulb_outline_rounded),
          ('actions', Icons.task_alt_rounded),
          ('warnings', Icons.warning_amber_rounded),
        ])
          if ((r[key] as List? ?? const []).isNotEmpty)
            _BulletSection(
              title: 'explain_$key'.tr(),
              icon: icon,
              warning: key == 'warnings',
              items: [for (final x in r[key] as List) '$x'],
            ),
      ],
      AiVisionTask.deadlines => _deadlines(r),
    };
  }

  /// Tushuntirishni bitta matn qilib (nusxalash uchun).
  String _explainText(Map<String, dynamic> r) => [
    '${r['doc_type'] ?? ''}',
    '${r['summary'] ?? ''}',
    for (final key in ['key_points', 'actions', 'warnings'])
      if ((r[key] as List? ?? const []).isNotEmpty)
        '\n${'explain_$key'.tr()}:\n${(r[key] as List).map((x) => '• $x').join('\n')}',
  ].join('\n');

  List<Widget> _deadlines(Map<String, dynamic> r) {
    final items = [
      for (final i in (r['items'] as List? ?? const []))
        if (DateTime.tryParse('${i['date']}') case final date?)
          (
            title: '${i['title'] ?? ''}',
            details: '${i['details'] ?? ''}',
            date: date,
            time: RegExp(r'^\d{1,2}:\d{2}$').hasMatch('${i['time']}')
                ? '${i['time']}'
                : null,
          ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('deadlines_none'.tr(), textAlign: TextAlign.center),
        ),
      ];
    }
    final today = DateUtils.dateOnly(DateTime.now());
    return [
      for (final d in items)
        _DeadlineCard(
          title: d.title,
          details: d.details,
          date: d.date,
          time: d.time,
          daysLeft: DateUtils.dateOnly(d.date).difference(today).inDays,
          onAdd: () => _addToCalendar(d.title, d.details, d.date, d.time),
        ),
    ];
  }

  /// Telefon kalendari ochiladi — eslatmani kalendar o'zi beradi (ilova
  /// yopiq bo'lsa ham), ruxsat so'ralmaydi.
  Future<void> _addToCalendar(
    String title,
    String details,
    DateTime date,
    String? time,
  ) async {
    final parts = time?.split(':');
    final start = parts == null
        ? date
        : DateTime(
            date.year,
            date.month,
            date.day,
            int.parse(parts[0]),
            int.parse(parts[1]),
          );
    final ok = await cal.Add2Calendar.addEvent2Cal(
      cal.Event(
        title: title,
        description: details,
        startDate: start,
        endDate: parts == null ? start : start.add(const Duration(hours: 1)),
        allDay: parts == null,
        iosParams: const cal.IOSParams(reminder: Duration(days: 1)),
      ),
    );
    if (!ok && mounted)
      showToolMessage(context, 'deadlines_no_calendar'.tr(), error: true);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String text;
  final bool highlight;
  final bool mono;
  final VoidCallback? onCopy;

  const _Section({
    required this.title,
    required this.text,
    this.highlight = false,
    this.mono = false,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: highlight ? cs.primaryContainer : null,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: highlight ? cs.onPrimaryContainer : cs.primary,
                    ),
                  ),
                ),
                if (onCopy != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: onCopy,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              text,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TablePreview extends StatelessWidget {
  final String name;
  final List<List<String>> rows;

  const _TablePreview(this.name, this.rows);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: cs.outlineVariant),
              children: [
                for (final (i, row) in rows.indexed)
                  TableRow(
                    decoration: i == 0
                        ? BoxDecoration(color: cs.surfaceContainerHigh)
                        : null,
                    children: [
                      for (var c = 0; c < cols; c++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Text(
                            c < row.length ? row[c] : '',
                            style: TextStyle(
                              fontWeight: i == 0 ? FontWeight.w700 : null,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool warning;
  final List<String> items;

  const _BulletSection({
    required this.title,
    required this.icon,
    required this.items,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = warning ? const Color(0xFFE5484D) : cs.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '•  ',
                      style: TextStyle(fontSize: 15, height: 1.45),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(fontSize: 15, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeadlineCard extends StatelessWidget {
  final String title;
  final String details;
  final DateTime date;
  final String? time;
  final int daysLeft;
  final VoidCallback onAdd;

  const _DeadlineCard({
    required this.title,
    required this.details,
    required this.date,
    required this.time,
    required this.daysLeft,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final past = daysLeft < 0;
    // 3 kundan kam qolgan muddat — qizil, o'tib ketgani — kulrang
    final accent = past
        ? cs.onSurfaceVariant
        : (daysLeft <= 3 ? const Color(0xFFE5484D) : cs.primary);
    final when = past
        ? 'deadlines_past'.tr()
        : daysLeft == 0
        ? 'deadlines_today'.tr()
        : 'deadlines_in_days'.tr(namedArgs: {'n': '$daysLeft'});
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 58,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  Text(
                    DateFormat.MMM(context.locale.toString()).format(date),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat.yMd(context.locale.toString()).format(date)}${time == null ? '' : '  $time'} · $when',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
            if (!past)
              IconButton(
                tooltip: 'deadlines_add'.tr(),
                icon: Icon(Icons.event_available_rounded, color: cs.primary),
                onPressed: onAdd,
              ),
          ],
        ),
      ),
    );
  }
}
