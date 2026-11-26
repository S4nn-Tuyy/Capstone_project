import 'package:supabase_flutter/supabase_flutter.dart';

class ManagedResident {
  const ManagedResident({
    required this.id,
    required this.name,
    required this.rtId,
    required this.unitId,
    required this.verificationStatus,
    required this.address,
  });

  final String id;
  final String name;
  final String rtId;
  final String unitId;
  final String verificationStatus;
  final String address;

  factory ManagedResident.fromJson(Map<String, dynamic> json) {
    final unit = json['unit'] as Map<String, dynamic>?;
    final road = unit?['jalan'] as Map<String, dynamic>?;
    final rt = unit?['rt'] as Map<String, dynamic>?;
    final rw = rt?['rw'] as Map<String, dynamic>?;
    final roadName = road?['nama'] as String?;
    final houseNumber = unit?['nomor'] as String?;
    final rtCode = rt?['kode'] as String?;
    final rwCode = rw?['kode'] as String?;
    final addressParts = [
      if (roadName != null && roadName.isNotEmpty) roadName,
      if (houseNumber != null && houseNumber.isNotEmpty) 'No. $houseNumber',
      if (rtCode != null && rtCode.isNotEmpty) 'RT $rtCode',
      if (rwCode != null && rwCode.isNotEmpty) 'RW $rwCode',
    ];

    return ManagedResident(
      id: json['id'] as String,
      name: json['full_name'] as String,
      rtId: json['rt_id'] as String,
      unitId: json['unit_id'] as String,
      verificationStatus: json['verification_status'] as String,
      address: addressParts.isEmpty
          ? 'Alamat belum tersedia'
          : addressParts.join(' · '),
    );
  }
}

class ResidentHouse {
  const ResidentHouse({
    required this.id,
    required this.rtId,
    required this.rwCode,
    required this.rtCode,
    required this.streetName,
    required this.number,
  });

  final String id;
  final String rtId;
  final String rwCode;
  final String rtCode;
  final String streetName;
  final String number;

  String get label => '$streetName No. $number · RT $rtCode · RW $rwCode';

  factory ResidentHouse.fromJson(Map<String, dynamic> json) {
    final road = json['jalan'] as Map<String, dynamic>?;
    final rt = json['rt'] as Map<String, dynamic>?;
    final rw = rt?['rw'] as Map<String, dynamic>?;
    return ResidentHouse(
      id: json['id'] as String,
      rtId: json['rt_id'] as String,
      rwCode: rw?['kode'] as String? ?? '—',
      rtCode: rt?['kode'] as String? ?? '—',
      streetName: road?['nama'] as String? ?? 'Jalan tidak diketahui',
      number: json['nomor'] as String,
    );
  }
}

abstract interface class ResidentManagementGateway {
  Future<List<ManagedResident>> residents({String? rtId});
  Future<List<ResidentHouse>> houses({String? rtId});
  Future<void> updateResident({
    required ManagedResident resident,
    required String name,
    required ResidentHouse house,
  });
}

class SupabaseResidentManagementGateway implements ResidentManagementGateway {
  const SupabaseResidentManagementGateway(this.client);

  final SupabaseClient client;

  static const _residentSelect = 'id, full_name, role, rt_id, unit_id, '
      'verification_status, unit:unit_rumah!profiles_unit_id_fkey('
      'nomor, jalan:jalan!unit_rumah_jalan_id_fkey(nama), '
      'rt:rt!unit_rumah_rt_id_fkey(kode, rw:rw!rt_rw_id_fkey(kode)))';

  static const _houseSelect = 'id, nomor, rt_id, '
      'jalan:jalan!unit_rumah_jalan_id_fkey(nama), '
      'rt:rt!unit_rumah_rt_id_fkey(kode, rw:rw!rt_rw_id_fkey(kode))';

  @override
  Future<List<ManagedResident>> residents({String? rtId}) async {
    final baseQuery =
        client.from('profiles').select(_residentSelect).eq('role', 'warga');
    final rows = rtId == null
        ? await baseQuery.order('full_name')
        : await baseQuery.eq('rt_id', rtId).order('full_name');
    return rows.map(ManagedResident.fromJson).toList();
  }

  @override
  Future<List<ResidentHouse>> houses({String? rtId}) async {
    final baseQuery = client.from('unit_rumah').select(_houseSelect);
    final rows = rtId == null
        ? await baseQuery.order('rt_id').order('nomor')
        : await baseQuery.eq('rt_id', rtId).order('nomor');
    return rows.map(ResidentHouse.fromJson).toList();
  }

  @override
  Future<void> updateResident({
    required ManagedResident resident,
    required String name,
    required ResidentHouse house,
  }) async {
    final changed = await client
        .from('profiles')
        .update({
          'full_name': name.trim(),
          'unit_id': house.id,
          'rt_id': house.rtId,
        })
        .eq('id', resident.id)
        .eq('rt_id', resident.rtId)
        .eq('role', 'warga')
        .select('id');

    if (changed.isEmpty) {
      throw StateError(
          'Data warga berubah atau sudah tidak dapat diperbarui. Muat ulang data.');
    }
  }
}
