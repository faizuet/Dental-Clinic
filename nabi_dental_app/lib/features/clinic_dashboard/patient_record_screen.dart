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
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/page_kit.dart';
import '../../core/widgets/record_pager.dart';
import 'patient_form_dialog.dart';

class PatientRecordScreen extends ConsumerStatefulWidget {
  const PatientRecordScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<PatientRecordScreen> createState() => _PatientRecordScreenState();
}

class _PatientRecordScreenState extends ConsumerState<PatientRecordScreen> {
  PatientRecord? _patient;
  List<MoneyEntry> _treatments = [];
  int _page = 0;
  final _images = <String, List<int>>{};
  bool _loading = true;
  bool _opening = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.listenManual(financeEpochProvider, (previous, next) {
      if (previous != next) {
        _reloadLocal();
      }
    });
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
          _showTreatments(treatments);
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
          _showTreatments(treatments);
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

  Future<void> _reloadLocal() async {
    final repo = ref.read(financeRepositoryProvider);
    final patient = await repo.patientById(widget.patientId);
    if (!mounted || patient == null) {
      return;
    }
    final treatments = await repo.patientTreatments(patient.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _patient = patient;
      _showTreatments(treatments);
      _loading = false;
      _error = null;
    });
  }

  void _showTreatments(List<MoneyEntry> treatments) {
    _page = settleRecordPage(page: _page, previousCount: _treatments.length, nextCount: treatments.length);
    _treatments = treatments;
  }

  String _latestVisitDate() {
    var latest = _treatments.first.date;
    for (final item in _treatments.skip(1)) {
      if (item.date.compareTo(latest) > 0) {
        latest = item.date;
      }
    }
    return latest;
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

  Future<void> _editPatient() async {
    final patient = _patient;
    if (patient == null || _opening || _saving) {
      return;
    }
    final repo = ref.read(financeRepositoryProvider);
    final patients = await repo.patients();
    if (!mounted) {
      return;
    }
    final result = await showDialog<({String name, String phone})>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => PatientFormDialog(existing: patient, patients: patients),
    );
    if (!mounted || result == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await repo.updatePatient(
        patient,
        name: result.name,
        phone: result.phone.isEmpty ? null : result.phone,
      );
      if (!mounted) {
        return;
      }
      setState(() => _patient = updated);
      showAppSnack(context, 'Patient updated.');
      await _load();
    } catch (error) {
      if (mounted) {
        showAppSnack(context, friendlyError(error), error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

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
          if (patient != null) ...[
            IconButton(
              tooltip: 'Edit patient',
              onPressed: _opening || _saving ? null : _editPatient,
              icon: const Icon(Icons.edit_rounded),
            ),
            IconButton(
              tooltip: 'Add treatment',
              onPressed: _opening || _saving ? null : () => _openOnce(_addTreatmentLocation),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ],
      ),
      body: AppStateSwitch(
        child: _loading
            ? Padding(
                key: const ValueKey('patient-loading'),
                padding: AppLayout.pagePadding(context),
                child: const SkeletonCards(count: 2),
              )
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
                    : PageScaffoldBody(
                        key: ValueKey('patient-${patient.id}'),
                        children: [
                          _profileHeader(patient),
                          const SizedBox(height: 20),
                          StatStrip(items: _stats(currency)),
                          const SizedBox(height: 20),
                          _historySection(currency),
                          const SizedBox(height: 20),
                          _xraySection(),
                        ],
                      ),
      ),
    );
  }

  Widget _profileHeader(PatientRecord patient) {
    final theme = Theme.of(context);
    final notes = patient.notes;
    return TablePanel(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 20,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InitialsAvatar(name: patient.name, size: 68),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(patient.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 20,
                            runSpacing: 6,
                            children: [
                              IconText(icon: Icons.call_rounded, text: patient.phone ?? '—', muted: true),
                              IconText(
                                icon: Icons.event_available_rounded,
                                text: patient.createdAt == null ? 'Registered —' : 'Registered ${formatDisplayDate(patient.createdAt)}',
                                muted: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _opening || _saving ? null : _editPatient,
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Edit patient'),
                    ),
                    PrimaryAction(
                      label: 'Add Treatment',
                      icon: Icons.add_rounded,
                      onPressed: _opening || _saving ? null : () => _openOnce(_addTreatmentLocation),
                    ),
                  ],
                ),
              ],
            ),
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sticky_note_2_rounded, size: 18, color: AppColors.orange),
                    const SizedBox(width: 10),
                    Expanded(child: Text(notes)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<MiniStat> _stats(String currency) {
    final billed = _treatments.fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount));
    final xrays = _treatments.fold<int>(0, (sum, item) => sum + item.attachments.length);
    return [
      MiniStat(
        label: 'Treatments',
        value: '${_treatments.length}',
        icon: Icons.medical_services_rounded,
        color: AppColors.primary,
        soft: AppColors.primarySoft,
      ),
      MiniStat(
        label: 'Total Billed',
        value: formatMoney(moneyFromDouble(billed), currency: currency),
        icon: Icons.payments_rounded,
        color: AppColors.success,
        soft: AppColors.mintSoft,
      ),
      MiniStat(
        label: 'Latest Visit',
        value: _treatments.isEmpty ? 'No treatments yet' : formatDisplayDate(_latestVisitDate()),
        icon: Icons.event_rounded,
        color: AppColors.violet,
        soft: AppColors.violetSoft,
      ),
      MiniStat(
        label: 'X-ray Images',
        value: '$xrays',
        icon: Icons.image_rounded,
        color: AppColors.aqua,
        soft: AppColors.aquaSoft,
      ),
    ];
  }

  Widget _historySection(String currency) {
    final page = RecordPage.of(_treatments, _page);
    return TablePanel(
      header: PanelTitle(
        title: 'Treatment history',
        subtitle: 'Every visit linked to this patient',
        icon: Icons.history_rounded,
        trailing: TextButton.icon(
          onPressed: _opening ? null : () => _openOnce(_addTreatmentLocation),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add treatment'),
        ),
      ),
      footer: _treatments.isEmpty
          ? null
          : RecordPageBar<MoneyEntry>(
              page: page,
              noun: _treatments.length == 1 ? 'treatment' : 'treatments',
              onPage: (value) => setState(() => _page = value),
            ),
      child: _treatments.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No treatments are linked to this patient yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < page.items.length; index++) ...[
                  if (index > 0) const Divider(height: 1, indent: 20, endIndent: 20),
                  AppReveal(index: index, child: _treatmentTile(page.items[index], currency)),
                ],
              ],
            ),
    );
  }

  Widget _treatmentTile(MoneyEntry entry, String currency) {
    final theme = Theme.of(context);
    final detail = entry.detailsText ??
        clinicalSummary(
          entry.details,
          subTreatment: displaySubTreatment(
            subTreatment: entry.subTreatment,
            details: entry.details,
            catalogName: entry.catalogName,
          ),
        );
    final title = [
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
    ].join(' · ');
    return InkWell(
      onTap: _opening ? null : () => _openOnce('/clinic/income/${entry.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.medical_services_rounded, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    [formatDisplayDate(entry.date), if (detail.isNotEmpty) detail].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            MoneyText(
              formatMoney(entry.amount, currency: currency),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              color: AppColors.success,
            ),
            const SizedBox(width: 12),
            RowAction(
              icon: Icons.visibility_outlined,
              tooltip: 'View',
              onPressed: _opening ? null : () => _openOnce('/clinic/income/${entry.id}'),
            ),
            const SizedBox(width: 6),
            RowAction(
              icon: Icons.edit_outlined,
              tooltip: 'Edit',
              color: AppColors.success,
              soft: AppColors.successSoft,
              onPressed: _opening ? null : () => _openOnce('/clinic/income/${entry.id}/edit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _xraySection() {
    final tiles = [
      for (final visit in _treatments)
        for (final attachment in visit.attachments) (visit: visit, attachment: attachment),
    ];
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
        child: tiles.isEmpty
            ? Text(
                'No X-ray attached to this patient yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              )
            : Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final tile in tiles) _xrayTile(tile.visit, tile.attachment),
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
}
