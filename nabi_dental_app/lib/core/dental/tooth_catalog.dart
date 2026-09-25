const toothNames = <String, String>{
  '11': 'Upper Right Central Incisor',
  '12': 'Upper Right Lateral Incisor',
  '13': 'Upper Right Canine',
  '14': 'Upper Right First Premolar',
  '15': 'Upper Right Second Premolar',
  '16': 'Upper Right First Molar',
  '17': 'Upper Right Second Molar',
  '18': 'Upper Right Third Molar',
  '21': 'Upper Left Central Incisor',
  '22': 'Upper Left Lateral Incisor',
  '23': 'Upper Left Canine',
  '24': 'Upper Left First Premolar',
  '25': 'Upper Left Second Premolar',
  '26': 'Upper Left First Molar',
  '27': 'Upper Left Second Molar',
  '28': 'Upper Left Third Molar',
  '31': 'Lower Left Central Incisor',
  '32': 'Lower Left Lateral Incisor',
  '33': 'Lower Left Canine',
  '34': 'Lower Left First Premolar',
  '35': 'Lower Left Second Premolar',
  '36': 'Lower Left First Molar',
  '37': 'Lower Left Second Molar',
  '38': 'Lower Left Third Molar',
  '41': 'Lower Right Central Incisor',
  '42': 'Lower Right Lateral Incisor',
  '43': 'Lower Right Canine',
  '44': 'Lower Right First Premolar',
  '45': 'Lower Right Second Premolar',
  '46': 'Lower Right First Molar',
  '47': 'Lower Right Second Molar',
  '48': 'Lower Right Third Molar',
};

const toothQuadrants = <String, List<String>>{
  'Upper right': ['18', '17', '16', '15', '14', '13', '12', '11'],
  'Upper left': ['21', '22', '23', '24', '25', '26', '27', '28'],
  'Lower left': ['31', '32', '33', '34', '35', '36', '37', '38'],
  'Lower right': ['41', '42', '43', '44', '45', '46', '47', '48'],
};

String? toothNameFor(String? number) {
  if (number == null || number.trim().isEmpty) {
    return null;
  }
  return toothNames[number.trim()];
}

enum TreatmentFamily { rct, prosthetic, perio, general }

enum TreatmentKind { rct, crown, bridge, removableDenture, fullDenture, scaling, general }

TreatmentFamily familyOf(String name, {String? categoryName}) {
  final n = name.toLowerCase();
  final c = (categoryName ?? '').toLowerCase();
  if (n.contains('rct') || n.contains('root canal')) {
    return TreatmentFamily.rct;
  }
  if (c.contains('prosthetic') || n.contains('crown') || n.contains('bridge') || n.contains('denture') || n.contains('implant')) {
    return TreatmentFamily.prosthetic;
  }
  if (c.contains('perio') || n.contains('scaling')) {
    return TreatmentFamily.perio;
  }
  return TreatmentFamily.general;
}

TreatmentKind kindOf(String name, {String? categoryName}) {
  final n = name.toLowerCase();
  if (n.contains('rct') || n.contains('root canal')) {
    return TreatmentKind.rct;
  }
  if (n.contains('bridge')) {
    return TreatmentKind.bridge;
  }
  if (n.contains('crown')) {
    return TreatmentKind.crown;
  }
  if (n.contains('full denture')) {
    return TreatmentKind.fullDenture;
  }
  if (n.contains('removable') || n == 'dentures') {
    return TreatmentKind.removableDenture;
  }
  if (n.contains('scaling')) {
    return TreatmentKind.scaling;
  }
  return familyOf(name, categoryName: categoryName) == TreatmentFamily.prosthetic
      ? TreatmentKind.crown
      : TreatmentKind.general;
}

String familyLabel(TreatmentFamily family) {
  return switch (family) {
    TreatmentFamily.rct => 'RCT',
    TreatmentFamily.prosthetic => 'Prosthetic',
    TreatmentFamily.perio => 'Periodontal',
    TreatmentFamily.general => 'Other',
  };
}

String clinicalSummary(Map<String, dynamic> details, {String? subTreatment}) {
  final parts = <String>[];
  if (subTreatment != null && subTreatment.trim().isNotEmpty) {
    parts.add(subTreatment.trim());
  }
  final numbers = _asList(details['tooth_numbers'] ?? details['tooth_number']);
  final names = _asList(details['tooth_names'] ?? details['tooth_name']);
  if (numbers.isNotEmpty) {
    parts.add(numbers.map((item) => '#$item').join(', '));
  }
  if (names.isNotEmpty && numbers.isEmpty) {
    parts.add(names.join(', '));
  }
  if (details['canals'] != null) {
    parts.add('${details['canals']} canals');
  }
  if (details['length_mm'] != null && details['length_mm'].toString().isNotEmpty) {
    parts.add('${details['length_mm']} mm');
  }
  if (details['material'] != null && details['material'].toString().isNotEmpty) {
    parts.add(details['material'].toString());
  }
  if (details['units'] != null) {
    parts.add('${details['units']} units');
  }
  final arch = details['arch'] ?? details['denture_type'];
  if (arch != null && arch.toString().isNotEmpty) {
    parts.add(arch.toString().replaceAll('_', ' '));
  }
  if (details['scope'] != null && details['scope'].toString().isNotEmpty) {
    parts.add(details['scope'].toString().replaceAll('_', ' '));
  }
  if (details['partial_details'] != null && details['partial_details'].toString().isNotEmpty) {
    parts.add(details['partial_details'].toString());
  }
  return parts.join(', ');
}

List<String> _asList(Object? value) {
  if (value is List) {
    return [for (final item in value) item.toString().trim()].where((item) => item.isNotEmpty).toList();
  }
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? const [] : [text];
}
