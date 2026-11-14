import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/error_banner.dart';

const _loginHero = 'assets/brand/login_hero.jpg';

const _navy = Color(0xFF17315C);
const _blue = Color(0xFF1B6FE3);
const _blueDeep = Color(0xFF0C4E9A);
const _muted = Color(0xFF7C8DA3);
const _fieldFill = Color(0xFFF3F6FA);
const _fieldBorder = Color(0xFFE3EAF2);
const _page = Color(0xFFF4F8FD);

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
    await ref
        .read(sessionProvider.notifier)
        .login(_email.text.trim(), _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final clinicName = session.clinic?.name ?? 'Nabi Dental Clinic';
    final wide = MediaQuery.sizeOf(context).width >= 1080;

    return AppExitScope(
      child: Scaffold(
        backgroundColor: _page,
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
            child: wide
                ? _desktopLayout(clinicName, session)
                : _compactLayout(clinicName, session),
          ),
        ),
      ),
    );
  }

  Widget _desktopLayout(String clinicName, SessionState session) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: _page)),
            const Positioned.fill(
                child: CustomPaint(painter: _RightWashPainter())),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: width * 0.74,
              child: const ClipPath(
                clipper: _BrandEdgeClipper(),
                child: ColoredBox(color: Color(0xFF8EBEF6)),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: width * 0.725,
              child: ClipPath(
                clipper: const _BrandEdgeClipper(),
                child: _brandCanvas(clinicName),
              ),
            ),
            Positioned(
              left: width * 0.50,
              right: 0,
              top: 0,
              bottom: 0,
              child: _signInPane(session),
            ),
          ],
        );
      },
    );
  }

  Widget _compactLayout(String clinicName, SessionState session) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    _loginHero,
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                const SizedBox(height: 16),
                _brandLockup(clinicName, light: false),
                const SizedBox(height: 22),
                _loginCard(session),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandCanvas(String clinicName) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const aspect = 560 / 296;
        final maxImageHeight =
            (constraints.maxHeight - 196).clamp(140.0, constraints.maxHeight);
        final naturalHeight = constraints.maxWidth / aspect;
        final imageHeight =
            naturalHeight > maxImageHeight ? maxImageHeight : naturalHeight;
        final imageWidth = imageHeight * aspect;
        final top =
            ((constraints.maxHeight - imageHeight) * 0.46).clamp(88.0, 170.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFF8FBFE),
                    Color(0xFFE8F3FB),
                    Color(0xFFD7E8F7)
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: top,
              width: imageWidth,
              height: imageHeight,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent
                    ],
                    stops: [0, 0.07, 0.88, 1],
                  ).createShader(rect);
                },
                child: Image.asset(
                  _loginHero,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0x00F4F9FD),
                    Color(0x00F4F9FD),
                    Color(0xE6F4F9FD)
                  ],
                  stops: [0, 0.78, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 32, 96, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _brandLockup(clinicName, light: false),
                  const Spacer(),
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _FeatureBar(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _brandLockup(String clinicName, {required bool light}) {
    final title = light ? Colors.white : _navy;
    final subtitle = light ? Colors.white.withValues(alpha: 0.92) : _muted;
    return Row(
      children: [
        _ToothMark(color: light ? Colors.white : _blue, size: 54),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clinicName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: title,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Healthy Smile, Brighter Life',
                style: TextStyle(
                  color: subtitle,
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _signInPane(SessionState session) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cornerScript = constraints.maxHeight >= 760;
        return Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding:
                    EdgeInsets.fromLTRB(28, 24, 36, cornerScript ? 78 : 24),
                child: _loginCard(session),
              ),
            ),
            if (cornerScript)
              const Positioned(
                right: 40,
                bottom: 26,
                child: _ScriptTagline(),
              ),
          ],
        );
      },
    );
  }

  Widget _loginCard(SessionState session) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
                color: Color(0x1A1B4F8A),
                blurRadius: 40,
                offset: Offset(0, 18)),
            BoxShadow(
                color: Color(0x0F1B4F8A), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 30, 32, 26),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      _ToothMark(color: _blue, size: 58),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sign in',
                              style: TextStyle(
                                color: _navy,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                                letterSpacing: -0.7,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Access your clinic management system',
                              style: TextStyle(
                                  color: _muted, fontSize: 14, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
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
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email
                    ],
                    onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                    decoration: _fieldDecoration(
                      hint: 'Email Address',
                      icon: Icons.mail_outline_rounded,
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
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    focusNode: _passwordFocus,
                    enabled: !session.busy,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) {
                      if (!session.busy) {
                        _submit();
                      }
                    },
                    decoration: _fieldDecoration(
                      hint: 'Password',
                      icon: Icons.lock_outline_rounded,
                      suffix: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        onPressed: session.busy
                            ? null
                            : () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: _muted,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  _signInButton(session),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Expanded(
                          child: Divider(color: _fieldBorder, thickness: 1)),
                      Flexible(
                        flex: 8,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'This computer talks to the local clinic server only.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.35),
                          ),
                        ),
                      ),
                      Expanded(
                          child: Divider(color: _fieldBorder, thickness: 1)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(
      {required String hint, required IconData icon, Widget? suffix}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _fieldBorder),
    );
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF93A3B8), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _fieldFill,
      hintStyle: const TextStyle(
          color: Color(0xFF9AABBE), fontWeight: FontWeight.w500),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _blue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD64545)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD64545), width: 1.5),
      ),
    );
  }

  Widget _signInButton(SessionState session) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF3D92F6), Color(0xFF1564D6)]),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
              color: Color(0x401564D6), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: FilledButton(
        onPressed: session.busy ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: Colors.white,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(54),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: session.busy
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                  SizedBox(width: 10),
                  Text('Signing in…'),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login_rounded, size: 20),
                  SizedBox(width: 10),
                  Text('Sign in'),
                ],
              ),
      ),
    );
  }
}

class _FeatureBar extends StatelessWidget {
  const _FeatureBar();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white),
        boxShadow: const [
          BoxShadow(
              color: Color(0x141B4F8A), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: _FeatureRow(),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _Feature(
            icon: Icons.verified_user_outlined,
            title: 'Trusted Care',
            subtitle: 'You Can Rely On'),
        _FeatureDivider(),
        _Feature(
            title: 'Modern Dental',
            subtitle: 'Solutions',
            mark: _ToothMark(color: _blue, size: 22)),
        _FeatureDivider(),
        _Feature(
            icon: Icons.favorite_border_rounded,
            title: 'For a Healthier',
            subtitle: 'Happier You'),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(
      {required this.title, required this.subtitle, this.icon, this.mark});

  final IconData? icon;
  final Widget? mark;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE7F1FC),
          ),
          child: mark ?? Icon(icon, color: _blue, size: 20),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                  color: _navy,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.2),
            ),
            Text(
              subtitle,
              style:
                  const TextStyle(color: _muted, fontSize: 12.5, height: 1.2),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeatureDivider extends StatelessWidget {
  const _FeatureDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFFD5E3F2),
    );
  }
}

class _ScriptTagline extends StatelessWidget {
  const _ScriptTagline();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Your Dental Health\nOur Priority',
      textAlign: TextAlign.right,
      style: TextStyle(
        fontFamily: 'Segoe Script',
        fontFamilyFallback: ['Brush Script MT', 'Segoe Print'],
        color: _blueDeep,
        fontSize: 22,
        height: 1.15,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ToothMark extends StatelessWidget {
  const _ToothMark({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.92,
      child: CustomPaint(painter: _ToothPainter(color)),
    );
  }
}

class _ToothPainter extends CustomPainter {
  const _ToothPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..color = color;
    final tooth = Path()
      ..moveTo(w * 0.50, h * 0.08)
      ..cubicTo(w * 0.78, h * 0.00, w * 0.98, h * 0.20, w * 0.90, h * 0.40)
      ..cubicTo(w * 0.84, h * 0.54, w * 0.78, h * 0.58, w * 0.74, h * 0.96)
      ..cubicTo(w * 0.70, h * 1.04, w * 0.56, h * 0.90, w * 0.52, h * 0.68)
      ..cubicTo(w * 0.48, h * 0.90, w * 0.34, h * 1.04, w * 0.28, h * 0.96)
      ..cubicTo(w * 0.24, h * 0.58, w * 0.18, h * 0.54, w * 0.12, h * 0.40)
      ..cubicTo(w * 0.04, h * 0.20, w * 0.22, h * 0.00, w * 0.50, h * 0.08)
      ..close();
    canvas.drawPath(tooth, fill);

    final swoosh = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.00, h * 0.58)
        ..quadraticBezierTo(w * 0.22, h * 0.34, w * 0.46, h * 0.52),
      swoosh,
    );
  }

  @override
  bool shouldRepaint(covariant _ToothPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _BrandEdgeClipper extends CustomClipper<Path> {
  const _BrandEdgeClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.80, 0)
      ..cubicTo(w * 0.96, h * 0.06, w * 1.04, h * 0.18, w * 0.98, h * 0.34)
      ..cubicTo(w * 0.92, h * 0.48, w * 0.88, h * 0.56, w * 0.94, h * 0.70)
      ..cubicTo(w * 1.02, h * 0.84, w * 0.98, h * 0.94, w * 0.82, h)
      ..lineTo(0, h)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _RightWashPainter extends CustomPainter {
  const _RightWashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = const Color(0xFFE5F1FC);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.78, size.height * 0.22),
        width: size.width * 0.62,
        height: size.height * 0.62,
      ),
      soft,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.42, size.height * 0.78),
        width: size.width * 0.55,
        height: size.height * 0.46,
      ),
      Paint()..color = const Color(0xFFF8FBFE),
    );

    final tooth = Path()
      ..moveTo(size.width * 0.86, size.height * 0.10)
      ..cubicTo(size.width * 0.96, size.height * 0.08, size.width * 1.02,
          size.height * 0.20, size.width * 0.98, size.height * 0.30)
      ..cubicTo(size.width * 0.95, size.height * 0.38, size.width * 0.92,
          size.height * 0.40, size.width * 0.90, size.height * 0.52)
      ..cubicTo(size.width * 0.88, size.height * 0.40, size.width * 0.84,
          size.height * 0.38, size.width * 0.80, size.height * 0.30)
      ..cubicTo(size.width * 0.76, size.height * 0.20, size.width * 0.80,
          size.height * 0.08, size.width * 0.86, size.height * 0.10)
      ..close();
    canvas.drawPath(tooth, Paint()..color = const Color(0xFFD9E9F8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
