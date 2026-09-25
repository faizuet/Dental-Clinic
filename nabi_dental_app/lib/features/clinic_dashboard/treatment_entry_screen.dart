import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../core/dental/tooth_catalog.dart';
import '../../core/dental/xray_validation.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/finance/finance_repository.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/summary_card.dart';

class _PendingXray {
  _PendingXray({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
  String label = 'before';
}

class TreatmentEntryScreen extends ConsumerStatefulWidget {
  const TreatmentEntryScreen({super.key});

  @override
  ConsumerState<TreatmentEntryScreen> createState() => _TreatmentEntryScreenState();
}

class _TreatmentEntryScreenState extends ConsumerState<TreatmentEntryScreen> {
  DateTime _date = DateTime.now();
  List<CatalogItem> _treatments = [];
  List<PatientRecord> _patients = [];
  PatientRecord? _patient;
  TreatmentFamily? _family;
  CatalogItem? _treatment;
  String? _tooth;
  final _teeth = <String>[];
  String _material = 'PFM';
  String _arch = 'upper';
  String _scope = 'full mouth';
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _length = TextEditingController();
  final _units = TextEditingController(text: '1');
  final _canals = TextEditingController(text: '3');
  final _teethCount = TextEditingController();
  final _partial = TextEditingController();
  final _otherMaterial = TextEditingController();
  final _patientSearch = TextEditingController();
  final _xrays = <_PendingXray>[];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await ref.read(financeRepositoryProvider).refresh();
    final repo = ref.read(financeRepositoryProvider);
    final treatments = await repo.treatments();
    final patients = await repo.patients();
    if (mounted) {
      setState(() {
        _treatments = treatments;
        _patients = patients;
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    _length.dispose();
    _units.dispose();
    _canals.dispose();
    _teethCount.dispose();
    _partial.dispose();
    _otherMaterial.dispose();
    _patientSearch.dispose();
    super.dispose();
  }

  TreatmentKind get _kind {
    final item = _treatment;
    if (item == null) {
      return TreatmentKind.general;
    }
    return kindOf(item.name, categoryName: item.categoryName);
  }

  List<CatalogItem> get _prostheticItems =>
      _treatments.where((item) => familyOf(item.name, categoryName: item.categoryName) == TreatmentFamily.prosthetic).toList();

  List<CatalogItem> get _perioItems =>
      _treatments.where((item) => familyOf(item.name, categoryName: item.categoryName) == TreatmentFamily.perio).toList();

  List<CatalogItem> get _generalItems =>
      _treatments.where((item) => familyOf(item.name, categoryName: item.categoryName) == TreatmentFamily.general).toList();

  CatalogItem? get _rctItem {
    final matches = _treatments.where((item) => familyOf(item.name, categoryName: item.categoryName) == TreatmentFamily.rct);
    return matches.isEmpty ? null : matches.first;
  }

  bool get _canSave => _treatment != null && isValidMoney(_amount.text);

  bool get _dirty =>
      _patient != null ||
      _treatment != null ||
      _amount.text.trim().isNotEmpty ||
      _notes.text.trim().isNotEmpty ||
      _xrays.isNotEmpty;

  void _selectFamily(TreatmentFamily? family) {
    setState(() {
      _family = family;
      _treatment = switch (family) {
        TreatmentFamily.rct => _rctItem,
        TreatmentFamily.prosthetic => _prostheticItems.isEmpty ? null : _prostheticItems.first,
        TreatmentFamily.perio => _perioItems.isEmpty ? null : _perioItems.first,
        TreatmentFamily.general => null,
        null => null,
      };
      _applyDefaultPrice();
    });
  }

  void _applyDefaultPrice() {
    final price = _treatment?.defaultPrice;
    if (price != null && _amount.text.trim().isEmpty) {
      _amount.text = price;
    }
  }

  Future<void> _addPatient() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showAppDialog<bool>(
      context: context,
      title: 'Add patient',
      icon: Icons.person_add_alt_1_rounded,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Patient name'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
      ],
    );
    final trimmed = name.text.trim();
    final phoneValue = phone.text.trim();
    name.dispose();
    phone.dispose();
    if (ok != true || trimmed.length < 2) {
      return;
    }
    try {
      final patient = await ref.read(financeRepositoryProvider).savePatient(
            name: trimmed,
            phone: phoneValue.isEmpty ? null : phoneValue,
          );
      if (mounted) {
        setState(() {
          _patients = [..._patients, patient]..sort((a, b) => a.name.compareTo(b.name));
          _patient = patient;
          _patientSearch.clear();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyError(error));
      }
    }
  }

  Future<void> _pickXray(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 92);
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      final fileError = validateXrayFile(filename: picked.name, byteLength: bytes.length);
      if (fileError != null) {
        setState(() => _error = fileError);
        return;
      }
      final imageError = await validateXrayImage(bytes);
      if (imageError != null) {
        setState(() => _error = imageError);
        return;
      }
      if (_xrays.length >= 8) {
        setState(() => _error = 'A treatment can have at most 8 X-ray images.');
        return;
      }
      setState(() {
        _error = null;
        _xrays.add(_PendingXray(bytes: bytes, filename: picked.name));
      });
    } catch (error) {
      setState(() => _error = friendlyError(error));
    }
  }

  Map<String, dynamic> _details() {
    final kind = _kind;
    final material = _material == 'Other' ? _otherMaterial.text.trim() : _material;
    return switch (kind) {
      TreatmentKind.rct => {
          'kind': 'rct',
          'tooth_number': _tooth,
          'tooth_name': toothNameFor(_tooth),
          'canals': int.tryParse(_canals.text) ?? 1,
          'length_mm': _length.text.trim(),
        },
      TreatmentKind.crown => {
          'kind': 'crown',
          'tooth_number': _tooth,
          'tooth_name': toothNameFor(_tooth),
          'material': material,
          'units': int.tryParse(_units.text) ?? 1,
        },
      TreatmentKind.bridge => {
          'kind': 'bridge',
          'tooth_numbers': List<String>.from(_teeth),
          'tooth_names': [for (final tooth in _teeth) toothNameFor(tooth)].whereType<String>().toList(),
          'material': material,
          'units': int.tryParse(_units.text) ?? _teeth.length,
        },
      TreatmentKind.removableDenture => {
          'kind': 'removable_denture',
          'arch': _arch,
          'partial_details': _partial.text.trim(),
          'teeth_count': int.tryParse(_teethCount.text),
          'material': material == 'PFM' ? null : material,
        },
      TreatmentKind.fullDenture => {
          'kind': 'full_denture',
          'arch': _arch,
          'denture_type': _arch,
        },
      TreatmentKind.scaling => {
          'kind': 'scaling',
          'scope': _scope,
        },
      TreatmentKind.general => {
          'kind': 'general',
          if (_tooth != null) 'tooth_number': _tooth,
          if (_tooth != null) 'tooth_name': toothNameFor(_tooth),
        },
    };
  }

  String? _validateClinical() {
    return switch (_kind) {
      TreatmentKind.rct when _tooth == null => 'Select the tooth for RCT.',
      TreatmentKind.crown when _tooth == null => 'Select the tooth for the crown.',
      TreatmentKind.bridge when _teeth.isEmpty => 'Select the teeth involved in the bridge.',
      TreatmentKind.removableDenture || TreatmentKind.fullDenture when _arch.isEmpty => 'Select upper, lower, or both.',
      _ => null,
    };
  }

  Future<void> _save() async {
    if (_treatment == null || !isValidMoney(_amount.text)) {
      setState(() => _error = 'Select a treatment and enter a fee greater than 0.');
      return;
    }
    final clinicalError = _validateClinical();
    if (clinicalError != null) {
      setState(() => _error = clinicalError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await ref.read(financeRepositoryProvider).saveTreatmentVisit(
            date: DateFormat('yyyy-MM-dd').format(_date),
            treatmentId: _treatment!.id,
            amount: moneyFromDouble(moneyToDouble(_amount.text)),
            patientId: _patient?.id,
            patientName: _patient?.name,
            patientPhone: _patient?.phone,
            subTreatment: _family == TreatmentFamily.prosthetic || _family == TreatmentFamily.perio
                ? _treatment!.name
                : null,
            details: _details(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            xrays: [
              for (final item in _xrays) (bytes: item.bytes, filename: item.filename, label: item.label),
            ],
          );
      if (mounted) {
        showAppSnack(context, message);
        appPop(context, fallback: '/clinic');
      }
    } catch (error) {
      setState(() => _error = friendlyError(error));
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
      fallback: '/clinic',
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const AppBarTitle('New treatment'),
        ),
        body: AppPageBody(
          padding: AppLayout.pagePadding(context, top: 8, bottom: 8),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: AppLayout.pagePadding(context).bottom),
            children: [
              _patientCard(),
              const SizedBox(height: 12),
              DatePickerTile(
                label: 'Treatment date',
                value: DateFormat('yyyy-MM-dd').format(_date),
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
              const SizedBox(height: 12),
              _familyPicker(),
              if (_family == TreatmentFamily.prosthetic) ...[
                const SizedBox(height: 12),
                _catalogDropdown('Sub-treatment', _prostheticItems, _treatment, (value) {
                  setState(() {
                    _treatment = value;
                    _applyDefaultPrice();
                  });
                }),
              ],
              if (_family == TreatmentFamily.perio) ...[
                const SizedBox(height: 12),
                _catalogDropdown('Sub-treatment', _perioItems, _treatment, (value) {
                  setState(() {
                    _treatment = value;
                    _applyDefaultPrice();
                  });
                }),
              ],
              if (_family == TreatmentFamily.general) ...[
                const SizedBox(height: 12),
                _catalogDropdown('Treatment', _generalItems, _treatment, (value) {
                  setState(() {
                    _treatment = value;
                    _applyDefaultPrice();
                  });
                }),
              ],
              if (_treatment != null) ...[
                const SizedBox(height: 16),
                Text('Clinical details', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._clinicalFields(),
                const SizedBox(height: 16),
                _xraySection(),
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Treatment fee'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 16),
              TotalBar(label: 'Fee', value: formatMoney(isValidMoney(_amount.text) ? moneyFromDouble(moneyToDouble(_amount.text)) : '0.00')),
              const SizedBox(height: 12),
              Stretch(
                child: FilledButton(
                  onPressed: _busy || !_canSave ? null : _save,
                  child: Text(_busy ? 'Saving…' : 'Save treatment'),
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
        ? _patients.take(6).toList()
        : _patients
            .where((item) => item.name.toLowerCase().contains(needle) || (item.phone ?? '').contains(needle))
            .take(6)
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
              const Text('Select a patient or add a new one. Phone number is saved with the patient.'),
            const SizedBox(height: 8),
            TextField(
              controller: _patientSearch,
              decoration: const InputDecoration(labelText: 'Search patients', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (_) => setState(() {}),
            ),
            if (_patient == null)
              for (final item in matches)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  subtitle: item.phone == null ? null : Text(item.phone!),
                  onTap: () => setState(() {
                    _patient = item;
                    _patientSearch.clear();
                  }),
                ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addPatient,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add patient'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _familyPicker() {
    return DropdownButtonFormField<TreatmentFamily>(
      initialValue: _family,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Main treatment'),
      items: [
        if (_rctItem != null) const DropdownMenuItem(value: TreatmentFamily.rct, child: Text('RCT')),
        if (_prostheticItems.isNotEmpty) const DropdownMenuItem(value: TreatmentFamily.prosthetic, child: Text('Prosthetic')),
        if (_perioItems.isNotEmpty) const DropdownMenuItem(value: TreatmentFamily.perio, child: Text('Periodontal')),
        if (_generalItems.isNotEmpty) const DropdownMenuItem(value: TreatmentFamily.general, child: Text('Other treatment')),
      ],
      onChanged: _selectFamily,
    );
  }

  Widget _catalogDropdown(
    String label,
    List<CatalogItem> items,
    CatalogItem? selected,
    ValueChanged<CatalogItem?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: selected?.id,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in items)
          DropdownMenuItem(
            value: item.id,
            child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (id) {
        final match = items.where((item) => item.id == id);
        onChanged(match.isEmpty ? null : match.first);
      },
    );
  }

  List<Widget> _clinicalFields() {
    return switch (_kind) {
      TreatmentKind.rct => [
          _toothDropdown(single: true),
          if (toothNameFor(_tooth) != null) ...[
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Tooth name'),
              child: Text(toothNameFor(_tooth)!),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _canals,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Number of canals'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _length,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Tooth / canal length (mm)'),
          ),
        ],
      TreatmentKind.crown => [
          _toothDropdown(single: true),
          const SizedBox(height: 12),
          _materialPicker(),
          const SizedBox(height: 12),
          TextField(controller: _units, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of units')),
        ],
      TreatmentKind.bridge => [
          _toothDropdown(single: false),
          const SizedBox(height: 12),
          _materialPicker(),
          const SizedBox(height: 12),
          TextField(controller: _units, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of units')),
        ],
      TreatmentKind.removableDenture => [
          _archPicker(),
          const SizedBox(height: 12),
          TextField(controller: _partial, decoration: const InputDecoration(labelText: 'Partial denture details')),
          const SizedBox(height: 12),
          TextField(controller: _teethCount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of teeth')),
          const SizedBox(height: 12),
          _materialPicker(includePfz: false),
        ],
      TreatmentKind.fullDenture => [_archPicker()],
      TreatmentKind.scaling => [
          DropdownButtonFormField<String>(
            initialValue: _scope,
            decoration: const InputDecoration(labelText: 'Scaling area'),
            items: const [
              DropdownMenuItem(value: 'full mouth', child: Text('Full mouth')),
              DropdownMenuItem(value: 'upper', child: Text('Upper')),
              DropdownMenuItem(value: 'lower', child: Text('Lower')),
            ],
            onChanged: (value) => setState(() => _scope = value ?? 'full mouth'),
          ),
        ],
      TreatmentKind.general => const [],
    };
  }

  Widget _toothDropdown({required bool single}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: single ? _tooth : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: single ? 'Tooth number' : 'Add a tooth'),
          items: [
            for (final entry in toothQuadrants.entries)
              for (final number in entry.value)
                DropdownMenuItem(value: number, child: Text('#$number  ${toothNameFor(number)}')),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              if (single) {
                _tooth = value;
              } else if (!_teeth.contains(value)) {
                _teeth.add(value);
                _units.text = '${_teeth.length}';
              }
            });
          },
        ),
        if (!single && _teeth.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final tooth in _teeth)
                Chip(
                  label: Text('#$tooth'),
                  onDeleted: () => setState(() {
                    _teeth.remove(tooth);
                    _units.text = '${_teeth.length}';
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _materialPicker({bool includePfz = true}) {
    final options = [
      if (includePfz) 'PFM',
      'Zirconia',
      'Other',
    ];
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: options.contains(_material) ? _material : options.first,
          decoration: const InputDecoration(labelText: 'Material / type'),
          items: [for (final item in options) DropdownMenuItem(value: item, child: Text(item))],
          onChanged: (value) => setState(() => _material = value ?? options.first),
        ),
        if (_material == 'Other') ...[
          const SizedBox(height: 12),
          TextField(controller: _otherMaterial, decoration: const InputDecoration(labelText: 'Specify material')),
        ],
      ],
    );
  }

  Widget _archPicker() {
    return DropdownButtonFormField<String>(
      initialValue: _arch,
      decoration: const InputDecoration(labelText: 'Upper / Lower'),
      items: const [
        DropdownMenuItem(value: 'upper', child: Text('Upper')),
        DropdownMenuItem(value: 'lower', child: Text('Lower')),
        DropdownMenuItem(value: 'both', child: Text('Both')),
      ],
      onChanged: (value) => setState(() => _arch = value ?? 'upper'),
    );
  }

  Widget _xraySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('X-ray images', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickXray(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Gallery'),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickXray(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Camera'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _xrays.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_xrays[i].bytes, width: 56, height: 56, fit: BoxFit.cover),
              ),
              title: DropdownButton<String>(
                value: _xrays[i].label,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'before', child: Text('Before')),
                  DropdownMenuItem(value: 'working', child: Text('Working')),
                  DropdownMenuItem(value: 'after', child: Text('After')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) => setState(() => _xrays[i].label = value ?? 'other'),
              ),
              trailing: IconButton(
                tooltip: 'Remove',
                onPressed: () => setState(() => _xrays.removeAt(i)),
                icon: const Icon(Icons.close_rounded, color: AppColors.danger),
              ),
            ),
          ),
      ],
    );
  }
}
