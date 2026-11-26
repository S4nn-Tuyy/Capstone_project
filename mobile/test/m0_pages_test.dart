import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesbar/m0_pages.dart';
import 'package:wesbar/m0_repository.dart';
import 'package:wesbar/m1_repository.dart';

class _NoopPanicGateway implements PanicGateway {
  @override
  Future<PanicSubmission> send(String kind) async =>
      const PanicSubmission(queued: false);

  @override
  Future<int> retryPending() async => 0;

  @override
  Future<List<EmergencyContact>> contacts(String rtId) async => const [];

  @override
  Future<List<IncidentSummary>> myActiveIncidents(String profileId) async =>
      const [];

  @override
  Future<List<IncidentSummary>> incomingIncidents(String profileId) async =>
      const [];

  @override
  Future<List<IncidentSummary>> activeIncidents() async => const [];

  @override
  Future<int> responders(String incidentId) async => 0;

  @override
  Future<void> respond(String incidentId, String response) async {}

  @override
  Future<void> updateStatus(String incidentId, String status) async {}

  @override
  Stream<void> watchChanges(String profileId) => const Stream<void>.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('account signup requires consent before contacting Auth',
      (tester) async {
    var signups = 0;
    await tester.pumpWidget(MaterialApp(
        home: AuthPage(
      onSignIn: (email, password) async {},
      onSignUp: (email, password) async {
        signups++;
        return true;
      },
      onSessionChanged: () async {},
    )));
    await tester.tap(find.text('Daftar warga'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(0), 'ani@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('Daftar'));
    await tester.pump();
    expect(signups, 0);
    expect(find.text('Setujui penggunaan email untuk membuat akun.'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('signup_consent')));
    await tester.pump();
    await tester.tap(find.text('Daftar'));
    await tester.pump();
    expect(signups, 1);
    expect(find.text('Periksa email untuk konfirmasi, lalu masuk kembali.'),
        findsOneWidget);
  });

  testWidgets('registration requires explicit consent', (tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var submissions = 0;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingPage(
        onSubmit: ({
          required name,
          required phone,
          required rtCode,
          required jalanName,
          required houseNumber,
          required consent,
        }) async {
          submissions++;
          expect(consent, isTrue);
          expect(name, 'Ani');
          expect(rtCode, '01');
        },
        onSignOut: () async {},
      ),
    ));

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ani');
    await tester.enterText(fields.at(2), '01');
    await tester.enterText(fields.at(3), 'Melati');
    await tester.enterText(fields.at(4), '7');
    await tester.ensureVisible(find.text('Ajukan verifikasi'));
    await tester.tap(find.text('Ajukan verifikasi'));
    await tester.pump();
    expect(submissions, 0);
    expect(find.text('Persetujuan penggunaan data wajib diberikan.'),
        findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('consent_checkbox')));
    await tester.tap(find.byKey(const Key('consent_checkbox')));
    await tester.pump();
    await tester.ensureVisible(find.text('Ajukan verifikasi'));
    await tester.tap(find.text('Ajukan verifikasi'));
    await tester.pump();
    expect(submissions, 1);
  });

  testWidgets('RT verifies a pending resident after confirmation',
      (tester) async {
    final rt = ResidentProfile(
      id: 'rt-user',
      name: 'Pengurus',
      role: 'pengurus_rt',
      verificationStatus: 'terverifikasi',
      rtId: 'rt-01',
    );
    final resident = ResidentProfile(
      id: 'warga-1',
      name: 'Ani',
      role: 'warga',
      verificationStatus: 'menunggu',
      rtId: 'rt-01',
      address: 'Melati No. 7',
    );
    var verified = false;
    var openedResidentManagement = false;
    await tester.pumpWidget(MaterialApp(
      home: RtVerificationPage(
        profile: rt,
        loadPending: (rtId) async => [resident],
        verify: (profileId, rtId, approve) async {
          expect(profileId, 'warga-1');
          expect(rtId, 'rt-01');
          verified = approve;
        },
        panicGateway: _NoopPanicGateway(),
        onSignOut: () async {},
        onManageResidents: () => openedResidentManagement = true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Melati No. 7'), findsOneWidget);
    await tester.tap(find.byKey(const Key('manage_residents')));
    expect(openedResidentManagement, isTrue);
    await tester.tap(find.byTooltip('Setujui Ani'));
    await tester.pumpAndSettle();
    expect(verified, isFalse);
    await tester.tap(find.text('Konfirmasi'));
    await tester.pumpAndSettle();
    expect(verified, isTrue);
  });
}
