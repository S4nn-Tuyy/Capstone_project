import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesbar/app_theme.dart';
import 'package:wesbar/m0_repository.dart';
import 'package:wesbar/ticket_management_pages.dart';
import 'package:wesbar/ticket_management_repository.dart';

ManagedTicket _ticketForResponseDeadline({
  required DateTime dueAt,
  DateTime? respondedAt,
}) =>
    ManagedTicket(
      id: 'ticket-deadline',
      reporterName: 'Warga',
      rtId: 'rt-01',
      category: 'fasilitas',
      priority: 'sedang',
      level: 'rt',
      status: respondedAt == null ? 'baru' : 'ditugaskan',
      description: 'Lampu jalan mati.',
      address: 'Jalan Melati · RT 01 · RW 05',
      createdAt: DateTime.utc(2026, 11, 24, 10),
      responseDueAt: dueAt,
      respondedAt: respondedAt,
    );

class _FakeTicketManagementGateway implements TicketManagementGateway {
  _FakeTicketManagementGateway(this.items);

  List<ManagedTicket> items;
  String? updatedStatus;
  String? escalationReason;
  bool escalated = false;

  @override
  Future<List<ManagedTicket>> tickets(ResidentProfile profile) async => items;

  @override
  Future<List<TicketHistoryEvent>> history(
    ResidentProfile profile,
    String ticketId,
  ) async =>
      [
        TicketHistoryEvent(
          action: 'dibuat',
          createdAt: DateTime.utc(2026, 11, 25),
          actorName: 'Ani Warga',
        ),
      ];

  @override
  Future<void> updateStatus({
    required ResidentProfile profile,
    required String ticketId,
    required String status,
  }) async {
    updatedStatus = status;
  }

  @override
  Future<void> escalate({
    required ResidentProfile profile,
    required String ticketId,
    required String reason,
  }) async {
    escalationReason = reason;
    escalated = true;
  }

  @override
  Future<String> signedPhotoUrl(String path) async =>
      'https://example.test/$path';
}

void main() {
  const rtManager = ResidentProfile(
    id: 'rt-manager',
    name: 'Pengurus RT',
    role: 'pengurus_rt',
    verificationStatus: 'terverifikasi',
    rtId: 'rt-01',
  );

  final ticket = ManagedTicket(
    id: 'ticket-1',
    reporterName: 'Ani Warga',
    rtId: 'rt-01',
    category: 'fasilitas',
    priority: 'sedang',
    level: 'rt',
    status: 'baru',
    description: 'Lampu jalan di depan rumah mati.',
    address: 'Jalan Melati No. 7 · RT 01 · RW 05',
    createdAt: DateTime.utc(2026, 11, 25, 10),
  );

  test('ticket history parses escalation reason', () {
    final event = TicketHistoryEvent.fromJson({
      'aksi': 'eskalasi',
      'status_sebelum': null,
      'status_sesudah': null,
      'level_sebelum': 'rt',
      'level_sesudah': 'rw',
      'catatan': 'Perlu penanganan fasilitas RW.',
      'created_at': '2026-11-25T10:00:00Z',
      'actor': {'full_name': 'Pengurus RT'},
    });

    expect(event.note, 'Perlu penanganan fasilitas RW.');
    expect(event.actorName, 'Pengurus RT');
  });

  test('response becomes overdue at its calendar deadline until responded', () {
    final dueAt = DateTime.utc(2026, 11, 25, 10);
    final unresponded = _ticketForResponseDeadline(dueAt: dueAt);
    final responded = _ticketForResponseDeadline(
      dueAt: dueAt,
      respondedAt: dueAt,
    );

    expect(unresponded.isResponseOverdueAt(dueAt), isTrue);
    expect(
      unresponded
          .isResponseOverdueAt(dueAt.subtract(const Duration(seconds: 1))),
      isFalse,
    );
    expect(responded.isResponseOverdueAt(dueAt), isFalse);
  });

  test('managed ticket parses address and nullable SLA deadlines', () {
    final parsed = ManagedTicket.fromJson({
      'id': 'ticket-1',
      'pelapor_id': 'resident-1',
      'rt_id': 'rt-01',
      'unit_id': 'unit-7',
      'kategori': 'fasilitas',
      'prioritas': 'sedang',
      'level': 'rt',
      'status': 'baru',
      'deskripsi': 'Lampu jalan mati.',
      'foto_path': null,
      'tenggat_respons_at': null,
      'tenggat_selesai_at': null,
      'created_at': '2026-11-25T10:00:00Z',
      'direspons_at': null,
      'pelapor': {'full_name': 'Ani Warga'},
      'unit': {
        'nomor': '7',
        'jalan': {'nama': 'Jalan Melati'},
      },
      'rt': {
        'kode': '01',
        'rw': {'kode': '05'},
      },
    });

    expect(parsed.reporterName, 'Ani Warga');
    expect(parsed.address, 'Jalan Melati · No. 7 · RT 01 · RW 05');
    expect(parsed.responseDueAt, isNull);
    expect(parsed.completionDueAt, isNull);
    expect(parsed.respondedAt, isNull);
  });

  testWidgets('RT manager can open a ticket and update its status',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _FakeTicketManagementGateway([ticket]);

    await tester.pumpWidget(MaterialApp(
      theme: WesbarTheme.light,
      home: TicketManagementPage(profile: rtManager, gateway: gateway),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Tiket wilayah'), findsOneWidget);
    expect(find.textContaining('Ani Warga'), findsOneWidget);
    await tester.tap(find.byKey(const Key('managed_ticket_ticket-1')));
    await tester.pumpAndSettle();

    expect(find.text('Target SLA belum ditetapkan'), findsOneWidget);
    expect(find.text('Riwayat tiket'), findsOneWidget);
    final updateButton = find.byKey(const Key('ticket_status_ditugaskan'));
    await tester.ensureVisible(updateButton);
    await tester.tap(updateButton);
    await tester.pumpAndSettle();

    expect(gateway.updatedStatus, 'ditugaskan');
    expect(find.text('Tiket wilayah'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('RT manager records a reason when escalating to RW',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _FakeTicketManagementGateway([ticket]);

    await tester.pumpWidget(MaterialApp(
      theme: WesbarTheme.light,
      home: TicketManagementPage(profile: rtManager, gateway: gateway),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('managed_ticket_ticket-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ticket_escalate')));
    await tester.pumpAndSettle();
    expect(find.text('Eskalasi tiket ke RW?'), findsOneWidget);
    final submitButton = find.widgetWithText(FilledButton, 'Eskalasi');
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);
    final reasonField = find.byKey(const Key('ticket_escalation_reason'));
    await tester.enterText(reasonField, 'Perlu penanganan fasilitas RW.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eskalasi'));
    await tester.pumpAndSettle();

    expect(gateway.escalated, isTrue);
    expect(gateway.escalationReason, 'Perlu penanganan fasilitas RW.');
    expect(find.text('Tiket wilayah'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
