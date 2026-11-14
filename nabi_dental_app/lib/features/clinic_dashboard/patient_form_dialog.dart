import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../core/models/finance_models.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/app_layout.dart';

class PatientFormDialog extends StatefulWidget {
  const PatientFormDialog({super.key, this.existing, this.patients = const []});

  final PatientRecord? existing;
  final List<PatientRecord> patients;

  @override
  State<PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends State<PatientFormDialog> {
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
                  helperText: 'Optional. You can add it later.',
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
