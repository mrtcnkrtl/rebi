import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rebi/screens/chat/chat_parts.dart';

import 'helpers/app_harness.dart';

/// "Rebi ile konuş" sayfası: üst sahne, katlanma, geri düğmesi ve klavye davranışı.
void main() {
  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester);
  }

  ChatStage stage(WidgetTester tester) => tester.widget<ChatStage>(find.byType(ChatStage));

  group('oturumsuz davet (/rebi)', () {
    testWidgets('kabuğun logo çubuğu yoktur; geri düğmesi karşılamaya döner', (tester) async {
      final h = await pumpApp(tester, location: '/rebi', loggedIn: false);
      expect(find.byType(ChatStage), findsOneWidget);
      expect(find.byIcon(LucideIcons.menu), findsNothing, reason: 'çift başlık yok: kabuğun logo/menü çubuğu kalktı');

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await settle(tester, 8);
      expect(h.router.routeInformationProvider.value.uri.path, '/');
    });
  });

  group('oturumlu sohbet (/dashboard/chat)', () {
    testWidgets('geri düğmesi yoktur (alt sekme)', (tester) async {
      await pumpApp(tester, location: '/dashboard/chat');
      expect(find.byType(ChatStage), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronLeft), findsNothing);
    });

    testWidgets('boşken büyük sahne karşılama sorusunu taşır; ilk mesajla ince çubuğa katlanır, "Temizle" belirir', (tester) async {
      await pumpApp(tester, location: '/dashboard/chat');
      expect(stage(tester).expanded, isTrue);
      expect(find.text(tr('chat.emptyTitle')), findsOneWidget);
      expect(find.text(tr('chat.clear')), findsNothing, reason: 'boş sohbette silinecek bir şey yok');

      await ask(tester, 'Retinol nedir?');
      expect(stage(tester).expanded, isFalse);
      expect(find.text(tr('chat.emptyTitle')), findsNothing, reason: 'konuşma başladı, sahne katlandı');
      expect(find.text(tr('chat.clear')), findsOneWidget);

      await tapText(tester, tr('chat.clear'));
      expect(stage(tester).expanded, isTrue, reason: 'temizlenince sahne yeniden açılır');
      expect(find.text(tr('chat.emptyTitle')), findsOneWidget);
    });

    testWidgets('yanıt beklenirken imza "düşünüyor" durumundadır, yanıt gelince durur', (tester) async {
      final gate = Completer<void>();
      final backend = FakeBackend()..chatGate = gate;
      await pumpApp(tester, location: '/dashboard/chat', backend: backend);
      await tester.enterText(find.byType(TextField), 'Merhaba');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump(const Duration(milliseconds: 300));
      expect(stage(tester).thinking, isTrue);
      expect(find.byType(TypingBubble), findsOneWidget);

      gate.complete();
      await settle(tester);
      expect(stage(tester).thinking, isFalse);
      expect(find.byType(TypingBubble), findsNothing);
    });
  });

  group('sığmayan durumlar', () {
    testWidgets('dar yükseklikte (320×568) sahne ince kalır; karşılama sorusu kaydırılabilir gövdede, tam bir kez görünür', (tester) async {
      await pumpApp(tester, location: '/dashboard/chat', size: const Size(320, 568));
      expect(stage(tester).expanded, isFalse);
      expect(find.text(tr('chat.emptyTitle')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('klavye açılınca kota notu ve yapay zekâ beyanı gizlenir, kapanınca geri gelir', (tester) async {
      await pumpApp(tester, location: '/dashboard/chat');
      expect(find.text(tr('common.aiDisclaimer')), findsOneWidget);

      // Cihaz oranı 3: 300 mantıksal piksellik klavye.
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester, 6);
      expect(find.text(tr('common.aiDisclaimer')), findsNothing);
      expect(stage(tester).expanded, isFalse, reason: 'klavye varken büyük sahne yer açmak için katlanır');

      tester.view.resetViewInsets();
      await settle(tester, 6);
      expect(find.text(tr('common.aiDisclaimer')), findsOneWidget);
    });
  });
}
