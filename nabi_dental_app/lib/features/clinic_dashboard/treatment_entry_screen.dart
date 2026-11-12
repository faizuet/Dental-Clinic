import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/app_colors.dart';
import '../../core/dental/tooth_catalog.dart';
import '../../core/errors/app_exception.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/summary_card.dart';
import 'treatment_line_card.dart';

class TreatmentEntryScreen extends ConsumerStatefulWidget {
  const TreatmentEntryScreen({super.key, this.visitId});

  final String? visitId;

  @override
  ConsumerState<TreatmentEntryScreen> createState() => _TreatmentEntryScreenState();
}

class _TreatmentEntryScreenState extends ConsumerState<TreatmentEntryScreen> {
  static const _uuid = Uuid();

  DateTime _date = DateTime.now();
  List<CatalogItem> _treatments = [];
  List<PatientRecord> _patients = [];
  PatientRecord? _patient;
  final _patientSearch = TextEditingController();
  final _lineKeys = <String, GlobalKey<TreatmentLineCardState>>{};
  List<TreatmentLineSeed> _lines = [TreatmentLineSeed(id: _uuid.v4())];
  MoneyEntry? _visit;
  bool _ready = false;
  bool _changed = false;
  bool _busy = false;
  bool _patientBusy = false;
  String? _error;
  String _totalAmount = '0.00';

  bool get _editing => widget.visitId != null && widget.visitId!.isNotEmpty;

  GlobalKey<TreatmentLineCardState> _keyFor(String id) {
    return _lineKeys.putIfAbsent(id, GlobalKey<TreatmentLineCardState>.new);
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void setState(VoidCallback fn) {
    final wasReady = _ready;
    super.setState(() {
      fn();
      if (wasReady && _editing) {
        _changed = true;
      }
    });
  }

  Future<void> _bootstrap() async {
    try {
      final repo = ref.read(financeRepositoryProvider);
      final treatments = await repo.treatments();
      final patients = await repo.patients();
      MoneyEntry? visit;
      var lines = [TreatmentLineSeed(id: _uuid.v4())];
      if (_editing) {
        visit = await repo.treatmentById(widget.visitId!);
        if (visit != null) {
          lines = await _seedsFromVisit(repo, visit, treatments, loadBytes: false);
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _treatments = treatments;
        _patients = patients;
        _lines = lines;
        _visit = visit;
        if (visit != null) {
          _date = DateTime.tryParse(visit.date) ?? DateTime.now();
          if (visit.patientId != null) {
            final matches = _patients.where((item) => item.id == visit!.patientId);
            _patient = matches.isEmpty
                ? PatientRecord(id: visit.patientId!, name: visit.displayPatientName, phone: visit.patientPhone)
                : matches.first;
            if (_patients.every((item) => item.id != _patient!.id)) {
              _patients = [_patient!, ..._patients];
            }
          }
        } else if (_editing) {
          _error = 'This treatment record is not available.';
        }
        _ready = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshTotal();
        }
      });
      if (visit != null) {
        final withImages = await _seedsFromVisit(repo, visit, treatments);
        if (mounted) {
          setState(() => _lines = withImages);
        }
      }
      unawaited(_refreshCatalogs());
    } catch (error) {
      if (mounted) {
        setState(() {
          _ready = true;
          _error = friendlyError(error);
        });
      }
    }
  }

  Future<void> _refreshCatalogs() async {
    final repo = ref.read(financeRepositoryProvider);
    try {
      await repo.refresh();
      final treatments = await repo.treatments();
      final patients = await repo.patients();
      if (!mounted) {
        return;
      }
      setState(() {
        _treatments = treatments;
        _patients = patients;
        if (_patient != null && _patients.every((item) => item.id != _patient!.id)) {
          _patients = [_patient!, ..._patients];
        }
      });
    } catch (_) {}
  }

  Future<List<TreatmentLineSeed>> _seedsFromVisit(
    FinanceRepository repo,
    MoneyEntry visit,
    List<CatalogItem> treatments, {
    bool loadBytes = true,
  }) async {
    final images = <String, TreatmentLineXray>{};
    for (final attachment in visit.attachments) {
      var bytes = Uint8List(0);
      if (loadBytes) {
        try {
          bytes = Uint8List.fromList(await repo.treatmentAttachmentBytes(visit.id, attachment.id));
        } catch (_) {}
      }
      images[attachment.id] = TreatmentLineXray(
        bytes: bytes,
        filename: attachment.originalName ?? 'xray.jpg',
        id: attachment.id,
        label: attachment.label,
      );
    }
    final assigned = <String>{};
    final explicit = explicitVisitItems(visit.details);
    final rawItems = explicit ??
        [
          {
            ...visit.details,
            'treatment_id': visit.catalogId,
            'treatment_name': visit.catalogName,
            'category_name': visit.categoryName,
            'amount': visit.amount,
            'notes': visit.notes,
            'attachment_ids': [for (final item in visit.attachments) item.id],
          },
        ];
    final seeds = <TreatmentLineSeed>[];
    for (final item in rawItems) {
      final lineId = item['id']?.toString() ?? _uuid.v4();
      final treatmentId = item['treatment_id']?.toString() ?? visit.catalogId;
      final treatmentName = item['treatment_name']?.toString() ?? item['sub_treatment']?.toString() ?? visit.catalogName;
      final treatment = findCatalogMatch(
            treatments,
            id: treatmentId,
            name: treatmentName,
          ) ??
          CatalogItem(
            id: treatmentId,
            name: treatmentName,
            categoryName: item['category_name']?.toString() ?? visit.categoryName,
          );
      final attachmentIds = [
        for (final value in item['attachment_ids'] is List ? item['attachment_ids'] as List : const []) value.toString(),
      ];
      final xrays = [
        for (final id in attachmentIds)
          if (images.containsKey(id)) images[id]!,
      ];
      assigned.addAll(attachmentIds);
      seeds.add(
        TreatmentLineSeed(
          id: lineId,
          treatment: treatment,
          details: item,
          amount: item['amount']?.toString() ?? (rawItems.length == 1 ? visit.amount : ''),
          notes: item['notes']?.toString() ?? (rawItems.length == 1 ? visit.notes : null),
          xrays: xrays,
        ),
      );
    }
    if (seeds.isEmpty) {
      seeds.add(TreatmentLineSeed(id: _uuid.v4()));
    }
    final leftover = [
      for (final attachment in visit.attachments)
        if (!assigned.contains(attachment.id) && images.containsKey(attachment.id)) images[attachment.id]!,
    ];
    if (leftover.isNotEmpty) {
      final first = seeds.first;
      seeds[0] = TreatmentLineSeed(
        id: first.id,
        treatment: first.treatment,
        details: first.details,
        amount: first.amount,
        notes: first.notes,
        xrays: [...first.xrays, ...leftover],
      );
    }
    return seeds;
  }

  @override
  void dispose() {
    _patientSearch.dispose();
    super.dispose();
  }

  bool get _hasPatientInput => _patient != null || _patientSearch.text.trim().length >= 2;

  bool get _dirty =>
      _editing
          ? _changed
          : _patient != null || _patientSearch.text.trim().isNotEmpty || _lines.length > 1;

  List<TreatmentLineSnapshot> _snapshots() {
    return [
      for (final line in _lines)
        if (_keyFor(line.id).currentState != null) _keyFor(line.id).currentState!.snapshot(),
    ];
  }

  void _refreshTotal() {
    final snapshots = _snapshots();
    final total = snapshots.fold<double>(0, (sum, item) => sum + (isValidMoney(item.amount) ? moneyToDouble(item.amount) : 0));
    setState(() => _totalAmount = moneyFromDouble(total));
  }

  void _addLine() {
    setState(() => _lines = [..._lines, TreatmentLineSeed(id: _uuid.v4())]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshTotal();
      }
    });
  }

  void _removeLine(String id) {
    if (_lines.length <= 1) {
      return;
    }
    setState(() {
      _lines = [for (final line in _lines) if (line.id != id) line];
      _lineKeys.remove(id);
    });
    _refreshTotal();
  }

  Future<void> _addPatient({String? presetName}) async {
    final result = await showDialog<({String name, String phone})>(
      context: context,
      builder: (context) => _AddPatientDialog(initialName: presetName),
    );
    final trimmed = result?.name ?? '';
    final phoneValue = result?.phone ?? '';
    if (result == null || trimmed.length < 2) {
      return;
    }
    await _registerPatient(name: trimmed, phone: phoneValue.isEmpty ? null : phoneValue);
  }

  Future<PatientRecord?> _registerPatient({required String name, String? phone}) async {
    setState(() {
      _patientBusy = true;
      _error = null;
    });
    try {
      final patient = await ref.read(financeRepositoryProvider).savePatient(
            name: name,
            phone: phone,
          );
      if (mounted) {
        setState(() {
          _patients = [
            patient,
            ..._patients.where((item) => item.id != patient.id),
          ];
          _patient = patient;
          _patientSearch.clear();
          _patientBusy = false;
        });
      }
      return patient;
    } catch (error) {
      if (mounted) {
        setState(() {
          _patientBusy = false;
          _error = friendlyError(error);
        });
      }
      return null;
    }
  }

  Future<PatientRecord?> _ensurePatient() async {
    if (_patient != null) {
      return _patient;
    }
    final typed = _patientSearch.text.trim();
    if (typed.length < 2) {
      setState(() => _error = 'Select or add a patient before saving the treatment.');
      return null;
    }
    for (final item in _patients) {
      if (item.name.toLowerCase() == typed.toLowerCase()) {
        setState(() {
          _patient = item;
          _patientSearch.clear();
        });
        return item;
      }
    }
    return _registerPatient(name: typed);
  }

  Future<void> _save() async {
    final snapshots = _snapshots();
    if (snapshots.length != _lines.length) {
      setState(() => _error = 'Wait for every treatment to finish loading, then save again.');
      return;
    }
    for (var index = 0; index < snapshots.length; index++) {
      final error = snapshots[index].clinicalError;
      if (error != null) {
        setState(() => _error = 'Treatment ${index + 1}: $error');
        return;
      }
    }
    final seen = <String>{};
    for (var index = 0; index < snapshots.length; index++) {
      final item = snapshots[index];
      final teeth = item.details['tooth_numbers'] is List
          ? (item.details['tooth_numbers'] as List).join(',')
          : item.details['tooth_number']?.toString() ?? '';
      final key = '${item.treatment?.id}|$teeth';
      if (!seen.add(key)) {
        setState(() => _error = 'Treatment ${index + 1} is already on this record. Change the treatment or tooth.');
        return;
      }
    }
    final imageCount = snapshots.fold<int>(0, (sum, item) => sum + item.xrays.length);
    if (imageCount > 24) {
      setState(() => _error = 'A treatment record can have at most 24 X-ray images.');
      return;
    }
    PatientRecord? patient = _patient;
    if (_hasPatientInput) {
      patient = await _ensurePatient();
      if (patient == null) {
        return;
      }
    } else if (!_editing || _visit?.patientId != null) {
      setState(() => _error = 'Select or add a patient before saving the treatment.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final total = snapshots.fold<double>(0, (sum, item) => sum + moneyToDouble(item.amount));
      final items = [for (final item in snapshots) item.details];
      final details = {
        'kind': 'visit',
        'items': items,
      };
      final names = [
        for (final item in snapshots)
          if (item.treatment?.name != null) item.treatment!.name,
      ];
      final uniqueNames = <String>[];
      for (final name in names) {
        if (!uniqueNames.contains(name)) {
          uniqueNames.add(name);
        }
      }
      final xrays = [
        for (final item in snapshots)
          for (final xray in item.xrays)
            if (!xray.isSaved)
              (bytes: xray.bytes, filename: xray.filename, label: xray.label, lineId: item.id),
      ];
      final removed = [
        for (final item in snapshots) ...item.removedAttachmentIds,
      ];
      final notes = snapshots.map((item) => item.notes).whereType<String>().join(' | ');
      final message = _editing
          ? await ref.read(financeRepositoryProvider).updateTreatmentVisit(
                entry: _visit!,
                date: DateFormat('yyyy-MM-dd').format(_date),
                treatmentId: snapshots.first.treatment!.id,
                amount: moneyFromDouble(total),
                patientId: patient?.id,
                patientName: patient?.name,
                patientPhone: patient?.phone,
                subTreatment: uniqueNames.join(', '),
                details: details,
                notes: notes.isEmpty ? null : notes,
                removeAttachmentIds: removed,
                xrays: xrays,
              )
          : await ref.read(financeRepositoryProvider).saveTreatmentVisit(
                date: DateFormat('yyyy-MM-dd').format(_date),
                treatmentId: snapshots.first.treatment!.id,
                amount: moneyFromDouble(total),
                patientId: patient?.id,
                patientName: patient?.name,
                patientPhone: patient?.phone,
                subTreatment: uniqueNames.join(', '),
                details: details,
                notes: notes.isEmpty ? null : notes,
                xrays: xrays,
              );
      if (mounted) {
        showAppSnack(context, message);
        appPop(context, fallback: _editing ? '/clinic/income/history' : '/clinic');
      }
    } catch (error) {
      if (error is AppException && error.code == 'IMAGE_UPLOAD_PARTIAL') {
        setState(() => _error = error.message);
        if (mounted) {
          showAppSnack(context, error.message, error: true);
          appPop(context, fallback: _editing ? '/clinic/income/history' : '/clinic');
        }
      } else {
        setState(() => _error = friendlyError(error, feature: 'upload'));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDiscardScope(
      dirty: _dirty,
      fallback: _editing ? '/clinic/income/history' : '/clinic',
      child: Scaffold(
        appBar: buildAppBar(
          context: context,
          title: _editing ? 'Edit treatment' : 'New treatment',
          fallback: _editing ? '/clinic/income/history' : '/clinic',
        ),
        body: !_ready
            ? const Center(child: SkeletonCards(count: 2))
            : AppPageBody(
                padding: AppLayout.pagePadding(context, top: 8, bottom: 8),
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
                  children: [
                    AppSplit(
                      primary: _patientCard(),
                      secondary: DatePickerTile(
                        label: 'Treatment date',
                        value: formatDisplayDate(_date),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 30)),
                          );
                          if (picked != null) {
                            setState(() => _date = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Treatments', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Add every treatment from this visit. Details stay with that tooth and treatment.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),
                    for (var index = 0; index < _lines.length; index++) ...[
                      TreatmentLineCard(
                        key: _keyFor(_lines[index].id),
                        seed: _lines[index],
                        index: index,
                        treatments: _treatments,
                        canRemove: _lines.length > 1,
                        onRemove: () => _removeLine(_lines[index].id),
                        onChanged: _refreshTotal,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _addLine,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add another treatment'),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 16),
                    TotalBar(label: 'Total fee', value: formatMoney(_totalAmount)),
                    const SizedBox(height: 12),
                    Stretch(
                      child: AppBusyButton(
                        busy: _busy,
                        busyLabel: 'Saving…',
                        onPressed: _busy || (_editing && _visit == null) ? null : _save,
                        label: _editing ? 'Save changes' : 'Save treatment',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
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
            Text('Patient', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_patient != null)
              Chip(
                label: Text(
                  _patient!.phone == null || _patient!.phone!.isEmpty
                      ? _patient!.name
                      : '${_patient!.name}  ·  ${_patient!.phone}',
                ),
                onDeleted: () => setState(() => _patient = null),
              )
            else
              const Text('Select a patient or add a new one. Every treatment in this record is saved under that name.'),
            const SizedBox(height: 8),
            TextField(
              controller: _patientSearch,
              enabled: _patient == null,
              decoration: const InputDecoration(labelText: 'Search patients', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (_) => setState(() {}),
            ),
            if (_patient == null) ...[
              const SizedBox(height: 8),
              if (_patientBusy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (matches.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    needle.length >= 2
                        ? 'No patient named "${_patientSearch.text.trim()}". Add them before saving.'
                        : 'No patients yet. Add a patient to continue.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
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
                          backgroundColor: AppColors.primarySoft,
                          foregroundColor: AppColors.primary,
                          child: Text('${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: item.phone == null ? null : Text(item.phone!),
                        onTap: () => setState(() {
                          _patient = item;
                          _patientSearch.clear();
                        }),
                      );
                    },
                  ),
                ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _patientBusy ? null : () => _addPatient(presetName: _patientSearch.text.trim()),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(_patientBusy ? 'Saving patient…' : 'Add patient'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPatientDialog extends StatefulWidget {
  const _AddPatientDialog({this.initialName});

  final String? initialName;

  @override
  State<_AddPatientDialog> createState() => _AddPatientDialogState();
}

class _AddPatientDialogState extends State<_AddPatientDialog> {
  late final TextEditingController _name;
  final _phone = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
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
            child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.purple),
          ),
          const SizedBox(height: 14),
          const Text('Add patient', maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      content: SizedBox(
        width: AppLayout.dialogWidth(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Patient name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  autofocus: true,
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
                    prefixIcon: Icon(Icons.phone_outlined),
                    counterText: '',
                  ),
                  validator: validateOptionalPakistaniMobile,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
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
