import 'package:supabase_flutter/supabase_flutter.dart';

class ResidentProfile {
  const ResidentProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.verificationStatus,
    this.rtId,
    this.unitId,
    this.address,
  });

  final String id;
  final String name;
  final String role;
  final String verificationStatus;
  final String? rtId;
  final String? unitId;
  final String? address;

  bool get isVerified => verificationStatus == 'terverifikasi';

  factory ResidentProfile.fromJson(Map<String, dynamic> json) {
    final unit = json['unit'] as Map<String, dynamic>?;
    final street = unit?['jalan'] as Map<String, dynamic>?;
    final rt = unit?['rt'] as Map<String, dynamic>?;
    final rw = rt?['rw'] as Map<String, dynamic>?;
    final address = unit == null
        ? null
        : [
            '${street?['nama'] ?? 'Jalan tidak diketahui'} No. ${unit['nomor']}',
            if (rt?['kode'] != null) 'RT ${rt?['kode']}',
            if (rw?['kode'] != null) 'RW ${rw?['kode']}',
          ].join(' · ');
    return ResidentProfile(
      id: json['id'] as String,
      name: json['full_name'] as String,
      role: json['role'] as String,
      verificationStatus: json['verification_status'] as String,
      rtId: json['rt_id'] as String?,
      unitId: json['unit_id'] as String?,
      address: address,
    );
  }
}

class M0Repository {
  const M0Repository(this.client);

  final SupabaseClient client;

  User? get signedInUser => client.auth.currentUser;
  Stream<AuthState> get authChanges => client.auth.onAuthStateChange;

  Future<bool> signUp(String email, String password) async {
    final result = await client.auth.signUp(email: email, password: password);
    // With email confirmation enabled, onboarding happens after the user logs in.
    return result.session == null;
  }

  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => client.auth.signOut();

  Future<ResidentProfile?> getMyProfile() async {
    final user = signedInUser;
    if (user == null) return null;
    final row = await client
        .from('profiles')
        .select('id, full_name, role, rt_id, unit_id, verification_status, '
            'unit:unit_rumah!profiles_unit_id_fkey('
            'nomor, jalan:jalan!unit_rumah_jalan_id_fkey(nama), '
            'rt:rt!unit_rumah_rt_id_fkey(kode, rw:rw!rt_rw_id_fkey(kode)))')
        .eq('id', user.id)
        .maybeSingle();
    return row == null ? null : ResidentProfile.fromJson(row);
  }

  Future<void> registerResident({
    required String name,
    required String phone,
    required String rtCode,
    required String jalanName,
    required String houseNumber,
    required bool consent,
  }) async {
    final user = signedInUser;
    if (user == null) throw StateError('Masuk terlebih dahulu.');
    if (!consent) {
      throw StateError('Persetujuan penggunaan data wajib diberikan.');
    }

    // Exact-address lookup returns only internal IDs; unverified users cannot
    // list residents or all houses under the normal table RLS policies.
    final response = await client.rpc('resolve_registration_unit', params: {
      'p_rt_code': rtCode.trim(),
      'p_jalan_name': jalanName.trim(),
      'p_nomor': houseNumber.trim(),
    });
    if (response is! List || response.isEmpty) {
      throw StateError('Alamat tidak ditemukan. Hubungi pengurus RT.');
    }
    final unit = Map<String, dynamic>.from(response.first as Map);
    await client.from('profiles').insert({
      'id': user.id,
      'full_name': name.trim(),
      if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      'rt_id': unit['rt_id'],
      'unit_id': unit['unit_id'],
      'consented_at': DateTime.now().toUtc().toIso8601String(),
      // role and verification_status are set by the database, not the client.
    });
  }

  Future<List<ResidentProfile>> pendingResidents(String rtId) async {
    final rows = await client
        .from('profiles')
        .select('id, full_name, role, rt_id, unit_id, verification_status, '
            'unit:unit_rumah!profiles_unit_id_fkey('
            'nomor, jalan:jalan!unit_rumah_jalan_id_fkey(nama), '
            'rt:rt!unit_rumah_rt_id_fkey(kode, rw:rw!rt_rw_id_fkey(kode)))')
        .eq('rt_id', rtId)
        .eq('role', 'warga')
        .eq('verification_status', 'menunggu')
        .order('full_name');
    return rows.map(ResidentProfile.fromJson).toList();
  }

  Future<void> verifyResident({
    required String profileId,
    required String rtId,
    required bool approve,
  }) async {
    // RLS and guard_profile() enforce RT scope and pending-warga-only changes.
    final changed = await client
        .from('profiles')
        .update({'verification_status': approve ? 'terverifikasi' : 'ditolak'})
        .eq('id', profileId)
        .eq('rt_id', rtId)
        .eq('role', 'warga')
        .eq('verification_status', 'menunggu')
        .select('id');
    if (changed.isEmpty) {
      throw StateError('Akun tidak tersedia atau sudah diverifikasi.');
    }
  }
}
