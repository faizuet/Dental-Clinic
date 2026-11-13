import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_motion.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';

class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen({super.key});

  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen> {
  final _search = TextEditingController();
  List<PatientRecord> _patients = [];
  bool _loading = true;
  bool _syncing = false;
  bool _busy = false;
  bool _deleting = false;
  bool _opening = false;
  String? _loadError;
  String? _message;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<PatientRecord> get _visible {
    final needle = _search.text.trim().toLowerCase();
    if (needle.isEmpty) {
      return _patients;
    }
    return _patients
        .where(
          (item) => item.name.toLowerCase().contains(needle) || (item.phone ?? '').toLowerCase().contains(needle),
        )
        .toList();
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (!silent && _patients.isEmpty) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    final repo = ref.read(financeRepositoryProvider);
    try {
      final local = await repo.patients();
      if (mounted) {
        setState(() {
          _patients = local;
          _loading = false;
          _syncing = true;
          _loadError = null;
        });
      }
      await repo.refresh(force: force);
      final items = await repo.patients();
      if (mounted) {
        setState(() {
          _patients = items;
          _loading = false;
          _syncing = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = friendlyError(error);
          _loading = false;
          _syncing = false;
        });
      }
    }
  }

  Future<void> _afterDialog() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
  }

  Future<void> _openRecord(PatientRecord patient) async {
    if (_opening || _busy) {
      return;
    }
    _opening = true;
    try {
      await appPush(context, '/clinic/patients/${patient.id}');
      if (mounted) {
        await _load(silent: true);
      }
    } finally {
      _opening = false;
    }
  }

  Widget _patientName(PatientRecord patient, {int? maxLines}) {
    return Tooltip(
      message: 'Open patient record',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openRecord(patient),
          child: Text(
            patient.name,
            maxLines: maxLines ?? 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary),
          ),
        ),
      ),
    );
  }

  Future<void> _savePatient({PatientRecord? existing}) async {
    final result = await showDialog<({String name, String phone})>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => _PatientFormDialog(existing: existing, patients: _patients),
    );
    await _afterDialog();
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (existing == null) {
        await ref.read(financeRepositoryProvider).savePatient(
              name: result.name,
              phone: result.phone.isEmpty ? null : result.phone,
            );
      } else {
        await ref.read(financeRepositoryProvider).updatePatient(
              existing,
              name: result.name,
              phone: result.phone.isEmpty ? null : result.phone,
            );
      }
      await _load(silent: true);
      if (mounted) {
        showAppSnack(context, existing == null ? 'Patient saved.' : 'Patient updated.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete(PatientRecord patient) async {
    if (_busy || _deleting) {
      return;
    }
    _deleting = true;
    try {
      final ok = await showAppDeleteDialog(
        context: context,
        title: 'Delete Patient?',
        message:
            'Are you sure you want to delete ${patient.name}? This action will remove the patient from the active patient list. Associated treatment records will be kept.',
        confirmLabel: 'Delete Patient',
        onConfirm: () => ref.read(financeRepositoryProvider).deletePatient(patient),
      );
      if (!mounted || !ok) {
        return;
      }
      setState(() {
        _patients = [for (final item in _patients) if (item.id != patient.id) item];
        _message = null;
      });
      ref.read(financeEpochProvider.notifier).state++;
      showAppSnack(context, 'Patient deleted successfully.');
    } finally {
      _deleting = false;
    }
  }

  Widget _desktopTable(List<PatientRecord> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppLayout.horizontalPadding(context),
            8,
            AppLayout.horizontalPadding(context),
            24,
          ),
          child: Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: math.max(720, constraints.maxWidth - AppLayout.horizontalPadding(context) * 2)),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(AppColors.primarySoft),
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('Patient')),
                    DataColumn(label: Text('Phone')),
                    DataColumn(label: Text('Registered')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (var index = 0; index < items.length; index++)
                      DataRow(
                        cells: [
                          DataCell(Text('${index + 1}')),
                          DataCell(
                            SizedBox(
                              width: 240,
                              child: _patientName(items[index]),
                            ),
                            onTap: _busy ? null : () => _openRecord(items[index]),
                          ),
                          DataCell(Text(items[index].phone ?? '—')),
                          DataCell(Text(items[index].createdAt == null ? '—' : formatDisplayDate(items[index].createdAt))),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Open',
                                  onPressed: _busy ? null : () => _openRecord(items[index]),
                                  icon: const Icon(Icons.folder_open_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Edit',
                                  onPressed: _busy ? null : () => _savePatient(existing: items[index]),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: _busy ? null : () => _delete(items[index]),
                                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _mobileList(List<PatientRecord> items) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppLayout.horizontalPadding(context),
        8,
        AppLayout.horizontalPadding(context),
        24,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return AppReveal(
          index: index,
          child: Card(
            child: ListTile(
              onTap: _busy ? null : () => _openRecord(item),
              leading: CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                foregroundColor: AppColors.primary,
                child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              title: _patientName(item, maxLines: 1),
              subtitle: Text(
                [
                  if (item.phone != null) item.phone,
                  if (item.createdAt != null) formatDisplayDate(item.createdAt),
                ].join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Open',
                    onPressed: _busy ? null : () => _openRecord(item),
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: _busy ? null : () => _savePatient(existing: item),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: _busy ? null : () => _delete(item),
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Scaffold(
      appBar: buildAppBar(
        context: context,
        title: 'Patients',
        fallback: '/clinic',
        actions: [
          IconButton(
            tooltip: 'Add patient',
            onPressed: _busy ? null : () => _savePatient(),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppLayout.maxContent(context)),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(AppLayout.horizontalPadding(context), 8, AppLayout.horizontalPadding(context), 8),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Search patients',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                  onChanged: (_) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 160), () {
                      if (mounted) {
                        setState(() {});
                      }
                    });
                  },
                ),
              ),
              if (_message != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(AppLayout.horizontalPadding(context), 0, AppLayout.horizontalPadding(context), 8),
                  child: ErrorBanner(message: _message!),
                ),
              if (_busy || _syncing)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: AppStateSwitch(
                  child: _loading && _patients.isEmpty
                      ? const Center(key: ValueKey('patients-loading'), child: SkeletonCards())
                      : _patients.isEmpty && _loadError != null
                          ? Center(
                              key: const ValueKey('patients-error'),
                              child: EmptyState(
                                message: _loadError!,
                                title: 'Unable to load patients',
                                icon: Icons.people_outline_rounded,
                                actionLabel: 'Retry',
                                onAction: _load,
                              ),
                            )
                          : items.isEmpty
                              ? Center(
                                  key: const ValueKey('patients-empty'),
                                  child: EmptyState(
                                    message: _search.text.trim().isEmpty
                                        ? 'Add a patient to keep treatment records attached to the right name.'
                                        : 'No patient matches this search.',
                                    title: 'No patients',
                                    icon: Icons.people_outline_rounded,
                                    actionLabel: 'Add patient',
                                    onAction: _busy ? null : () => _savePatient(),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: AppLayout.isDesktop(context) ? _desktopTable(items) : _mobileList(items),
                                ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientFormDialog extends StatefulWidget {
  const _PatientFormDialog({this.existing, this.patients = const []});

  final PatientRecord? existing;
  final List<PatientRecord> patients;

  @override
  State<_PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends State<_PatientFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _phone = TextEditingController(text: widget.existing?.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }
    Navigator.pop(context, (name: _name.text.trim(), phone: _phone.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final inset = size.width < 360 ? 16.0 : 24.0;
    final adding = widget.existing == null;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: inset, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.purpleSoft, borderRadius: BorderRadius.circular(AppRadii.md)),
            child: Icon(
              adding ? Icons.person_add_alt_1_rounded : Icons.person_outline_rounded,
              color: AppColors.purple,
            ),
          ),
          const SizedBox(height: 14),
          Text(adding ? 'Add patient' : 'Edit patient', maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      content: SizedBox(
        width: AppLayout.dialogWidth(context),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Patient name'),
                validator: (value) {
                  if (value == null || value.trim().length < 2) {
                    return 'Enter the patient name.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: pakistaniMobileInputFormatters,
                maxLength: 11,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '03XXXXXXXXX',
                  counterText: '',
                ),
                validator: (value) {
                  return validateOptionalPakistaniMobile(value) ??
                      duplicatePatientPhoneWarning(
                        patients: widget.patients,
                        phone: value,
                        excludeId: widget.existing?.id,
                      );
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
