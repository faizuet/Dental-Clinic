import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/auth/session_controller.dart';
import '../../core/widgets/app_controls.dart';
import '../../core/widgets/app_layout.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/error_banner.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _emailFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await ref.read(sessionProvider.notifier).login(_email.text.trim(), _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final clinicName = session.clinic?.name ?? 'Nabi Dental Clinic';
    final wide = MediaQuery.sizeOf(context).width >= 960;

    return AppExitScope(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (!session.busy) {
                _submit();
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: wide ? _desktopLayout(clinicName, session) : _compactLayout(clinicName, session),
          ),
        ),
      ),
    );
  }

  Widget _desktopLayout(String clinicName, SessionState session) {
    return Row(
      children: [
        Expanded(flex: 5, child: _brandPanel(clinicName, wide: true)),
        Expanded(
          flex: 6,
          child: ColoredBox(
            color: AppColors.background,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: (constraints.maxHeight - 96).clamp(0.0, double.infinity)),
                    child: Center(child: _loginCard(session, maxWidth: 440)),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _compactLayout(String clinicName, SessionState session) {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  _brandPanel(clinicName, wide: false),
                  const SizedBox(height: 28),
                  _loginCard(session, maxWidth: 460),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandPanel(String clinicName, {required bool wide}) {
    final panel = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 28),
        Text(
          clinicName,
          textAlign: wide ? TextAlign.left : TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Clinic management for the front desk',
          textAlign: wide ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 16,
            height: 1.45,
          ),
        ),
        if (wide) ...[
          const SizedBox(height: 36),
          _brandPoint(Icons.people_alt_outlined, 'Patient records and treatment history'),
          _brandPoint(Icons.healing_outlined, 'Treatments, RCT details, and X-rays'),
          _brandPoint(Icons.payments_outlined, 'Clinic income, expenses, and reports'),
        ],
      ],
    );

    if (!wide) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryDark, AppColors.primary, AppColors.secondary],
          ),
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
        child: panel,
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B4F9C), AppColors.primaryDark, AppColors.primary],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 48, 48, 48),
        child: panel,
      ),
    );
  }

  Widget _brandPoint(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 15, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginCard(SessionState session, {required double maxWidth}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 40, 36, 36),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Sign in', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                    'Use the clinic owner email and password.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 28),
                if (session.error != null) ...[
                  ErrorBanner(message: session.error!),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _email,
                  focusNode: _emailFocus,
                  enabled: !session.busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'owner@example.com',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) {
                      return 'Email is required.';
                    }
                    if (!email.contains('@') || !email.contains('.')) {
                      return 'Enter a valid email address.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  focusNode: _passwordFocus,
                  enabled: !session.busy,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => session.busy ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      onPressed: session.busy ? null : () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Stretch(
                  child: AppBusyButton(
                    busy: session.busy,
                    busyLabel: 'Signing in…',
                    onPressed: _submit,
                    label: 'Sign in',
                  ),
                ),
                const SizedBox(height: 16),
                  Text(
                    'This computer talks to the local clinic server only.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
