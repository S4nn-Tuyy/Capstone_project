import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesbar/app_theme.dart';
import 'package:wesbar/panic_layout.dart';
import 'package:wesbar/status_indicator.dart';

void main() {
  test('brand palette is applied to the app theme', () {
    final scheme = WesbarTheme.light.colorScheme;

    expect(scheme.primary, WesbarPalette.royal);
    expect(scheme.secondary, WesbarPalette.china);
    expect(scheme.surface, WesbarPalette.moon);
    expect(WesbarTheme.light.scaffoldBackgroundColor, WesbarPalette.moon);
  });

  test('form and outlined button borders use stronger contrast colors', () {
    final theme = WesbarTheme.light;
    final inputBorder =
        theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
    final outlinedButtonBorder =
        theme.outlinedButtonTheme.style!.side!.resolve(const {})!;

    expect(inputBorder.borderSide.color, WesbarPalette.inputBorder);
    expect(outlinedButtonBorder.color, WesbarPalette.chinaBorder);
    expect(WesbarPalette.outline, const Color(0xFFD7DDE7));
  });

  test('navigation and status colors are available from the theme', () {
    final theme = WesbarTheme.light;

    expect(theme.navigationBarTheme.backgroundColor, WesbarPalette.card);
    expect(theme.navigationBarTheme.indicatorColor, const Color(0xFFE5EDF9));
    expect(
      theme.navigationBarTheme.labelTextStyle!.resolve(const {})!.fontSize,
      12,
    );
    expect(theme.extension<StatusColors>()?.pending, const Color(0xFFB54708));
    expect(theme.extension<StatusColors>()?.progress, WesbarPalette.royal);
    expect(theme.extension<StatusColors>()?.done, const Color(0xFF067647));
    expect(
      theme.extension<StatusColors>()?.escalated,
      WesbarPalette.emergency,
    );
  });

  test('status colors support copyWith and lerp', () {
    final colors = StatusColors.light;
    final copied = colors.copyWith(pending: Colors.blue);
    final other = colors.copyWith(pending: Colors.white);

    expect(copied.pending, Colors.blue);
    expect(colors.lerp(other, 0.5).pending,
        Color.lerp(colors.pending, Colors.white, 0.5));
  });

  test('panic button has a dedicated circular emergency style', () {
    final style = WesbarTheme.panicButton;

    expect(style.backgroundColor!.resolve(const {}), WesbarPalette.emergency);
    expect(style.foregroundColor!.resolve(const {}), Colors.white);
    expect(style.minimumSize!.resolve(const {}), const Size(160, 160));
    expect(style.shape!.resolve(const {}), isA<CircleBorder>());
  });

  testWidgets('resident bottom navigation emits the selected destination',
      (tester) async {
    var selectedIndex = 0;
    await tester.pumpWidget(MaterialApp(
      theme: WesbarTheme.light,
      home: Scaffold(
        bottomNavigationBar: WesbarNavBar(
          index: selectedIndex,
          onTap: (index) => selectedIndex = index,
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.confirmation_number_outlined));
    expect(selectedIndex, 2);
  });

  testWidgets('ticket status pairs a status color with text and an icon',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: WesbarTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(child: StatusIndicator.ticket(context, 'baru')),
        ),
      ),
    ));

    expect(find.text('Baru'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.schedule_outlined)).color,
      StatusColors.light.pending,
    );
  });

  test('primary actions have a comfortable minimum tap target', () {
    final style = WesbarTheme.light.filledButtonTheme.style!;

    expect(style.minimumSize!.resolve(const {}), const Size(48, 48));
    expect(
        WesbarTheme.light.materialTapTargetSize, MaterialTapTargetSize.padded);
  });
}
