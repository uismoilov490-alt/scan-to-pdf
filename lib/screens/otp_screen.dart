import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/user_service.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  final String verificationId;
  final int? resendToken;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.verificationId,
    this.resendToken,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  final _focusNode = FocusNode();

  late String _verificationId;
  int? _resendToken;

  bool _verifying = false;
  String? _error;
  int _countdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    _focusNode.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown == 0) {
        t.cancel();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _verify() async {
    final code = _otpController.text.trim();
    if (code.length < 6) return;
    if (_verifying) return;

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: code,
      );
      await _signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _verifying = false;
          _error = _errorMessage(e.code);
        });
        _otpController.clear();
        _focusNode.requestFocus();
      }
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    final result =
        await FirebaseAuth.instance.signInWithCredential(credential);
    final user = result.user;
    if (user != null && mounted) {
      await UserService.saveUser(
        name: user.displayName ?? '',
        email: user.email ?? '',
        photoUrl: user.photoURL,
        phone: user.phoneNumber,
      );
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _resend() async {
    if (_countdown > 0) return;
    setState(() => _error = null);

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: widget.phone,
      forceResendingToken: _resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        await _signInWithCredential(credential);
      },
      verificationFailed: (e) {
        if (mounted) {
          setState(
            () => _error = e.message ?? 'otp_error_generic'.tr(),
          );
        }
      },
      codeSent: (verificationId, resendToken) {
        if (mounted) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _startCountdown();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('otp_resent'.tr()),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  String _errorMessage(String code) => switch (code) {
    'invalid-verification-code' => 'otp_error_invalid_code'.tr(),
    'session-expired' => 'otp_error_session_expired'.tr(),
    'too-many-requests' => 'otp_error_too_many_requests'.tr(),
    'invalid-verification-id' => 'otp_error_invalid_id'.tr(),
    _ => 'otp_error_generic'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: cs.onSurface,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: cs.onSurface,
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primaryContainer,
                  ),
                  child: Icon(
                    Icons.sms_rounded,
                    size: 36,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'otp_title'.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'otp_subtitle'.tr(namedArgs: {'phone': widget.phone}),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 40),

              // Hidden TextField (actual input)
              Offstage(
                child: TextField(
                  controller: _otpController,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (val) {
                    setState(() {});
                    if (val.length == 6) _verify();
                  },
                ),
              ),

              // Visual OTP boxes
              GestureDetector(
                onTap: () => _focusNode.requestFocus(),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _otpController,
                  builder: (_, value, _) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (i) {
                        final char =
                            i < value.text.length ? value.text[i] : null;
                        final isActive =
                            i == value.text.length && _focusNode.hasFocus;
                        return _OtpCell(
                          char: char,
                          isActive: isActive,
                          hasError: _error != null,
                          colorScheme: cs,
                        );
                      }),
                    );
                  },
                ),
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 32),

              // Verify button
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _verifying ? null : _verify,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _verifying
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: cs.onPrimary,
                          ),
                        )
                      : Text(
                          'otp_verify'.tr(),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // Resend
              Center(
                child: _countdown > 0
                    ? Text.rich(
                        TextSpan(
                          text: 'otp_resend_prefix'.tr(),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                          ),
                          children: [
                            TextSpan(
                              text: '0:${_countdown.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : TextButton(
                        onPressed: _resend,
                        child: Text(
                          'otp_resend_btn'.tr(),
                          style: TextStyle(fontWeight: FontWeight.w600),
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

class _OtpCell extends StatelessWidget {
  final String? char;
  final bool isActive;
  final bool hasError;
  final ColorScheme colorScheme;

  const _OtpCell({
    required this.char,
    required this.isActive,
    required this.hasError,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final filled = char != null;
    final borderColor = hasError
        ? Colors.red
        : isActive
            ? colorScheme.primary
            : filled
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outlineVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 46,
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: filled
            ? colorScheme.primaryContainer.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: isActive ? 2 : 1.2,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: filled
          ? Text(
              char!,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
            )
          : isActive
              ? _BlinkingCursor(color: colorScheme.primary)
              : null,
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  final Color color;

  const _BlinkingCursor({required this.color});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 2,
        height: 28,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
