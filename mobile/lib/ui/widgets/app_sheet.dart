import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../brand/palette.dart';
import '../tw.dart';

/// Alt sayfa çerçevesi: tutamaç, Fraunces başlık, kapatma düğmesi ve kaydırılabilir gövde.
/// `showModalBottomSheet(isScrollControlled: true, backgroundColor: Colors.transparent, ...)` ile birlikte kullanılır;
/// klavye açılınca gövde yukarı kayar.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  /// Standart ayarlarla (şeffaf zemin, kök gezgin) açar.
  static Future<T?> show<T>(BuildContext context, {required String title, String? subtitle, required WidgetBuilder body}) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AppSheet(title: title, subtitle: subtitle, child: body(ctx)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 672, maxHeight: media.size.height * .88),
          child: Container(
            decoration: BoxDecoration(
              color: Tw.surfaceRaised,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: Tw.gray100)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Tw.gray200, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: heading(24, h: 1.15)),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(subtitle!, style: tx(13, c: Tw.gray500, h: snug)),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(LucideIcons.x, size: 22, color: Tw.gray500),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                      child: child,
                    ),
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
