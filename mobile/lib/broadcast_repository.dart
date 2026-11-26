import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class BroadcastAnnouncement {
  const BroadcastAnnouncement({
    required this.id,
    required this.kind,
    required this.audience,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.sentAt,
    this.readAt,
  });

  final String id;
  final String kind;
  final String audience;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime? readAt;

  factory BroadcastAnnouncement.fromJson(Map<String, dynamic> json) =>
      BroadcastAnnouncement(
        id: json['id'] as String,
        kind: json['jenis'] as String,
        audience: json['audiens'] as String,
        title: json['judul'] as String,
        content: json['isi'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        sentAt: json['terkirim_at'] == null
            ? null
            : DateTime.parse(json['terkirim_at'] as String),
        readAt: json['dibaca_at'] == null
            ? null
            : DateTime.parse(json['dibaca_at'] as String),
      );
}

class BroadcastRt {
  const BroadcastRt({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;

  factory BroadcastRt.fromJson(Map<String, dynamic> json) => BroadcastRt(
        id: json['id'] as String,
        code: json['kode'] as String,
        name: json['nama'] as String,
      );
}

class BroadcastSubmission {
  const BroadcastSubmission({required this.id, required this.recipientCount});

  final String id;
  final int recipientCount;
}

abstract interface class BroadcastGateway {
  Future<List<BroadcastAnnouncement>> received(String profileId);
  Future<List<BroadcastAnnouncement>> sent(String profileId);
  Future<List<BroadcastRt>> availableRts();
  Future<BroadcastSubmission> publish({
    required String kind,
    required String audience,
    String? targetRtId,
    String? targetRole,
    required String title,
    required String content,
  });
  Future<void> markRead(String announcementId, String profileId);
  Stream<void> watchChanges(String profileId);
  Future<void> dispose();
}

class SupabaseBroadcastGateway implements BroadcastGateway {
  SupabaseBroadcastGateway(this.client);

  final SupabaseClient client;
  RealtimeChannel? _channel;
  StreamController<void>? _changes;

  String get _userId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('Sesi sudah berakhir. Silakan masuk kembali.');
    return id;
  }

  static const _announcementFields =
      'id, jenis, audiens, judul, isi, created_at, terkirim_at';

  @override
  Future<List<BroadcastAnnouncement>> received(String profileId) async {
    if (profileId != _userId) throw StateError('Profil tidak sesuai dengan sesi aktif.');
    final assignments = await client
        .from('pengumuman_penerima')
        .select('pengumuman_id, dibaca_at')
        .eq('profile_id', profileId);
    if (assignments.isEmpty) return [];

    final readAtById = <String, dynamic>{
      for (final assignment in assignments)
        assignment['pengumuman_id'] as String: assignment['dibaca_at'],
    };
    final rows = await client
        .from('pengumuman')
        .select(_announcementFields)
        .inFilter('id', readAtById.keys.toList())
        .not('terkirim_at', 'is', null)
        .order('terkirim_at', ascending: false);
    return rows
        .map((row) => BroadcastAnnouncement.fromJson({
              ...row,
              'dibaca_at': readAtById[row['id'] as String],
            }))
        .toList();
  }

  @override
  Future<List<BroadcastAnnouncement>> sent(String profileId) async {
    if (profileId != _userId) throw StateError('Profil tidak sesuai dengan sesi aktif.');
    final rows = await client
        .from('pengumuman')
        .select(_announcementFields)
        .eq('penulis_id', profileId)
        .not('terkirim_at', 'is', null)
        .order('terkirim_at', ascending: false);
    return rows.map(BroadcastAnnouncement.fromJson).toList();
  }

  @override
  Future<List<BroadcastRt>> availableRts() async {
    final rows = await client.from('rt').select('id, kode, nama').order('kode');
    return rows.map(BroadcastRt.fromJson).toList();
  }

  @override
  Future<BroadcastSubmission> publish({
    required String kind,
    required String audience,
    String? targetRtId,
    String? targetRole,
    required String title,
    required String content,
  }) async {
    final response = await client.functions.invoke(
      'broadcast-publish',
      body: {
        'jenis': kind,
        'audiens': audience,
        'target_rt_id': targetRtId,
        'target_peran': targetRole,
        'judul': title,
        'isi': content,
      },
    );
    final body = Map<String, dynamic>.from(response.data as Map);
    final result = Map<String, dynamic>.from(body['announcement'] as Map);
    return BroadcastSubmission(
      id: result['announcement_id'] as String,
      recipientCount: (result['recipient_count'] as num).toInt(),
    );
  }

  @override
  Future<void> markRead(String announcementId, String profileId) async {
    if (profileId != _userId) throw StateError('Profil tidak sesuai dengan sesi aktif.');
    await client
        .from('pengumuman_penerima')
        .update({'dibaca_at': DateTime.now().toUtc().toIso8601String()})
        .eq('pengumuman_id', announcementId)
        .eq('profile_id', profileId)
        .isFilter('dibaca_at', null);
  }

  @override
  Stream<void> watchChanges(String profileId) {
    _changes?.close();
    _changes = StreamController<void>.broadcast();
    _channel = client
        .channel('broadcast-$profileId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pengumuman',
          callback: (_) => _changes?.add(null),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pengumuman_penerima',
          callback: (_) => _changes?.add(null),
        )
        .subscribe();
    return _changes!.stream;
  }

  @override
  Future<void> dispose() async {
    if (_channel != null) await client.removeChannel(_channel!);
    await _changes?.close();
  }
}
