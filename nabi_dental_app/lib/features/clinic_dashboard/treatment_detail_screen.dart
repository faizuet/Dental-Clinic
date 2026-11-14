import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/dental/tooth_catalog.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/export/file_saver.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_memory_image.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/empty_state.dart';

class TreatmentDetailScreen extends ConsumerStatefulWidget {
  const TreatmentDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<TreatmentDetailScreen> createState() => _TreatmentDetailScreenState();
}

class _TreatmentDetailScreenState extends ConsumerState<TreatmentDetailScreen> {
  MoneyEntry? _entry;
  final _images = <String, List<int>>{};
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_entry == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repo = ref.read(financeRepositoryProvider);
      var entry = await repo.treatmentById(widget.id);
      if (entry == null) {
        throw Exception('Treatment was not found.');
      }
      if (mounted) {
        setState(() {
          _entry = entry;
          _loading = false;
        });
      }
      entry = await repo.treatmentById(widget.id, remote: true) ?? entry;
      if (mounted) {
        setState(() => _entry = entry);
      }
      for (final attachment in entry.attachments) {
        if (_images.containsKey(attachment.id)) {
          continue;
        }
        try {
          final bytes = await repo.treatmentAttachmentBytes(entry.id, attachment.id);
          if (!mounted) {
            return;
          }
          setState(() => _images[attachment.id] = bytes);
        } catch (_) {}
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = friendlyError(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final file = await ref.read(financeRepositoryProvider).exportTreatment(widget.id);
      await saveBytes(bytes: file.bytes, filename: file.filename, mime: file.mime);
      if (mounted) {
        showAppSnack(context, 'Treatment PDF saved.');
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(context, friendlyError(error, feature: 'report'), error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).clinic?.currency ?? 'PKR';
    final entry = _entry;
    return Scaffold(
      appBar: buildAppBar(
        context: context,
        title: 'Treatment record',
        fallback: '/clinic/income/history',
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: entry == null
                ? null
                : () async {
                    await appPush(context, '/clinic/income/${widget.id}/edit');
                    if (mounted) {
                      await _load();
                    }
                  },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Add lab charge',
            onPressed: entry == null
                ? null
                : () => appPush(
                      context,
                      '/clinic/lab-charges/new?transactionId=${Uri.encodeQueryComponent(widget.id)}',
                    ),
            icon: const Icon(Icons.science_outlined),
          ),
          IconButton(
            tooltip: 'Export PDF',
            onPressed: entry == null || _exporting ? null : _export,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context),
        child: AppStateSwitch(
          child: _loading
            ? const Center(key: ValueKey('detail-loading'), child: SkeletonCards(count: 2))
            : _error != null
                ? EmptyState(
                    key: const ValueKey('detail-error'),
                    title: 'Could not open record',
                    message: _error!,
                    icon: Icons.wifi_off_rounded,
                    actionLabel: 'Retry',
                    onAction: _load,
                  )
                : entry == null
                    ? const EmptyState(key: ValueKey('detail-missing'), title: 'Not found', message: 'This treatment record is not available.', icon: Icons.healing_outlined)
                    : ListView(
                        key: const ValueKey('detail-body'),
                        children: [
                          _summary(entry, currency),
                          const SizedBox(height: 16),
                          _section('Patient information', icon: Icons.person_rounded, [
                            _row('Sr. No.', entry.serialNo?.toString() ?? '—'),
                            _row('Patient', entry.displayPatientName),
                            if (entry.patientPhone != null) _row('Phone', entry.patientPhone!),
                            _row('Date', formatDisplayDate(entry.date)),
                            _row(
                              explicitVisitItems(entry.details) != null &&
                                      explicitVisitItems(entry.details)!.length > 1
                                  ? 'Treatments'
                                  : 'Treatment',
                              explicitVisitItems(entry.details) != null &&
                                      explicitVisitItems(entry.details)!.length > 1
                                  ? visitMainLabel(
                                      catalogName: entry.catalogName,
                                      categoryName: entry.categoryName,
                                      details: entry.details,
                                    )
                                  : displaySubTreatment(
                                        subTreatment: entry.subTreatment,
                                        details: entry.details,
                                        catalogName: entry.catalogName,
                                      ) ??
                                      entry.catalogName,
                            ),
                            _row('Total fee', formatMoney(entry.amount, currency: currency)),
                          ]),
                          const SizedBox(height: 16),
                          ..._treatmentSections(entry, currency),
                        ],
                      ),
        ),
      ),
    );
  }

  List<Widget> _treatmentSections(MoneyEntry entry, String currency) {
    final explicit = explicitVisitItems(entry.details);
    final items = visitItems(entry.details);
    if (explicit == null) {
      return [
        _section('Dental information', [
          _row(
            'Details',
            entry.detailsText ??
                clinicalSummary(
                  entry.details,
                  subTreatment: displaySubTreatment(
                    subTreatment: entry.subTreatment,
                    details: entry.details,
                    catalogName: entry.catalogName,
                  ),
                ),
          ),
          if (entry.notes != null) _row('Notes', entry.notes!),
        ]),
        const SizedBox(height: 12),
        _xraySection(entry, entry.attachments),
      ];
    }
    final assigned = <String>{
      for (final item in items)
        for (final value in item['attachment_ids'] is List ? item['attachment_ids'] as List : const []) value.toString(),
    };
    final leftover = [
      for (final attachment in entry.attachments)
        if (!assigned.contains(attachment.id)) attachment,
    ];
    return [
      for (var index = 0; index < items.length; index++) ...[
        _itemSection(entry, items[index], index, currency),
        const SizedBox(height: 12),
      ],
      if (leftover.isNotEmpty) _xraySection(entry, leftover),
    ];
  }

  Widget _itemSection(MoneyEntry entry, Map<String, dynamic> item, int index, String currency) {
    final name = item['sub_treatment']?.toString() ?? item['treatment_name']?.toString() ?? entry.catalogName;
    final amount = item['amount']?.toString();
    final notes = item['notes']?.toString();
    final attachmentIds = {
      for (final value in item['attachment_ids'] is List ? item['attachment_ids'] as List : const []) value.toString(),
    };
    final images = [
      for (final attachment in entry.attachments)
        if (attachmentIds.contains(attachment.id)) attachment,
    ];
    return _section('Treatment ${index + 1}', [
      _row('Treatment', name),
      _row('Details', clinicalSummary(item, subTreatment: name)),
      if (amount != null && amount.isNotEmpty) _row('Fee', formatMoney(amount, currency: currency)),
      if (notes != null && notes.isNotEmpty) _row('Notes', notes),
      if (images.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final attachment in images) _xrayTile(attachment),
          ],
        ),
      ],
    ]);
  }

  Widget _xraySection(MoneyEntry entry, List<TreatmentAttachment> attachments) {
    return TablePanel(
      header: const PanelTitle(
        title: 'X-ray images',
        subtitle: 'Tap an image to preview it',
        icon: Icons.image_rounded,
        color: AppColors.aqua,
        soft: AppColors.aquaSoft,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachments.isEmpty)
              Text(
                'No X-ray attached to this treatment.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final attachment in attachments) _xrayTile(attachment),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _xrayTile(TreatmentAttachment attachment) {
    final bytes = _images[attachment.id];
    final label = attachment.label.replaceAll('_', ' ').toUpperCase();
    const frameWidth = 220.0;
    const frameHeight = 156.0;
    return SizedBox(
      width: frameWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: bytes == null ? null : () => _previewImage(label: label, bytes: bytes),
              child: Ink(
                width: frameWidth,
                height: frameHeight,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: bytes == null
                    ? Center(
                        child: Text(
                          'Image could not be loaded.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(8),
                        child: AppMemoryImage(
                          bytes: bytes,
                          width: frameWidth - 16,
                          height: frameHeight - 16,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _previewImage({required String label, required List<int> bytes}) {
    return showAppDialog<void>(
      context: context,
      title: label,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: ColoredBox(
            color: AppColors.inputFill,
            child: AppMemoryImage(
              bytes: bytes,
              width: 420,
              height: 320,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
      actions: (dialogContext) => [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
      ],
    );
  }

  Widget _section(String title, List<Widget> children, {IconData icon = Icons.healing_rounded}) {
    return TablePanel(
      header: PanelTitle(title: title, icon: icon),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _summary(MoneyEntry entry, String currency) {
    final theme = Theme.of(context);
    return TablePanel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 20,
          runSpacing: 16,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InitialsAvatar(name: entry.displayPatientName, size: 60),
                const SizedBox(width: 16),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.displayPatientName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 18,
                        runSpacing: 6,
                        children: [
                          IconText(icon: Icons.event_rounded, text: formatDisplayDate(entry.date), muted: true),
                          if (entry.serialNo != null) IconText(icon: Icons.tag_rounded, text: 'Sr. No. ${entry.serialNo}', muted: true),
                          if (entry.patientPhone != null) IconText(icon: Icons.call_rounded, text: entry.patientPhone!, muted: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(color: AppColors.mintSoft, borderRadius: BorderRadius.circular(AppRadii.md)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Total fee', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700)),
                  Text(
                    formatMoney(entry.amount, currency: currency),
                    style: theme.textTheme.titleLarge?.copyWith(color: AppColors.success, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    if (AppLayout.isDesktop(context)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(label, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}
