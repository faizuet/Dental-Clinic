import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/summary_card.dart';

class LabChargeFormScreen extends ConsumerStatefulWidget {
  const LabChargeFormScreen({super.key, this.chargeId, this.patientId, this.transactionId});

  final String? chargeId;
  final String? patientId;
  final String? transactionId;

  @override
  ConsumerState<LabChargeFormScreen> createState() => _LabChargeFormScreenState();
}

class _LabChargeFormScreenState extends ConsumerState<LabChargeFormScreen> {
  static const _backTo = '/clinic/lab-charges';

  final _amount = TextEditingController();
  final _labName = TextEditingController();
  final _notes = TextEditingController();
  final _patientSearch = TextEditingController();
  DateTime _date = DateTime.now();
  LabCharge? _charge;
  List<PatientRecord> _patients = [];
  PatientRecord? _patient;
  List<MoneyEntry> _visits = [];
  String? _visitId;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  String? _error;

  bool get _editing => widget.chargeId != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _amount.dispose();
    _labName.dispose();
    _notes.dispose();
    _patientSearch.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final repo = ref.read(financeRepositoryProvider);
    try {
      final patients = await repo.patients();
      var patientId = widget.patientId;
      var visitId = widget.transactionId;
      if (_editing) {
        final charge = await repo.labChargeById(widget.chargeId!);
        if (charge == null) {
          throw StateError('This lab charge was deleted or has not synced to this device yet.');
        }
        _charge = charge;
        _date = DateTime.tryParse(charge.date) ?? DateTime.now();
        _amount.text = charge.amount;
        _labName.text = charge.labName ?? '';
        _notes.text = charge.notes ?? '';
        patientId = charge.patientId;
        visitId = charge.transactionId;
      } else if (visitId != null && patientId == null) {
        patientId = (await repo.treatmentById(visitId))?.patientId;
      }
      PatientRecord? patient;
      for (final item in patients) {
        if (item.id == patientId) {
          patient = item;
        }
      }
      final visits = patient == null ? <MoneyEntry>[] : await repo.patientTreatments(patient.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _patients = patients;
        _patient = patient;
        _visits = visits;
        _visitId = visits.any((item) => item.id == visitId) ? visitId : null;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is StateError ? error.message : friendlyError(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectPatient(PatientRecord? patient) async {
    setState(() {
      _patient = patient;
      _visits = [];
      _visitId = null;
      _dirty = true;
      _patientSearch.clear();
    });
    if (patient == null) {
      return;
    }
    final visits = await ref.read(financeRepositoryProvider).patientTreatments(patient.id);
    if (mounted && _patient?.id == patient.id) {
      setState(() => _visits = visits);
    }
  }

  String? _text(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    if (!isValidMoney(_amount.text)) {
      setState(() => _error = 'Enter an amount greater than 0 with up to two decimals.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(financeRepositoryProvider);
    final date = DateFormat('yyyy-MM-dd').format(_date);
    final amount = moneyFromDouble(moneyToDouble(_amount.text));
    try {
      final message = _charge == null
          ? await repo.saveLabCharge(
              date: date,
              amount: amount,
              patientId: _patient?.id,
              transactionId: _visitId,
              labName: _text(_labName),
              notes: _text(_notes),
            )
          : await repo.updateLabCharge(
              _charge!,
              date: date,
              amount: amount,
              patientId: _patient?.id,
              transactionId: _visitId,
              labName: _text(_labName),
              notes: _text(_notes),
            );
      ref.read(financeEpochProvider.notifier).state++;
      if (mounted) {
        setState(() => _dirty = false);
        showAppSnack(context, message);
        appPop(context, fallback: _backTo);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _visitText(MoneyEntry visit) {
    final treatment = visit.subTreatment?.trim().isNotEmpty == true ? visit.subTreatment! : visit.catalogName;
    return [
      if (visit.serialNo != null) '#${visit.serialNo}',
      treatment,
      formatDisplayDate(visit.date),
    ].join(' · ');
  }

  Widget _patientCard() {
    final needle = _patientSearch.text.trim().toLowerCase();
    final matches = needle.isEmpty
        ? _patients
        : _patients
            .where((item) => item.name.toLowerCase().contains(needle) || (item.phone ?? '').contains(needle))
            .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Patient and visit (optional)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_patient != null)
              Chip(
                label: Text(
                  _patient!.phone == null || _patient!.phone!.isEmpty
                      ? _patient!.name
                      : '${_patient!.name}  ·  ${_patient!.phone}',
                ),
                onDeleted: () => _selectPatient(null),
              )
            else ...[
              const Text('Link this lab charge to a patient if it is for their work.'),
              const SizedBox(height: 8),
              TextField(
                controller: _patientSearch,
                decoration: const InputDecoration(labelText: 'Search patients', prefixIcon: Icon(Icons.search_rounded)),
                onChanged: (_) => setState(() {}),
              ),
              if (needle.isNotEmpty) ...[
                const SizedBox(height: 8),
                if (matches.isEmpty)
                  Text(
                    'No patient matches "${_patientSearch.text.trim()}".',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final item = matches[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: AppColors.violetSoft,
                            foregroundColor: AppColors.violet,
                            child: Text('${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: item.phone == null ? null : Text(item.phone!),
                          onTap: () => _selectPatient(item),
                        );
                      },
                    ),
                  ),
              ],
            ],
            if (_patient != null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey('lab-visit-${_patient!.id}-${_visits.length}'),
                initialValue: _visitId,
                isExpanded: true,
                menuMaxHeight: 420,
                decoration: const InputDecoration(labelText: 'Treatment visit', prefixIcon: Icon(Icons.medical_services_outlined)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Not linked to a visit')),
                  for (final visit in _visits)
                    DropdownMenuItem<String?>(
                      value: visit.id,
                      child: Text(_visitText(visit), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _visitId = value;
                  _dirty = true;
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _editing ? 'Edit lab charge' : 'Lab charge';
    return AppDiscardScope(
      dirty: _dirty,
      fallback: _backTo,
      child: Scaffold(
        appBar: buildAppBar(context: context, title: title, fallback: _backTo),
        body: AppPageBody(
          padding: AppLayout.pagePadding(context, top: 8, bottom: 8),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
                  children: [
                    DatePickerTile(
                      label: 'Date',
                      value: formatDisplayDate(_date),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null) {
                          setState(() {
                            _date = picked;
                            _dirty = true;
                          });
                        }
                      },
                    ),
                    if (_error != null) ErrorBanner(message: _error!),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            TextField(
                              controller: _amount,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(labelText: 'Amount', prefixIcon: Icon(Icons.payments_outlined)),
                              onChanged: (_) => setState(() => _dirty = true),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _labName,
                              maxLength: 150,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Lab name (optional)',
                                prefixIcon: Icon(Icons.science_outlined),
                                counterText: '',
                              ),
                              onChanged: (_) => _dirty = true,
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _notes,
                              maxLength: 1000,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Notes (optional)',
                                prefixIcon: Icon(Icons.notes_rounded),
                                counterText: '',
                              ),
                              onChanged: (_) => _dirty = true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _patientCard(),
                    const SizedBox(height: 12),
                    Stretch(
                      child: AppBusyButton(
                        busy: _busy,
                        busyLabel: 'Saving…',
                        onPressed: _busy || !isValidMoney(_amount.text) || (_editing && _charge == null) ? null : _save,
                        label: _editing ? 'Save changes' : 'Save',
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
