import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesbar/m0_pages.dart';

void main() {
  testWidgets('authentication screen provides sign-in and registration', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AuthPage(
        onSignIn: (email, password) async {},
        onSignUp: (email, password) async => true,
        onSessionChanged: () async {},
      ),
    ));

    expect(find.text('Masuk'), findsWidgets);
    expect(find.text('Daftar warga'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });
}
