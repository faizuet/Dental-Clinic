import 'dart:typed_data';

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
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(financeRepositoryProvider);
      final entry = await repo.treatmentById(widget.id);
      if (entry == null) {
        throw Exception('Treatment was not found.');
      }
      final images = <String, List<int>>{};
      for (final attachment in entry.attachments) {
        try {
          images[attachment.id] = await repo.treatmentAttachmentBytes(entry.id, attachment.id);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _entry = entry;
          _images
            ..clear()
            ..addAll(images);
          _loading = false;
        });
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
                          AppSplit(
                            primary: _section('Patient information', [
                            _row('Sr. No.', entry.serialNo?.toString() ?? '—'),
                            _row('Patient', entry.displayPatientName),
                            if (entry.patientPhone != null) _row('Phone', entry.patientPhone!),
                            _row('Date', formatDisplayDate(entry.date)),
                            _row('Main treatment', displayMainTreatment(entry.catalogName, categoryName: entry.categoryName)),
                            _row('Sub-treatment', displaySubTreatment(
                                  subTreatment: entry.subTreatment,
                                  details: entry.details,
                                  catalogName: entry.catalogName,
                                ) ??
                                '—'),
                            _row('Fee', formatMoney(entry.amount, currency: currency)),
                          ]),
                            secondary: _section('Dental information', [
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
                          ),
                          const SizedBox(height: 12),
                          _xraySection(entry),
                        ],
                      ),
        ),
      ),
    );
  }

  Widget _xraySection(MoneyEntry entry) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('X-ray images', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (entry.attachments.isEmpty)
              Text(
                'No X-ray attached to this treatment.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final attachment in entry.attachments) _xrayTile(attachment),
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
                        child: Image.memory(
                          Uint8List.fromList(bytes),
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
            child: Image.memory(
              Uint8List.fromList(bytes),
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

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
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
