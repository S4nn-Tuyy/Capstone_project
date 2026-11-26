import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesbar/broadcast_pages.dart';
import 'package:wesbar/broadcast_repository.dart';
import 'package:wesbar/m0_repository.dart';

class _FakeBroadcastGateway implements BroadcastGateway {
  final changes = StreamController<void>.broadcast();
  List<BroadcastAnnouncement> inbox = [];
  List<BroadcastAnnouncement> outbox = [];
  String? readId;
  String? publishedKind;
  String? publishedAudience;
  String? publishedRtId;
  String? publishedRole;

  @override
  Future<List<BroadcastAnnouncement>> received(String profileId) async => inbox;

  @override
  Future<List<BroadcastAnnouncement>> sent(String profileId) async => outbox;

  @override
  Future<List<BroadcastRt>> availableRts() async => const [
        BroadcastRt(id: 'rt-id', code: 'DEMO-01', name: 'Demo'),
      ];

  @override
  Future<BroadcastSubmission> publish({
    required String kind,
    required String audience,
    String? targetRtId,
    String? targetRole,
    required String title,
    required String content,
  }) async {
    publishedKind = kind;
    publishedAudience = audience;
    publishedRtId = targetRtId;
    publishedRole = targetRole;
    return const BroadcastSubmission(id: 'announcement-1', recipientCount: 3);
  }

  @override
  Future<void> markRead(String announcementId, String profileId) async {
    readId = announcementId;
  }

  @override
  Stream<void> watchChanges(String profileId) => changes.stream;

  @override
  Future<void> dispose() async {
    if (!changes.isClosed) await changes.close();
  }
}

void main() {
  const resident = ResidentProfile(
    id: 'resident-1',
    name: 'Warga Demo',
    role: 'warga',
    verificationStatus: 'terverifikasi',
    rtId: 'rt-id',
    unitId: 'unit-1',
  );
  const rtManager = ResidentProfile(
    id: 'rt-manager-1',
    name: 'Pengurus Demo',
    role: 'pengurus_rt',
    verificationStatus: 'terverifikasi',
    rtId: 'rt-id',
  );

  testWidgets('resident can open a broadcast and mark it as read', (tester) async {
    final gateway = _FakeBroadcastGateway()
      ..inbox = [
        BroadcastAnnouncement(
          id: 'announcement-1',
          kind: 'penting',
          audience: 'rt',
          title: 'Kerja bakti',
          content: 'Kerja bakti hari Minggu pukul 07.00.',
          createdAt: DateTime.utc(2026, 11, 9),
          sentAt: DateTime.utc(2026, 11, 9),
        ),
      ];
    await tester.pumpWidget(MaterialApp(
      home: BroadcastPage(profile: resident, gateway: gateway, onSignOut: () async {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Kerja bakti'), findsOneWidget);
    await tester.tap(find.byKey(const Key('announcement_announcement-1')));
    await tester.pumpAndSettle();

    expect(gateway.readId, 'announcement-1');
    expect(find.text('Kerja bakti hari Minggu pukul 07.00.'), findsOneWidget);
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unread announcement badge updates on realtime events', (tester) async {
    final gateway = _FakeBroadcastGateway();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [
          BroadcastShortcut(
            profileId: resident.id,
            gateway: gateway,
            onPressed: () {},
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNothing);

    gateway.inbox = [
      BroadcastAnnouncement(
        id: 'announcement-2',
        kind: 'umum',
        audience: 'rt',
        title: 'Informasi warga',
        content: 'Informasi.',
        createdAt: DateTime.utc(2026, 11, 9),
        sentAt: DateTime.utc(2026, 11, 9),
      ),
    ];
    gateway.changes.add(null);
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('RT can publish an immediate announcement to its own RT', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _FakeBroadcastGateway();
    await tester.pumpWidget(MaterialApp(
      home: BroadcastPage(profile: rtManager, gateway: gateway, onSignOut: () async {}),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('broadcast_compose')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('broadcast_title')), 'Jadwal ronda');
    await tester.enterText(find.byKey(const Key('broadcast_content')), 'Ronda mulai pukul 21.00.');
    await tester.tap(find.byKey(const Key('broadcast_send')));
    await tester.pumpAndSettle();

    expect(gateway.publishedKind, 'umum');
    expect(gateway.publishedAudience, 'rt');
    expect(gateway.publishedRtId, 'rt-id');
    expect(gateway.publishedRole, isNull);
    expect(find.text('Pengumuman terkirim ke 3 akun.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
