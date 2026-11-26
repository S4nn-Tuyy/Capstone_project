import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wesbar/m0_repository.dart';
import 'package:wesbar/ticket_pages.dart';
import 'package:wesbar/ticket_repository.dart';

class _FakeTicketGateway implements TicketGateway {
  List<ResidentTicket> tickets = [];
  String? createdCategory;
  String? createdDescription;
  ResidentProfile? createdBy;
  XFile? createdPhoto;

  @override
  Future<List<ResidentTicket>> myTickets(String profileId) async => tickets;

  @override
  Future<void> createTicket({
    required ResidentProfile profile,
    required String category,
    required String description,
    XFile? photo,
  }) async {
    createdBy = profile;
    createdCategory = category;
    createdDescription = description;
    createdPhoto = photo;
    tickets = [
      ResidentTicket(
        id: 'ticket-1',
        category: category,
        description: description,
        status: 'baru',
        createdAt: DateTime.utc(2026, 11, 19),
        address: 'Jalan Melati No. 7 · RT 01 · RW 05',
        photoPath: photo == null ? null : 'resident-1/ticket-1/foto.png',
      ),
    ];
  }

  @override
  Future<String> signedPhotoUrl(String path) async =>
      'https://example.test/$path';
}

void main() {
  const resident = ResidentProfile(
    id: 'resident-1',
    name: 'Ani Warga',
    role: 'warga',
    verificationStatus: 'terverifikasi',
    rtId: 'rt-01',
    unitId: 'unit-7',
    address: 'Jalan Melati No. 7 · RT 01 · RW 05',
  );

  testWidgets('resident can create a ticket with category and description',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _FakeTicketGateway();

    await tester.pumpWidget(MaterialApp(
      home: ResidentTicketsPage(profile: resident, gateway: gateway),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Belum ada tiket.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ticket_create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ticket_description')),
      'Lampu jalan di depan rumah mati.',
    );
    await tester.tap(find.byKey(const Key('ticket_submit')));
    await tester.pumpAndSettle();

    expect(gateway.createdBy?.id, resident.id);
    expect(gateway.createdCategory, 'fasilitas');
    expect(gateway.createdDescription, 'Lampu jalan di depan rumah mati.');
    expect(gateway.createdPhoto, isNull);
    expect(find.byKey(const Key('ticket_ticket-1')), findsOneWidget);
    expect(find.text('Baru'), findsOneWidget);
    expect(find.textContaining('RW 05'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resident can attach an optional photo before submission',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _FakeTicketGateway();
    final image = XFile.fromData(
      Uint8List.fromList([1, 2, 3]),
      name: 'bukti.png',
      path: 'bukti.png',
      mimeType: 'image/png',
    );
    await tester.pumpWidget(MaterialApp(
      home: ResidentTicketsPage(
        profile: resident,
        gateway: gateway,
        pickImage: () async => image,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ticket_create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ticket_description')),
      'Perlu pemeriksaan fasilitas.',
    );
    await tester.tap(find.byKey(const Key('ticket_add_photo')));
    await tester.pumpAndSettle();

    expect(find.text('bukti.png'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ticket_submit')));
    await tester.pumpAndSettle();

    expect(gateway.createdPhoto?.name, 'bukti.png');
    expect(find.textContaining('Foto terlampir'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
