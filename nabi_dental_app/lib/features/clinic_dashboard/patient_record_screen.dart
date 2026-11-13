import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/dental/tooth_catalog.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_memory_image.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/empty_state.dart';

class PatientRecordScreen extends ConsumerStatefulWidget {
  const PatientRecordScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<PatientRecordScreen> createState() => _PatientRecordScreenState();
}

class _PatientRecordScreenState extends ConsumerState<PatientRecordScreen> {
  PatientRecord? _patient;
  List<MoneyEntry> _treatments = [];
  final _images = <String, List<int>>{};
  bool _loading = true;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_patient == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repo = ref.read(financeRepositoryProvider);
      var patient = await repo.patientById(widget.patientId);
      if (patient == null) {
        throw Exception('Patient was not found.');
      }
      var treatments = await repo.patientTreatments(patient.id);
      if (mounted) {
        setState(() {
          _patient = patient;
          _treatments = treatments;
          _loading = false;
        });
      }
      final remotePatient = await repo.patientById(widget.patientId, remote: true);
      if (remotePatient != null) {
        patient = remotePatient;
      }
      treatments = await repo.patientTreatments(patient.id, remote: true);
      if (mounted) {
        setState(() {
          _patient = patient;
          _treatments = treatments;
        });
      }
      await _loadImages(treatments);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = friendlyError(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadImages(List<MoneyEntry> treatments) async {
    final repo = ref.read(financeRepositoryProvider);
    for (final visit in treatments) {
      for (final attachment in visit.attachments) {
        if (_images.containsKey(attachment.id)) {
          continue;
        }
        try {
          final bytes = await repo.treatmentAttachmentBytes(visit.id, attachment.id);
          if (!mounted) {
            return;
          }
          setState(() => _images[attachment.id] = bytes);
        } catch (_) {}
      }
    }
  }

  String get _addTreatmentLocation =>
      '/clinic/income?patientId=${Uri.encodeQueryComponent(widget.patientId)}';

  Future<void> _openOnce(String location) async {
    if (_opening) {
      return;
    }
    _opening = true;
    try {
      await appPush(context, location);
      if (mounted) {
        await _load();
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(sessionProvider).clinic?.currency ?? 'PKR';
    final patient = _patient;
    return Scaffold(
      appBar: buildAppBar(
        context: context,
        title: patient?.name ?? 'Patient record',
        fallback: '/clinic/patients',
        actions: [
          if (patient != null)
            IconButton(
              tooltip: 'Add treatment',
              onPressed: _opening ? null : () => _openOnce(_addTreatmentLocation),
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: AppPageBody(
        padding: AppLayout.pagePadding(context),
        child: AppStateSwitch(
          child: _loading
              ? const Center(key: ValueKey('patient-loading'), child: SkeletonCards(count: 2))
              : _error != null
                  ? EmptyState(
                      key: const ValueKey('patient-error'),
                      title: 'Could not open patient',
                      message: _error!,
                      icon: Icons.people_outline_rounded,
                      actionLabel: 'Retry',
                      onAction: _load,
                    )
                  : patient == null
                      ? const EmptyState(
                          key: ValueKey('patient-missing'),
                          title: 'Not found',
                          message: 'This patient record is not available.',
                          icon: Icons.people_outline_rounded,
                        )
                      : ListView(
                          key: ValueKey('patient-${patient.id}'),
                          children: [
                            AppSplit(
                              primary: _section('Patient information', [
                                _row('Patient', patient.name),
                                _row('Phone', patient.phone ?? '—'),
                                _row(
                                  'Registered',
                                  patient.createdAt == null ? '—' : formatDisplayDate(patient.createdAt),
                                ),
                                _row('Treatments', '${_treatments.length}'),
                              ]),
                              secondary: _section('Dental information', [
                                _row(
                                  'Latest visit',
                                  _treatments.isEmpty ? 'No treatments yet' : formatDisplayDate(_treatments.first.date),
                                ),
                                if (patient.notes != null && patient.notes!.isNotEmpty) _row('Notes', patient.notes!),
                              ]),
                            ),
                            const SizedBox(height: 12),
                            _historySection(currency),
                            const SizedBox(height: 12),
                            _xraySection(),
                          ],
                        ),
        ),
      ),
    );
  }

  Widget _historySection(String currency) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Treatment history', style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: _opening ? null : () => _openOnce(_addTreatmentLocation),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add treatment'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_treatments.isEmpty)
              Text(
                'No treatments are linked to this patient yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              )
            else
              for (var index = 0; index < _treatments.length; index++)
                AppReveal(
                  index: index,
                  child: _treatmentTile(_treatments[index], currency),
                ),
          ],
        ),
      ),
    );
  }

  Widget _treatmentTile(MoneyEntry entry, String currency) {
    final detail = entry.detailsText ??
        clinicalSummary(
          entry.details,
          subTreatment: displaySubTreatment(
            subTreatment: entry.subTreatment,
            details: entry.details,
            catalogName: entry.catalogName,
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (entry.serialNo != null) '#${entry.serialNo}',
                        visitMainLabel(
                          catalogName: entry.catalogName,
                          categoryName: entry.categoryName,
                          details: entry.details,
                        ),
                        displaySubTreatment(
                              subTreatment: entry.subTreatment,
                              details: entry.details,
                              catalogName: entry.catalogName,
                            ) ??
                            entry.catalogName,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  MoneyText(
                    formatMoney(entry.amount, currency: currency),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  formatDisplayDate(entry.date),
                  if (detail.isNotEmpty) detail,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _opening ? null : () => _openOnce('/clinic/income/${entry.id}'),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View'),
                  ),
                  TextButton.icon(
                    onPressed: _opening ? null : () => _openOnce('/clinic/income/${entry.id}/edit'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _xraySection() {
    final tiles = [
      for (final visit in _treatments)
        for (final attachment in visit.attachments) (visit: visit, attachment: attachment),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('X-ray images', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (tiles.isEmpty)
              Text(
                'No X-ray attached to this patient yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final tile in tiles) _xrayTile(tile.visit, tile.attachment),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _xrayTile(MoneyEntry visit, TreatmentAttachment attachment) {
    final bytes = _images[attachment.id];
    final label = [
      attachment.label.replaceAll('_', ' ').toUpperCase(),
      if (visit.serialNo != null) '#${visit.serialNo}',
    ].join(' · ');
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
