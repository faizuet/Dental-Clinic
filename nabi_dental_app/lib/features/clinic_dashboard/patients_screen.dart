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
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/page_kit.dart';

enum _PatientFilter { all, active, inactive }

enum _RegisteredRange { allTime, thisMonth, thisYear }

class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen({super.key, this.openAdd = false, this.initialQuery});

  final bool openAdd;
  final String? initialQuery;

  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen> {
  static const _pageSize = 25;
  static const _activeDays = 180;

  final _search = TextEditingController();
  List<PatientRecord> _patients = [];
  Map<String, String> _lastVisit = const {};
  _PatientFilter _filter = _PatientFilter.all;
  _RegisteredRange _range = _RegisteredRange.allTime;
  int _page = 0;
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
    _search.text = widget.initialQuery ?? '';
    _load();
    if (widget.openAdd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _savePatient();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool _isActive(PatientRecord patient) {
    final last = parseFlexibleDate(_lastVisit[patient.id]);
    if (last == null) {
      return false;
    }
    return DateTime.now().difference(last).inDays <= _activeDays;
  }

  bool _registeredIn(PatientRecord patient, _RegisteredRange range) {
    if (range == _RegisteredRange.allTime) {
      return true;
    }
    final created = DateTime.tryParse(patient.createdAt ?? '')?.toLocal();
    if (created == null) {
      return false;
    }
    final now = DateTime.now();
    if (range == _RegisteredRange.thisYear) {
      return created.year == now.year;
    }
    return created.year == now.year && created.month == now.month;
  }

  List<PatientRecord> get _visible {
    final needle = _search.text.trim().toLowerCase();
    return _patients.where((item) {
      if (needle.isNotEmpty &&
          !item.name.toLowerCase().contains(needle) &&
          !(item.phone ?? '').toLowerCase().contains(needle)) {
        return false;
      }
      if (_filter == _PatientFilter.active && !_isActive(item)) {
        return false;
      }
      if (_filter == _PatientFilter.inactive && _isActive(item)) {
        return false;
      }
      return _registeredIn(item, _range);
    }).toList();
  }

  Future<Map<String, String>> _visits(FinanceRepository repo) async {
    final latest = <String, String>{};
    final List<MoneyEntry> visits;
    try {
      visits = await repo.incomeHistory();
    } catch (_) {
      return latest;
    }
    for (final visit in visits) {
      final id = visit.patientId;
      if (id == null || id.isEmpty) {
        continue;
      }
      final current = latest[id];
      if (current == null || visit.date.compareTo(current) > 0) {
        latest[id] = visit.date;
      }
    }
    return latest;
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
      final visits = await _visits(repo);
      if (mounted) {
        setState(() {
          _patients = local;
          _lastVisit = visits;
          _loading = false;
          _syncing = true;
          _loadError = null;
        });
      }
      await repo.refresh(force: force);
      final items = await repo.patients();
      final latest = await _visits(repo);
      if (mounted) {
        setState(() {
          _patients = items;
          _lastVisit = latest;
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
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
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

  Widget _status(PatientRecord patient) {
    final active = _isActive(patient);
    return Tooltip(
      message: active ? 'Visited in the last 6 months' : 'No visit in the last 6 months',
      child: active
          ? const StatusPill(label: 'Active')
          : const StatusPill(label: 'Inactive', color: AppColors.muted, soft: AppColors.background),
    );
  }

  List<Widget> _actions(PatientRecord patient) {
    return [
      RowAction(icon: Icons.visibility_rounded, tooltip: 'Open', onPressed: _busy ? null : () => _openRecord(patient)),
      RowAction(icon: Icons.edit_rounded, tooltip: 'Edit', onPressed: _busy ? null : () => _savePatient(existing: patient)),
      RowAction.danger(icon: Icons.delete_outline_rounded, tooltip: 'Delete', onPressed: _busy ? null : () => _delete(patient)),
    ];
  }

  Widget _desktopTable(List<PatientRecord> items, int offset) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: math.max(760, constraints.maxWidth)),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('Patient Name')),
                DataColumn(label: Text('Phone')),
                DataColumn(label: Text('Registered On')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Actions')),
              ],
              rows: [
                for (var index = 0; index < items.length; index++)
                  DataRow(
                    cells: [
                      DataCell(Text('${offset + index + 1}')),
                      DataCell(
                        SizedBox(
                          width: 240,
                          child: Row(
                            children: [
                              InitialsAvatar(name: items[index].name),
                              const SizedBox(width: 12),
                              Expanded(child: _patientName(items[index], maxLines: 1)),
                            ],
                          ),
                        ),
                        onTap: _busy ? null : () => _openRecord(items[index]),
                      ),
                      DataCell(IconText(icon: Icons.call_rounded, text: items[index].phone ?? '—')),
                      DataCell(
                        IconText(
                          icon: Icons.event_note_rounded,
                          text: items[index].createdAt == null ? '—' : formatDisplayDate(items[index].createdAt),
                        ),
                      ),
                      DataCell(_status(items[index])),
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: _actions(items[index]))),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _mobileList(List<PatientRecord> items) {
    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          ListTile(
            onTap: _busy ? null : () => _openRecord(items[index]),
            leading: InitialsAvatar(name: items[index].name, size: 40),
            title: _patientName(items[index], maxLines: 1),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (items[index].phone != null) Text(items[index].phone!),
                  _status(items[index]),
                ],
              ),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: _actions(items[index])),
          ),
        ],
      ],
    );
  }

  Widget _stats() {
    final now = DateTime.now();
    final thisMonth = _patients.where((item) => _registeredIn(item, _RegisteredRange.thisMonth)).length;
    final treatedThisMonth = {
      for (final entry in _lastVisit.entries)
        if (parseFlexibleDate(entry.value)?.year == now.year && parseFlexibleDate(entry.value)?.month == now.month) entry.key,
    }.where((id) => _patients.any((item) => item.id == id)).length;
    final active = _patients.where(_isActive).length;
    return StatStrip(
      items: [
        MiniStat(
          label: 'Total Patients',
          value: '${_patients.length}',
          icon: Icons.groups_rounded,
          color: AppColors.primary,
          soft: AppColors.primarySoft,
        ),
        MiniStat(
          label: 'New This Month',
          value: '$thisMonth',
          icon: Icons.person_add_alt_1_rounded,
          color: AppColors.success,
          soft: AppColors.mintSoft,
        ),
        MiniStat(
          label: 'Treated This Month',
          value: '$treatedThisMonth',
          icon: Icons.medical_services_rounded,
          color: AppColors.violet,
          soft: AppColors.violetSoft,
        ),
        MiniStat(
          label: 'Active Patients',
          value: '$active',
          icon: Icons.verified_rounded,
          color: AppColors.orange,
          soft: AppColors.warningSoft,
          caption: '6 months',
        ),
      ],
    );
  }

  Widget _rangeMenu() {
    const labels = {
      _RegisteredRange.allTime: 'All Time',
      _RegisteredRange.thisMonth: 'This Month',
      _RegisteredRange.thisYear: 'This Year',
    };
    return PopupMenuButton<_RegisteredRange>(
      tooltip: 'Registered date',
      initialValue: _range,
      onSelected: (value) => setState(() {
        _range = value;
        _page = 0;
      }),
      itemBuilder: (context) => [
        for (final entry in labels.entries) PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      child: IgnorePointer(
        child: FilterButton(
          label: labels[_range]!,
          icon: Icons.calendar_month_rounded,
          trailingIcon: Icons.expand_more_rounded,
          onPressed: () {},
        ),
      ),
    );
  }

  Widget _tableSection(List<PatientRecord> items) {
    final pages = math.max(1, (items.length / _pageSize).ceil());
    final page = math.min(_page, pages - 1);
    final start = page * _pageSize;
    final slice = items.skip(start).take(_pageSize).toList();
    return TablePanel(
      header: FilterBar(
        filters: [
          SegmentPills<_PatientFilter>(
            value: _filter,
            options: const [
              (value: _PatientFilter.all, label: 'All Patients'),
              (value: _PatientFilter.active, label: 'Active'),
              (value: _PatientFilter.inactive, label: 'Inactive'),
            ],
            onChanged: (value) => setState(() {
              _filter = value;
              _page = 0;
            }),
          ),
          _rangeMenu(),
          FilterSearch(
            controller: _search,
            hint: 'Search by name or phone...',
            onChanged: (_) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 160), () {
                if (mounted) {
                  setState(() => _page = 0);
                }
              });
            },
          ),
        ],
        trailing: [
          FilterButton(
            label: 'Refresh',
            icon: Icons.refresh_rounded,
            onPressed: _syncing ? null : () => _load(force: true),
          ),
        ],
      ),
      footer: TableFooterText(
        shown: start + slice.length,
        total: items.length,
        noun: items.length == 1 ? 'patient' : 'patients',
        trailing: pages > 1
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RowAction(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Previous page',
                    onPressed: page == 0 ? null : () => setState(() => _page = page - 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('${page + 1} / $pages', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  RowAction(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'Next page',
                    onPressed: page >= pages - 1 ? null : () => setState(() => _page = page + 1),
                  ),
                ],
              )
            : null,
      ),
      child: AppStateSwitch(
        child: _loading && _patients.isEmpty
            ? const SkeletonTable(key: ValueKey('patients-loading'))
            : _patients.isEmpty && _loadError != null
                ? EmptyState(
                    key: const ValueKey('patients-error'),
                    message: _loadError!,
                    title: 'Unable to load patients',
                    icon: Icons.people_outline_rounded,
                    actionLabel: 'Retry',
                    onAction: _load,
                  )
                : items.isEmpty
                    ? EmptyState(
                        key: const ValueKey('patients-empty'),
                        message: _patients.isEmpty
                            ? 'Add a patient to keep treatment records attached to the right name.'
                            : 'No patient matches these filters.',
                        title: 'No patients',
                        icon: Icons.people_outline_rounded,
                        actionLabel: _patients.isEmpty ? 'Add patient' : null,
                        onAction: _busy || _patients.isNotEmpty ? null : () => _savePatient(),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('patients-table'),
                        child: AppLayout.isDesktop(context) ? _desktopTable(slice, start) : _mobileList(slice),
                      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Scaffold(
      appBar: buildAppBar(context: context, title: 'Patients', fallback: '/clinic'),
      body: PageScaffoldBody(
        onRefresh: () => _load(force: true),
        children: [
          PageHeader(
            icon: Icons.groups_rounded,
            title: 'Patients',
            subtitle: 'Manage your clinic patients efficiently',
            actions: [
              Tooltip(
                message: 'Add patient',
                child: PrimaryAction(
                  label: 'Add New Patient',
                  icon: Icons.add_rounded,
                  onPressed: _busy ? null : () => _savePatient(),
                ),
              ),
            ],
          ),
          _stats(),
          if (_message != null) ...[
            ErrorBanner(message: _message!),
            const SizedBox(height: 12),
          ],
          if (_busy || _syncing) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 8),
          ],
          _tableSection(items),
        ],
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
      title: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadii.md)),
            child: Icon(
              adding ? Icons.person_add_alt_1_rounded : Icons.person_outline_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(adding ? 'Add patient' : 'Edit patient', maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  adding ? 'Register a new patient for this clinic' : 'Update the patient name or phone',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
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
                decoration: const InputDecoration(labelText: 'Patient name', prefixIcon: Icon(Icons.person_outline_rounded)),
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
                  prefixIcon: Icon(Icons.call_outlined),
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
