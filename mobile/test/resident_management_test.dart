import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesbar/m0_repository.dart';
import 'package:wesbar/resident_pages.dart';
import 'package:wesbar/resident_repository.dart';

class _FakeResidentGateway implements ResidentManagementGateway {
  _FakeResidentGateway({required this.residentsData, required this.housesData});

  final List<ManagedResident> residentsData;
  final List<ResidentHouse> housesData;
  String? residentsRtId;
  String? housesRtId;
  ManagedResident? updatedResident;
  String? updatedName;
  ResidentHouse? updatedHouse;

  @override
  Future<List<ManagedResident>> residents({String? rtId}) async {
    residentsRtId = rtId;
    return residentsData;
  }

  @override
  Future<List<ResidentHouse>> houses({String? rtId}) async {
    housesRtId = rtId;
    return housesData;
  }

  @override
  Future<void> updateResident({
    required ManagedResident resident,
    required String name,
    required ResidentHouse house,
  }) async {
    updatedResident = resident;
    updatedName = name;
    updatedHouse = house;
  }
}

void main() {
  const rtProfile = ResidentProfile(
    id: 'rt-1',
    name: 'Pengurus RT',
    role: 'pengurus_rt',
    verificationStatus: 'terverifikasi',
    rtId: 'rt-01',
  );
  const residents = [
    ManagedResident(
      id: 'resident-1',
      name: 'Ani Warga',
      rtId: 'rt-01',
      unitId: 'unit-7',
      verificationStatus: 'terverifikasi',
      address: 'Melati · No. 7 · RT 01 · RW 05',
    ),
  ];
  const houses = [
    ResidentHouse(
      id: 'unit-7',
      rtId: 'rt-01',
      rwCode: '05',
      rtCode: '01',
      streetName: 'Melati',
      number: '7',
    ),
    ResidentHouse(
      id: 'unit-8',
      rtId: 'rt-01',
      rwCode: '05',
      rtCode: '01',
      streetName: 'Melati',
      number: '8',
    ),
  ];

  test('resident profile address includes street, RT, and RW', () {
    final profile = ResidentProfile.fromJson({
      'id': 'resident-1',
      'full_name': 'Ani Warga',
      'role': 'warga',
      'rt_id': 'rt-01',
      'unit_id': 'unit-7',
      'verification_status': 'terverifikasi',
      'unit': {
        'nomor': '7',
        'jalan': {'nama': 'Melati'},
        'rt': {
          'kode': '01',
          'rw': {'kode': '05'},
        },
      },
    });

    expect(profile.address, 'Melati No. 7 · RT 01 · RW 05');
  });

  test('resident and house addresses include their RW relationship', () {
    final resident = ManagedResident.fromJson({
      'id': 'resident-1',
      'full_name': 'Ani Warga',
      'rt_id': 'rt-01',
      'unit_id': 'unit-7',
      'verification_status': 'terverifikasi',
      'unit': {
        'nomor': '7',
        'jalan': {'nama': 'Melati'},
        'rt': {
          'kode': '01',
          'rw': {'kode': '05'},
        },
      },
    });
    final house = ResidentHouse.fromJson({
      'id': 'unit-7',
      'rt_id': 'rt-01',
      'nomor': '7',
      'jalan': {'nama': 'Melati'},
      'rt': {
        'kode': '01',
        'rw': {'kode': '05'},
      },
    });

    expect(resident.address, 'Melati · No. 7 · RT 01 · RW 05');
    expect(house.label, 'Melati No. 7 · RT 01 · RW 05');
  });

  testWidgets('RT can edit a resident only using its scoped houses',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _FakeResidentGateway(
      residentsData: residents,
      housesData: houses,
    );

    await tester.pumpWidget(MaterialApp(
      home: ResidentManagementPage(profile: rtProfile, gateway: gateway),
    ));
    await tester.pumpAndSettle();

    expect(gateway.residentsRtId, 'rt-01');
    expect(gateway.housesRtId, 'rt-01');
    expect(find.text('Ani Warga'), findsOneWidget);
    expect(find.text('Melati · No. 7 · RT 01 · RW 05'), findsOneWidget);

    await tester.tap(find.byTooltip('Ubah data Ani Warga'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('resident_name_input')),
      'Ani Warga Baru',
    );
    await tester.tap(find.byKey(const Key('resident_house_input')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Melati No. 8 · RT 01 · RW 05').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan perubahan'));
    await tester.pumpAndSettle();

    expect(gateway.updatedResident?.id, 'resident-1');
    expect(gateway.updatedName, 'Ani Warga Baru');
    expect(gateway.updatedHouse?.id, 'unit-8');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('admin loads resident and house data without an RT restriction',
      (tester) async {
    const adminProfile = ResidentProfile(
      id: 'admin-1',
      name: 'Admin',
      role: 'admin',
      verificationStatus: 'terverifikasi',
    );
    final gateway = _FakeResidentGateway(
      residentsData: residents,
      housesData: houses,
    );

    await tester.pumpWidget(MaterialApp(
      home: ResidentManagementPage(profile: adminProfile, gateway: gateway),
    ));
    await tester.pumpAndSettle();

    expect(gateway.residentsRtId, isNull);
    expect(gateway.housesRtId, isNull);
    expect(find.text('Ani Warga'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
