import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../ui/brand/brand_button.dart';
import '../../ui/brand/brand_mark.dart';
import '../../ui/brand/motion.dart';
import '../../ui/brand/palette.dart';
import '../../ui/brand/public_top_bar.dart';
import '../../ui/tw.dart';

// Giriş / kayıt ekranının yapı taşları (`AuthScreen` yalnızca kipleri ve akışı yönetir).

/// Üst sahne: derin orman yeşili zemin, krem Fraunces başlık ve sağ üstte çok silik dev "R" monogramı.
/// Monogram sayfa açılırken kendini çizer (tek, sakin hareket); mod değişince yalnızca başlık yumuşakça değişir.
class AuthStage extends StatelessWidget {
  const AuthStage({super.key, required this.modeKey, required this.compact, required this.title, required this.subtitle, required this.onBack});

  final String modeKey;

  /// Kayıt formu uzundur: sahne kısa kalır. Diğer kiplerde ekran yüksekliğinin ~%40'ına uzar, başlık alta oturur.
  final bool compact;
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    // Doğal yükseklik: durum çubuğu + üst çubuk (60) + boşluk + başlık bloğu (~75) + alt pay. Fazlası başlığın üstüne eklenir.
    final natural = top + 60 + 22 + 75 + 52;
    final extra = compact ? 0.0 : (MediaQuery.sizeOf(context).height * .40 - natural).clamp(0.0, 150.0);
    return Stack(
      children: [
        const Positioned(right: -90, top: -20, child: DrawnWatermark(size: 300)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: top),
            Reveal(offset: Offset.zero, child: PublicTopBar(onBack: onBack, onDark: true)),
            AnimatedPadding(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(26, 22 + extra, 26, 52),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, .14), end: Offset.zero).animate(anim), child: child),
                  ),
                  child: Column(
                    key: ValueKey(modeKey),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Brand.serif(38, ls: -1.2, h: 1.05, color: Brand.cream)),
                      const SizedBox(height: 10),
                      Text(subtitle, style: tx(16.5, c: Brand.cream.withValues(alpha: .74), h: 1.45)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Altı çizili metin eylemi (parolamı unuttum, tekrar gönder…); dokunma alanı en az 48 dp.
class AuthTextAction extends StatelessWidget {
  const AuthTextAction({super.key, required this.label, required this.onTap, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    // Kapalı (ör. yeniden gönderme bekleme süresinde) eylem soluk görünür; yükleniyorsa normal kalır.
    final dim = onTap == null && !busy;
    return Semantics(
      button: true,
      enabled: !dim,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Opacity(
              opacity: dim ? .5 : 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy) ...[
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Brand.ink)),
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: BrandLinkText(label, size: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Yüzen etiketli, yumuşak çerçeveli alan; odaklanınca çerçeve koyulaşır.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    this.icon,
    required this.controller,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.validator,
    this.obscure = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.suffix,
    this.onSubmitted,
    this.onChanged,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.textStyle,
  });

  final String label;

  /// Yoksa alanın başında simge bulunmaz (ortalanmış kod alanı).
  final IconData? icon;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final bool obscure;
  final bool autocorrect;
  final bool enableSuggestions;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1.2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      validator: validator,
      obscureText: obscure,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      onFieldSubmitted: onSubmitted,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      cursorColor: Brand.teal,
      style: textStyle ?? tx(16.5, w: 5, c: Brand.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: tx(15.5, c: Brand.inkSoft),
        floatingLabelStyle: tx(14, w: 6, c: Brand.ink),
        floatingLabelAlignment: icon == null ? FloatingLabelAlignment.center : null,
        filled: true,
        fillColor: Brand.surface,
        contentPadding: EdgeInsets.symmetric(horizontal: icon == null ? 16 : 4, vertical: icon == null ? 17 : 19),
        prefixIcon: icon == null
            ? null
            : Padding(padding: const EdgeInsetsDirectional.only(start: 16, end: 10), child: Icon(icon, size: 19, color: Brand.inkSoft)),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffix,
        errorStyle: tx(12, w: 5, c: Tw.red600),
        enabledBorder: border(Brand.ink.withValues(alpha: .12)),
        focusedBorder: border(Brand.ink, 1.6),
        errorBorder: border(Tw.red500),
        focusedErrorBorder: border(Tw.red500, 1.7),
        border: border(Brand.ink.withValues(alpha: .12)),
      ),
    );
  }
}

/// Parola gücü: dört parçalı ince çubuk ve kısa bir etiket; boşken kural ipucu gösterilir.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    if (level == 0) {
      return Text(i18n.t('mobileAuth.strengthHint'), style: tx(12, c: Brand.inkSoft, h: snug));
    }
    final colors = [Tw.red500, Tw.amber500, Tw.teal500, Tw.emerald500];
    final labels = ['mobileAuth.strengthWeak', 'mobileAuth.strengthFair', 'mobileAuth.strengthFair', 'mobileAuth.strengthStrong'];
    final color = colors[level - 1];
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 4,
                    margin: EdgeInsets.only(right: i < 3 ? 5 : 0),
                    decoration: BoxDecoration(color: i < level ? color : Brand.inkFaint, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(i18n.t(labels[level - 1]), style: tx(12, w: 7, c: color)),
      ],
    );
  }
}
