import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/dental/tooth_catalog.dart';
import '../../core/dental/xray_validation.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/media/clinic_image_picker.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_memory_image.dart';

class TreatmentLineXray {
  TreatmentLineXray({required this.bytes, required this.filename, this.id, this.label = 'before'});

  final Uint8List bytes;
  final String filename;
  final String? id;
  String label;

  bool get isSaved => id != null;
}

class TreatmentLineSeed {
  const TreatmentLineSeed({
    required this.id,
    this.treatment,
    this.details = const {},
    this.amount = '',
    this.notes,
    this.xrays = const [],
  });

  final String id;
  final CatalogItem? treatment;
  final Map<String, dynamic> details;
  final String amount;
  final String? notes;
  final List<TreatmentLineXray> xrays;
}

class TreatmentLineSnapshot {
  const TreatmentLineSnapshot({
    required this.id,
    required this.treatment,
    required this.details,
    required this.amount,
    required this.notes,
    required this.xrays,
    required this.removedAttachmentIds,
    this.clinicalError,
  });

  final String id;
  final CatalogItem? treatment;
  final Map<String, dynamic> details;
  final String amount;
  final String? notes;
  final List<TreatmentLineXray> xrays;
  final List<String> removedAttachmentIds;
  final String? clinicalError;
}

class TreatmentLineCard extends StatefulWidget {
  const TreatmentLineCard({
    super.key,
    required this.seed,
    required this.index,
    required this.treatments,
    required this.canRemove,
    this.onRemove,
    this.onChanged,
  });

  final TreatmentLineSeed seed;
  final int index;
  final List<CatalogItem> treatments;
  final bool canRemove;
  final VoidCallback? onRemove;
  final VoidCallback? onChanged;

  @override
  State<TreatmentLineCard> createState() => TreatmentLineCardState();
}

class TreatmentLineCardState extends State<TreatmentLineCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  CatalogItem? _treatment;
  String? _tooth;
  final _teeth = <String>[];
  String _material = 'PFM';
  String _arch = 'upper';
  String _scope = 'full mouth';
  final _search = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _length = TextEditingController();
  final _units = TextEditingController(text: '1');
  final _canals = TextEditingController(text: '3');
  final _teethCount = TextEditingController();
  final _partial = TextEditingController();
  final _otherMaterial = TextEditingController();
  final _xrays = <TreatmentLineXray>[];
  final _removedAttachmentIds = <String>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _hydrate(widget.seed);
  }

  @override
  void dispose() {
    _search.dispose();
    _amount.dispose();
    _notes.dispose();
    _length.dispose();
    _units.dispose();
    _canals.dispose();
    _teethCount.dispose();
    _partial.dispose();
    _otherMaterial.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TreatmentLineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _treatment;
    if (current == null) {
      return;
    }
    final resolved = _resolveTreatment(current);
    if (resolved != null && resolved.id != current.id) {
      _treatment = resolved;
    }
  }

  CatalogItem? _resolveTreatment(CatalogItem? item) {
    if (item == null) {
      return null;
    }
    return findCatalogMatch(widget.treatments, id: item.id, name: item.name) ?? item;
  }

  void _hydrate(TreatmentLineSeed seed) {
    _treatment = _resolveTreatment(seed.treatment);
    _amount.text = seed.amount;
    _notes.text = seed.notes ?? '';
    _xrays
      ..clear()
      ..addAll(seed.xrays);
    final details = seed.details;
    _tooth = details['tooth_number']?.toString();
    _teeth.clear();
    final teeth = details['tooth_numbers'];
    if (teeth is List) {
      _teeth.addAll([for (final item in teeth) item.toString()]);
    }
    _canals.text = '${details['canals'] ?? 3}';
    _length.text = details['length_mm']?.toString() ?? '';
    _units.text = '${details['units'] ?? (_teeth.isEmpty ? 1 : _teeth.length)}';
    _arch = (details['arch'] ?? 'upper').toString();
    _scope = (details['scope'] ?? 'full mouth').toString();
    _partial.text = details['partial_details']?.toString() ?? '';
    _teethCount.text = details['teeth_count']?.toString() ?? '';
    final material = details['material']?.toString().trim();
    if (material == null || material.isEmpty || material == 'PFM' || material == 'Zirconia' || material == 'Porcelain') {
      _material = material == null || material.isEmpty ? 'PFM' : material;
      _otherMaterial.clear();
    } else {
      _material = 'Other';
      _otherMaterial.text = material;
    }
  }

  TreatmentKind get _kind {
    final item = _treatment;
    if (item == null) {
      return TreatmentKind.general;
    }
    return kindOf(item.name, categoryName: item.categoryName);
  }

  List<CatalogItem> get _pickerTreatments {
    final byName = {for (final item in widget.treatments) item.name.trim().toLowerCase(): item};
    final items = <CatalogItem>[
      for (final name in clinicTreatmentNames)
        if (byName[name.toLowerCase()] != null) byName[name.toLowerCase()]!,
    ];
    final selected = _treatment;
    if (selected != null && items.every((item) => item.id != selected.id)) {
      items.add(selected);
    }
    return items;
  }

  List<CatalogItem> get _filteredTreatments {
    final needle = _search.text.trim().toLowerCase();
    if (needle.isEmpty) {
      return _pickerTreatments;
    }
    return [for (final item in _pickerTreatments) if (item.name.toLowerCase().contains(needle)) item];
  }

  void _notify() => widget.onChanged?.call();

  void _selectTreatment(CatalogItem? value) {
    setState(() {
      _treatment = value;
      _search.clear();
      _applyTreatmentDefaults();
    });
    _notify();
  }

  void _applyTreatmentDefaults() {
    final name = _treatment?.name.toLowerCase() ?? '';
    if (name.contains('zirconia')) {
      _material = 'Zirconia';
    } else if (name.contains('porcelain')) {
      _material = 'Porcelain';
      _otherMaterial.clear();
    }
    final price = _treatment?.defaultPrice;
    if (price != null && _amount.text.trim().isEmpty) {
      _amount.text = price;
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
    final name = _treatment?.name ?? '';
    return switch (_kind) {
      TreatmentKind.rct when _tooth == null => 'Select the tooth for this RCT.',
      TreatmentKind.crown when _tooth == null => 'Select the tooth for the crown.',
      TreatmentKind.bridge when _teeth.isEmpty => 'Select the teeth involved in the bridge.',
      TreatmentKind.removableDenture || TreatmentKind.fullDenture when _arch.isEmpty => 'Select upper, lower, or both.',
      TreatmentKind.general when requiresToothSelection(name) && _tooth == null => 'Select the tooth for this treatment.',
      _ => null,
    };
  }

  TreatmentLineSnapshot snapshot() {
    final details = _details();
    details['id'] = widget.seed.id;
    details['sub_treatment'] = _treatment?.name;
    details['treatment_id'] = _treatment?.id;
    details['treatment_name'] = _treatment?.name;
    details['category_name'] = _treatment?.categoryName;
    details['amount'] = moneyFromDouble(moneyToDouble(_amount.text));
    details['notes'] = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    details['attachment_ids'] = [
      for (final item in _xrays)
        if (item.id != null) item.id,
    ];
    return TreatmentLineSnapshot(
      id: widget.seed.id,
      treatment: _treatment,
      details: details,
      amount: _amount.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      xrays: List<TreatmentLineXray>.from(_xrays),
      removedAttachmentIds: List<String>.from(_removedAttachmentIds),
      clinicalError: _treatment == null
          ? 'Select a treatment.'
          : !isValidMoney(_amount.text)
              ? 'Enter a fee greater than 0.'
              : _validateClinical(),
    );
  }

  Future<void> _pickXray({bool fromCamera = false}) async {
    try {
      final picked = await pickClinicImage(fromCamera: fromCamera);
      if (picked == null) {
        return;
      }
      final fileError = validateXrayFile(filename: picked.filename, byteLength: picked.bytes.length);
      if (fileError != null) {
        setState(() => _error = fileError);
        return;
      }
      final imageError = await validateXrayImage(picked.bytes);
      if (imageError != null) {
        setState(() => _error = imageError);
        return;
      }
      if (_xrays.length >= 8) {
        setState(() => _error = 'Each treatment can have at most 8 X-ray images.');
        return;
      }
      setState(() {
        _error = null;
        _xrays.add(TreatmentLineXray(bytes: picked.bytes, filename: picked.filename));
      });
      _notify();
    } catch (error) {
      setState(() => _error = friendlyError(error, feature: 'upload'));
    }
  }

  Future<void> _previewXray(TreatmentLineXray item) async {
    if (item.bytes.isEmpty) {
      return;
    }
    await showAppDialog<void>(
      context: context,
      title: 'Selected image',
      content: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AppMemoryImage(bytes: item.bytes, height: 280, fit: BoxFit.contain),
      ),
      actions: (dialogContext) => [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final clinical = _treatment == null ? const <Widget>[] : _clinicalFields();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Treatment ${widget.index + 1}', style: Theme.of(context).textTheme.titleMedium),
                ),
                if (widget.canRemove)
                  IconButton(
                    tooltip: 'Remove treatment',
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close_rounded, color: AppColors.danger),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _treatmentPicker(),
            if (_treatment != null) ...[
              if (clinical.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Clinical details', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ...clinical,
              ],
              const SizedBox(height: 16),
              _xraySection(),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Treatment fee', prefixIcon: Icon(Icons.payments_outlined)),
                onChanged: (_) {
                  setState(() {});
                  _notify();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes_rounded)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _treatmentPicker() {
    final filtered = _filteredTreatments;
    final query = _search.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: 'Search treatments',
            hintText: 'RCT, Braces, Filling…',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              query.isEmpty
                  ? 'No treatments are available yet. Refresh and try again.'
                  : 'No treatment matches "$query".',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Material(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final number = clinicTreatmentNumber(item.name);
                  final selected = _treatment?.id == item.id;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    selectedTileColor: AppColors.primarySoft,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: selected ? AppColors.primary : AppColors.card,
                      foregroundColor: selected ? Colors.white : AppColors.primary,
                      child: Text(
                        number > 0 ? '$number' : '${index + 1}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: selected ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                    onTap: () => _selectTreatment(item),
                  );
                },
              ),
            ),
          ),
      ],
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
      TreatmentKind.general => [
          if (requiresToothSelection(_treatment?.name ?? '')) ...[
            _toothDropdown(single: true),
            if (toothNameFor(_tooth) != null) ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Tooth name'),
                child: Text(toothNameFor(_tooth)!),
              ),
            ],
          ],
        ],
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
      'Porcelain',
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
        Text('Clinical images', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Attach a dental X-ray or intraoral photo for this treatment.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickXray(),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Choose image'),
            ),
            if (clinicCameraAvailable)
              OutlinedButton.icon(
                onPressed: () => _pickXray(fromCamera: true),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: AppMotion.of(context, AppMotion.medium),
          curve: AppMotion.standard,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              for (var i = 0; i < _xrays.length; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: _xrays[i].bytes.isEmpty ? null : () => _previewXray(_xrays[i]),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _xrays[i].bytes.isEmpty
                          ? const SizedBox(
                              width: 56,
                              height: 56,
                              child: Icon(Icons.image_not_supported_outlined, color: AppColors.muted),
                            )
                          : AppMemoryImage(bytes: _xrays[i].bytes, width: 56, height: 56),
                    ),
                    title: _xrays[i].isSaved
                        ? Text(_xrays[i].label.replaceAll('_', ' '))
                        : DropdownButton<String>(
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
                      onPressed: () => setState(() {
                        final removed = _xrays.removeAt(i);
                        if (removed.id != null) {
                          _removedAttachmentIds.add(removed.id!);
                        }
                        _notify();
                      }),
                      icon: const Icon(Icons.close_rounded, color: AppColors.danger),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
