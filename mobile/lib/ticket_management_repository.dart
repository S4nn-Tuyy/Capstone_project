import 'package:supabase_flutter/supabase_flutter.dart';

import 'm0_repository.dart';
import 'ticket_repository.dart';

class ManagedTicket {
  const ManagedTicket({
    required this.id,
    required this.reporterName,
    required this.rtId,
    required this.category,
    required this.priority,
    required this.level,
    required this.status,
    required this.description,
    required this.address,
    required this.createdAt,
    this.photoPath,
    this.responseDueAt,
    this.completionDueAt,
  });

  final String id;
  final String reporterName;
  final String rtId;
  final String category;
  final String priority;
  final String level;
  final String status;
  final String description;
  final String address;
  final DateTime createdAt;
  final String? photoPath;
  final DateTime? responseDueAt;
  final DateTime? completionDueAt;

  factory ManagedTicket.fromJson(Map<String, dynamic> json) {
    final reporter = json['pelapor'] as Map<String, dynamic>?;
    final unit = json['unit'] as Map<String, dynamic>?;
    final road = unit?['jalan'] as Map<String, dynamic>?;
    final rt = json['rt'] as Map<String, dynamic>?;
    final rw = rt?['rw'] as Map<String, dynamic>?;
    final addressParts = [
      if (road?['nama'] is String) road!['nama'] as String,
      if (unit?['nomor'] is String) 'No. ${unit!['nomor']}',
      if (rt?['kode'] is String) 'RT ${rt!['kode']}',
      if (rw?['kode'] is String) 'RW ${rw!['kode']}',
    ];

    return ManagedTicket(
      id: json['id'] as String,
      reporterName:
          reporter?['full_name'] as String? ?? 'Warga tidak diketahui',
      rtId: json['rt_id'] as String,
      category: json['kategori'] as String,
      priority: json['prioritas'] as String,
      level: json['level'] as String,
      status: json['status'] as String,
      description: json['deskripsi'] as String,
      address: addressParts.isEmpty
          ? 'Alamat tidak tersedia'
          : addressParts.join(' · '),
      createdAt: DateTime.parse(json['created_at'] as String),
      photoPath: json['foto_path'] as String?,
      responseDueAt: _parseDate(json['tenggat_respons_at']),
      completionDueAt: _parseDate(json['tenggat_selesai_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) =>
      value is String ? DateTime.parse(value) : null;
}

class TicketHistoryEvent {
  const TicketHistoryEvent({
    required this.action,
    required this.createdAt,
    this.statusBefore,
    this.statusAfter,
    this.levelBefore,
    this.levelAfter,
    this.actorName,
    this.note,
  });

  final String action;
  final DateTime createdAt;
  final String? statusBefore;
  final String? statusAfter;
  final String? levelBefore;
  final String? levelAfter;
  final String? actorName;
  final String? note;

  factory TicketHistoryEvent.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] as Map<String, dynamic>?;
    return TicketHistoryEvent(
      action: json['aksi'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      statusBefore: json['status_sebelum'] as String?,
      statusAfter: json['status_sesudah'] as String?,
      levelBefore: json['level_sebelum'] as String?,
      levelAfter: json['level_sesudah'] as String?,
      actorName: actor?['full_name'] as String?,
      note: json['catatan'] as String?,
    );
  }
}

abstract interface class TicketManagementGateway {
  Future<List<ManagedTicket>> tickets(ResidentProfile profile);
  Future<List<TicketHistoryEvent>> history(
    ResidentProfile profile,
    String ticketId,
  );
  Future<void> updateStatus({
    required ResidentProfile profile,
    required String ticketId,
    required String status,
  });
  Future<void> escalate({
    required ResidentProfile profile,
    required String ticketId,
    required String reason,
  });
  Future<String> signedPhotoUrl(String path);
}

class SupabaseTicketManagementGateway implements TicketManagementGateway {
  SupabaseTicketManagementGateway(this.client);

  static const bucket = SupabaseTicketGateway.bucket;
  static const photoExpirySeconds = SupabaseTicketGateway.photoExpirySeconds;
  static const _ticketSelect = 'id, pelapor_id, rt_id, unit_id, kategori, '
      'prioritas, level, status, deskripsi, foto_path, tenggat_respons_at, '
      'tenggat_selesai_at, created_at, '
      'pelapor:profiles!tiket_pelapor_id_fkey(full_name), '
      'unit:unit_rumah!tiket_unit_id_fkey('
      'nomor, jalan:jalan!unit_rumah_jalan_id_fkey(nama)), '
      'rt:rt!tiket_rt_id_fkey(kode, rw:rw!rt_rw_id_fkey(kode))';
  static const _historySelect = 'aksi, status_sebelum, status_sesudah, '
      'level_sebelum, level_sesudah, catatan, created_at, '
      'actor:profiles!tiket_riwayat_actor_id_fkey(full_name)';
  static const _statuses = {
    'baru',
    'ditugaskan',
    'diproses',
    'selesai',
    'ditutup',
  };

  final SupabaseClient client;

  void _requireManager(ResidentProfile profile) {
    final currentUserId = client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != profile.id) {
      throw StateError('Sesi pengurus tidak valid. Silakan masuk kembali.');
    }
    if (!const ['pengurus_rt', 'pengurus_rw', 'admin'].contains(profile.role)) {
      throw StateError('Akses pengelolaan tiket tidak tersedia.');
    }
    if (profile.role == 'pengurus_rt' && profile.rtId == null) {
      throw StateError('Akun pengurus RT belum memiliki wilayah.');
    }
  }

  @override
  Future<List<ManagedTicket>> tickets(ResidentProfile profile) async {
    _requireManager(profile);
    var query = client.from('tiket').select(_ticketSelect);
    if (profile.role == 'pengurus_rt') {
      query = query.eq('rt_id', profile.rtId!);
    }
    final rows = await query.order('created_at', ascending: false);
    return rows.map(ManagedTicket.fromJson).toList();
  }

  @override
  Future<List<TicketHistoryEvent>> history(
    ResidentProfile profile,
    String ticketId,
  ) async {
    _requireManager(profile);
    final rows = await client
        .from('tiket_riwayat')
        .select(_historySelect)
        .eq('tiket_id', ticketId)
        .order('created_at');
    return rows.map(TicketHistoryEvent.fromJson).toList();
  }

  @override
  Future<void> updateStatus({
    required ResidentProfile profile,
    required String ticketId,
    required String status,
  }) async {
    _requireManager(profile);
    if (!_statuses.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final row = await client
        .from('tiket')
        .update({'status': status})
        .eq('id', ticketId)
        .select('id')
        .maybeSingle();
    if (row == null) {
      throw StateError('Tiket tidak ditemukan atau akses pengurus ditolak.');
    }
  }

  @override
  Future<void> escalate({
    required ResidentProfile profile,
    required String ticketId,
    required String reason,
  }) async {
    _requireManager(profile);
    if (!const ['pengurus_rt', 'admin'].contains(profile.role)) {
      throw StateError('Hanya pengurus RT atau admin yang dapat mengeskalasi.');
    }
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty || normalizedReason.length > 1000) {
      throw ArgumentError.value(reason, 'reason');
    }
    final row = await client
        .from('tiket')
        .update({'level': 'rw', 'alasan_eskalasi': normalizedReason})
        .eq('id', ticketId)
        .eq('level', 'rt')
        .select('id')
        .maybeSingle();
    if (row == null) {
      throw StateError('Tiket sudah dieskalasi atau akses ditolak.');
    }
  }

  @override
  Future<String> signedPhotoUrl(String path) =>
      client.storage.from(bucket).createSignedUrl(path, photoExpirySeconds);
}
