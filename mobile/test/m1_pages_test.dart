import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesbar/m0_pages.dart';
import 'package:wesbar/m0_repository.dart';
import 'package:wesbar/m1_pages.dart';
import 'package:wesbar/m1_repository.dart';

class _FakePanicGateway implements PanicGateway {
  int sends = 0;
  final changes = StreamController<void>.broadcast();
  List<IncidentSummary> incoming = [];
  List<IncidentSummary> mine = [];
  List<IncidentSummary> active = [];
  String? lastResponse;
  String? lastRespondedIncident;

  @override
  Future<PanicSubmission> send(String kind) async {
    sends++;
    return const PanicSubmission(queued: false, incidentId: 'incident-1');
  }

  @override
  Future<int> retryPending() async => 0;

  @override
  Future<List<EmergencyContact>> contacts(String rtId) async => const [];

  @override
  Future<List<IncidentSummary>> myActiveIncidents(String profileId) async =>
      mine;

  @override
  Future<List<IncidentSummary>> incomingIncidents(String profileId) async =>
      incoming;

  @override
  Future<List<IncidentSummary>> activeIncidents() async => active;

  @override
  Future<int> responders(String incidentId) async => 0;

  @override
  Future<void> respond(String incidentId, String response) async {
    lastRespondedIncident = incidentId;
    lastResponse = response;
  }

  @override
  Future<void> updateStatus(String incidentId, String status) async {}

  @override
  Stream<void> watchChanges(String profileId) => changes.stream;

  @override
  Future<void> dispose() async {
    if (!changes.isClosed) await changes.close();
  }
}

void main() {
  const profile = ResidentProfile(
    id: 'resident-1',
    name: 'Warga Demo',
    role: 'warga',
    verificationStatus: 'terverifikasi',
    rtId: 'rt-demo',
    unitId: 'unit-1',
  );

  testWidgets('panic countdown can be cancelled before sending',
      (tester) async {
    final gateway = _FakePanicGateway();
    await tester.pumpWidget(MaterialApp(
      home: PanicButtonPage(profile: profile, gateway: gateway),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('panic_button')));
    await tester.pump();
    expect(find.text('Alert dikirim dalam 3 detik'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Alert dikirim dalam 1 detik'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel_panic_countdown')));
    await tester.pump();

    expect(gateway.sends, 0);
    expect(find.byKey(const Key('panic_button')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('assigned incident is shown and can be acknowledged',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _FakePanicGateway();
    await tester.pumpWidget(MaterialApp(
      home: PanicButtonPage(profile: profile, gateway: gateway),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Tidak ada alert masuk yang aktif.'), findsOneWidget);

    gateway
      ..mine = [
        IncidentSummary(
          id: 'sent-1',
          kind: 'keamanan',
          status: 'aktif',
          location: 'Jalan Pengirim No. 01',
          createdAt: DateTime.utc(2026, 11, 9),
        ),
      ]
      ..incoming = [
        IncidentSummary(
          id: 'incoming-1',
          kind: 'medis',
          status: 'aktif',
          location: 'Jalan Penerima No. 02',
          createdAt: DateTime.utc(2026, 11, 9),
          recipientResponse: 'menunggu',
        ),
      ];
    gateway.changes.add(null);
    await tester.pumpAndSettle();

    expect(find.text('Insiden aktif saya'), findsOneWidget);
    expect(find.text('Jalan Pengirim No. 01'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Alert untuk saya'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Alert untuk saya'), findsOneWidget);
    expect(find.text('Jalan Penerima No. 02'), findsOneWidget);
    final respondButton = find.byKey(const Key('respond_incoming-1_menuju'));
    expect(respondButton, findsOneWidget);
    await tester.ensureVisible(respondButton);
    await tester.tap(respondButton);
    await tester.pumpAndSettle();

    expect(gateway.lastRespondedIncident, 'incoming-1');
    expect(gateway.lastResponse, 'menuju');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'RT active-incident banner appears on realtime changes and opens inbox',
      (tester) async {
    const rtProfile = ResidentProfile(
      id: 'rt-1',
      name: 'Pengurus Demo',
      role: 'pengurus_rt',
      verificationStatus: 'terverifikasi',
      rtId: 'rt-demo',
    );
    final gateway = _FakePanicGateway();
    var openedInbox = false;
    var openedTickets = false;
    await tester.pumpWidget(MaterialApp(
      home: RtVerificationPage(
        profile: rtProfile,
        loadPending: (_) async => const [],
        verify: (_, __, ___) async {},
        panicGateway: gateway,
        onSignOut: () async {},
        onOpenIncidents: () => openedInbox = true,
        onManageTickets: () => openedTickets = true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rt_active_incidents_banner')), findsNothing);
    await tester.tap(find.byKey(const Key('manage_tickets')));
    expect(openedTickets, isTrue);

    gateway.active = [
      IncidentSummary(
        id: 'active-1',
        kind: 'keamanan',
        status: 'aktif',
        location: 'DEMO-01 / Jalan Contoh No. 02',
        createdAt: DateTime.utc(2026, 11, 9),
      ),
    ];
    gateway.changes.add(null);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rt_active_incidents_banner')), findsOneWidget);
    expect(find.text('1 insiden aktif perlu diperhatikan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rt_active_incidents_banner')));
    expect(openedInbox, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('training mode completes without creating an alert',
      (tester) async {
    final gateway = _FakePanicGateway();
    await tester.pumpWidget(MaterialApp(
      home: PanicButtonPage(profile: profile, gateway: gateway),
    ));
    await tester.pumpAndSettle();

    expect(find.text('MINTA BANTUAN'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(find.byKey(const Key('training_mode_notice')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('LATIHAN'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('LATIHAN'), findsOneWidget);
    await tester.tap(find.byKey(const Key('panic_button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(gateway.sends, 0);
    expect(
        find.text(
            'Mode latihan: alert tidak disimpan dan tidak dikirim ke penerima.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('admin can open resident management from the incident inbox',
      (tester) async {
    const adminProfile = ResidentProfile(
      id: 'admin-1',
      name: 'Admin',
      role: 'admin',
      verificationStatus: 'terverifikasi',
    );
    final gateway = _FakePanicGateway();
    var openedManagement = false;
    var openedTickets = false;
    await tester.pumpWidget(MaterialApp(
      home: IncidentInboxPage(
        profile: adminProfile,
        gateway: gateway,
        onSignOut: () async {},
        onManageResidents: () => openedManagement = true,
        onManageTickets: () => openedTickets = true,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('manage_residents')));
    expect(openedManagement, isTrue);
    await tester.tap(find.byKey(const Key('manage_tickets')));
    expect(openedTickets, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
