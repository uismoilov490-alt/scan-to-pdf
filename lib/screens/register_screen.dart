import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/phone_country.dart';
import '../services/phone_country_catalog.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/phone_country_picker_sheet.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _phoneController = TextEditingController();
  final _manualDialController = TextEditingController();
  bool _agreedToTerms = false;
  bool _signingIn = false;
  String? _phoneError;

  PhoneCountry _selectedCountry = PhoneCountry.uz;
  bool _manualDialMode = false;

  final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  @override
  void initState() {
    super.initState();
    PhoneCountryCatalog.ensureLoaded();
  }

  @override
  void dispose() {
    _manualDialController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _dialDigits() {
    final manual = _manualDialController.text.replaceAll(RegExp(r'\D'), '');
    return _manualDialMode ? manual : _selectedCountry.dialDigits;
  }

  int _nationalMaxLen() {
    final dialLen = _dialDigits().length;
    return (15 - dialLen).clamp(5, 14);
  }

  bool _validDial(String dial) {
    return dial.isNotEmpty &&
        dial.length <= 6 &&
        RegExp(r'^[1-9]\d*$').hasMatch(dial);
  }

  Future<void> _pickCountry() async {
    final all = await PhoneCountryCatalog.ensureLoaded();
    if (!mounted) return;
    final picked = await showPhoneCountryPickerSheet(
      context,
      countries: all,
      selected: _manualDialMode ? null : _selectedCountry,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (picked.isManualOnly) {
        _manualDialMode = true;
        _manualDialController.text = picked.dialDigits;
      } else {
        _manualDialMode = false;
        _selectedCountry = picked;
        _manualDialController.clear();
      }
      _phoneError = null;
    });
  }

  Future<void> _onContinuePhone() async {
    final dial = _dialDigits();
    if (!_validDial(dial)) {
      setState(() => _phoneError = 'auth_error_invalid_country_code'.tr());
      return;
    }
    final national = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (national.length < 5) {
      setState(() => _phoneError = 'auth_phone_error_national'.tr());
      return;
    }
    if (dial.length + national.length > 15) {
      setState(() => _phoneError = 'auth_phone_error_invalid_length'.tr());
      return;
    }

    setState(() {
      _phoneError = null;
      _signingIn = true;
    });
    FocusScope.of(context).unfocus();

    final fullPhone = '+$dial$national';

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _signingIn = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_verifyErrorMessage(e.code)),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        codeSent: (String verificationId, int? resendToken) async {
          if (!mounted) return;
          setState(() => _signingIn = false);
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => OtpScreen(
                phone: fullPhone,
                verificationId: verificationId,
                resendToken: resendToken,
              ),
            ),
          );
          if (ok == true && mounted) Navigator.pop(context, true);
        },
        codeAutoRetrievalTimeout: (_) {
          if (mounted && _signingIn) setState(() => _signingIn = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _signingIn = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is FirebaseAuthException
                ? _verifyErrorMessage(e.code)
                : 'Xatolik: ${e.toString()}',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
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
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _signingIn = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_verifyErrorMessage(e.code)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _verifyErrorMessage(String code) => switch (code) {
    'invalid-phone-number' => 'auth_error_invalid_phone'.tr(),
    'too-many-requests' => 'auth_error_too_many_requests'.tr(),
    'quota-exceeded' => 'auth_error_quota'.tr(),
    'network-request-failed' => 'auth_error_network'.tr(),
    _ => 'auth_error_unknown'.tr(namedArgs: {'code': code}),
  };

  Future<void> _onContinueGoogle() async {
    setState(() => _signingIn = true);
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        // User cancelled
        if (mounted) setState(() => _signingIn = false);
        return;
      }

      await UserService.saveUser(
        name: account.displayName ?? account.email,
        email: account.email,
        photoUrl: account.photoUrl,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _signingIn = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('error_prefix'.tr(namedArgs: {'message': '$e'})),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final kbInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: cs.onSurface,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppTheme.authBackgroundGradient(context),
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(22, 8, 22, 28 + kbInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                        _BrandMark(colorScheme: cs),
                        const SizedBox(height: 28),
                        Text(
                          'auth_title'.tr(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'auth_subtitle'.tr(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: cs.outlineVariant.withValues(
                                alpha:
                                    theme.brightness == Brightness.dark
                                        ? 0.55
                                        : 0.12,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: cs.primary.withValues(
                                  alpha:
                                      theme.brightness == Brightness.dark
                                          ? 0.18
                                          : 0.07,
                                ),
                                blurRadius: 40,
                                offset: const Offset(0, 18),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha:
                                      theme.brightness == Brightness.dark
                                          ? 0.35
                                          : 0.04,
                                ),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: cs.primary.withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    12,
                                    12,
                                    12,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Checkbox(
                                          value: _agreedToTerms,
                                          onChanged: (v) {
                                            setState(
                                              () =>
                                                  _agreedToTerms = v ?? false,
                                            );
                                          },
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(5),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(
                                              () => _agreedToTerms =
                                                  !_agreedToTerms,
                                            );
                                          },
                                          child: RichText(
                                            text: TextSpan(
                                              style: TextStyle(
                                                fontSize: 13,
                                                height: 1.45,
                                                color: cs.onSurface,
                                              ),
                                              children: [
                                                TextSpan(
                                                  text: 'auth_terms_prefix'
                                                      .tr(),
                                                ),
                                                TextSpan(
                                                  text: 'auth_terms_link_use'
                                                      .tr(),
                                                  style: TextStyle(
                                                    color: cs.primary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: 'auth_terms_middle'
                                                      .tr(),
                                                ),
                                                TextSpan(
                                                  text:
                                                      'auth_terms_link_privacy'
                                                          .tr(),
                                                  style: TextStyle(
                                                    color: cs.primary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: 'auth_terms_suffix'
                                                      .tr(),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'auth_phone_section_title'.tr(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  letterSpacing: 0.3,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: _pickCountry,
                                      borderRadius: BorderRadius.circular(14),
                                      child: Ink(
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: cs.outlineVariant,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: SizedBox(
                                            height: 54,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                            Text(
                                              _manualDialMode
                                                  ? '🌐'
                                                  : _selectedCountry
                                                      .flagEmoji,
                                              style: const TextStyle(
                                                fontSize: 22,
                                                height: 1,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (!_manualDialMode)
                                              Text(
                                                '+${_selectedCountry.dialDigits}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                  color: cs.onSurface,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              )
                                            else
                                              Text(
                                                '+',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: cs.onSurfaceVariant,
                                              size: 22,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_manualDialMode) ...[
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 92,
                                      child: TextField(
                                        controller: _manualDialController,
                                        keyboardType: TextInputType.phone,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(6),
                                        ],
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.35,
                                        ),
                                        onChanged: (_) {
                                          if (_phoneError != null) {
                                            setState(
                                              () => _phoneError = null,
                                            );
                                          }
                                        },
                                        decoration: InputDecoration(
                                          hintText: '998',
                                          filled: true,
                                          fillColor: cs.surfaceContainerHigh,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 14,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide(
                                              color: cs.outlineVariant,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide(
                                              color: _phoneError != null
                                                  ? Colors.red
                                                  : cs.outlineVariant,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide(
                                              color: _phoneError != null
                                                  ? Colors.red
                                                  : cs.primary,
                                              width: 1.8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _phoneController,
                                      keyboardType: TextInputType.phone,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(
                                          _nationalMaxLen(),
                                        ),
                                      ],
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                      onChanged: (_) {
                                        if (_phoneError != null) {
                                          setState(() => _phoneError = null);
                                        }
                                      },
                                      decoration: InputDecoration(
                                        hintText: 'auth_phone_hint'.tr(),
                                        errorText: _phoneError,
                                        filled: true,
                                        fillColor: cs.surfaceContainerHigh,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 16,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: BorderSide(
                                            color: cs.outlineVariant,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: BorderSide(
                                            color: _phoneError != null
                                                ? Colors.red
                                                : cs.outlineVariant,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: BorderSide(
                                            color: _phoneError != null
                                                ? Colors.red
                                                : cs.primary,
                                            width: 1.8,
                                          ),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: const BorderSide(
                                            color: Colors.red,
                                          ),
                                        ),
                                        focusedErrorBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: const BorderSide(
                                            color: Colors.red,
                                            width: 1.8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 16,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'auth_continue_sms_note'.tr(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (!_agreedToTerms) ...[
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_rounded,
                                      size: 18,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'auth_terms_required_hint'.tr(),
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.4,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 52,
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed:
                                      (_agreedToTerms && !_signingIn)
                                          ? _onContinuePhone
                                          : null,
                                  style: FilledButton.styleFrom(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: _signingIn
                                      ? SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: cs.onPrimary,
                                          ),
                                        )
                                      : Text(
                                          'auth_continue_phone'.tr(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: cs.outlineVariant,
                                thickness: 1,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: Text(
                                'auth_divider_or'.tr(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: cs.outlineVariant,
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 54,
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: (_agreedToTerms && !_signingIn)
                                ? _onContinueGoogle
                                : null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cs.onSurface,
                              side: BorderSide(color: cs.outlineVariant),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              backgroundColor: cs.surfaceContainerLow,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                            ),
                            child: _signingIn
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: cs.primary,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const _GoogleMark(size: 22),
                                      const SizedBox(width: 12),
                                      Text(
                                        'auth_google'.tr(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  final ColorScheme colorScheme;

  const _BrandMark({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary,
              colorScheme.primary.withValues(alpha: 0.82),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 14,
              left: 18,
              child: Container(
                width: 28,
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.45),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            const Icon(
              Icons.verified_user_rounded,
              color: Colors.white,
              size: 36,
            ),
          ],
        ),
      ),
    );
  }
}

/// Markazlashtirilgan, multirang “G” belgisi (asset’siz).
class _GoogleMark extends StatelessWidget {
  final double size;

  const _GoogleMark({this.size = 22});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF4285F4),
              Color(0xFFEA4335),
              Color(0xFFFBBC05),
              Color(0xFF34A853),
            ],
            stops: [0.0, 0.35, 0.65, 1.0],
          ).createShader(bounds);
        },
        child: Text(
          'G',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: size * 0.92,
            fontWeight: FontWeight.w800,
            height: 1,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
