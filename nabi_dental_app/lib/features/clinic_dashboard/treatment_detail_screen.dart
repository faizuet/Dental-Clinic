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
import '../../core/utils/money.dart';
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
      appBar: AppBar(
        leading: const AppBackButton(fallback: '/clinic/income/history'),
        title: const AppBarTitle('Treatment record'),
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? EmptyState(
                    title: 'Could not open record',
                    message: _error!,
                    icon: Icons.wifi_off_rounded,
                    actionLabel: 'Retry',
                    onAction: _load,
                  )
                : entry == null
                    ? const EmptyState(title: 'Not found', message: 'This treatment record is not available.', icon: Icons.healing_outlined)
                    : ListView(
                        children: [
                          _section('Patient information', [
                            _row('Sr. No.', entry.serialNo?.toString() ?? '—'),
                            _row('Patient', entry.patientName ?? 'Walk-in'),
                            if (entry.patientPhone != null) _row('Phone', entry.patientPhone!),
                            _row('Date', entry.date),
                            _row('Main treatment', entry.catalogName),
                            if (entry.subTreatment != null) _row('Sub-treatment', entry.subTreatment!),
                            _row('Fee', formatMoney(entry.amount, currency: currency)),
                          ]),
                          const SizedBox(height: 12),
                          _section('Dental information', [
                            _row('Details', entry.detailsText ?? clinicalSummary(entry.details, subTreatment: entry.subTreatment)),
                            if (entry.notes != null) _row('Notes', entry.notes!),
                          ]),
                          const SizedBox(height: 12),
                          Text('X-ray images', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          if (entry.attachments.isEmpty)
                            Text('No X-ray attached to this treatment.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted))
                          else
                            for (final attachment in entry.attachments)
                              Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        attachment.label.replaceAll('_', ' ').toUpperCase(),
                                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.muted),
                                      ),
                                      const SizedBox(height: 8),
                                      if (_images[attachment.id] != null)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.memory(
                                            Uint8List.fromList(_images[attachment.id]!),
                                            fit: BoxFit.contain,
                                          ),
                                        )
                                      else
                                        const Text('Image could not be loaded.'),
                                    ],
                                  ),
                                ),
                              ),
                        ],
                      ),
      ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppColors.muted))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
