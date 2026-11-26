import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class PanicTypes {
  static const values = ['keamanan', 'kebakaran', 'medis', 'lainnya'];
  const PanicTypes._();
}

class PanicSubmission {
  const PanicSubmission({
    required this.queued,
    this.incidentId,
    this.message,
  });

  final bool queued;
  final String? incidentId;
  final String? message;
}

class EmergencyContact {
  const EmergencyContact({
    required this.name,
    required this.phone,
    this.type,
  });

  final String name;
  final String phone;
  final String? type;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) => EmergencyContact(
        name: json['nama'] as String,
        phone: json['nomor_telepon'] as String,
        type: json['jenis'] as String?,
      );
}

class IncidentSummary {
  const IncidentSummary({
    required this.id,
    required this.kind,
    required this.status,
    required this.location,
    required this.createdAt,
    this.escalatedAt,
    this.reporterId,
    this.recipientResponse,
  });

  final String id;
  final String kind;
  final String status;
  final String location;
  final DateTime createdAt;
  final DateTime? escalatedAt;
  final String? reporterId;
  final String? recipientResponse;

  factory IncidentSummary.fromJson(Map<String, dynamic> json) => IncidentSummary(
        id: json['id'] as String,
        kind: json['jenis'] as String,
        status: json['status'] as String,
        location: json['lokasi'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        escalatedAt: json['eskalasi_at'] == null
            ? null
            : DateTime.parse(json['eskalasi_at'] as String),
        reporterId: json['pelapor_id'] as String?,
        recipientResponse: json['recipient_response'] as String?,
      );
}

abstract interface class PanicGateway {
  Future<PanicSubmission> send(String kind);
  Future<int> retryPending();
  Future<List<EmergencyContact>> contacts(String rtId);
  Future<List<IncidentSummary>> myActiveIncidents(String profileId);
  Future<List<IncidentSummary>> incomingIncidents(String profileId);
  Future<List<IncidentSummary>> activeIncidents();
  Future<int> responders(String incidentId);
  Future<void> respond(String incidentId, String response);
  Future<void> updateStatus(String incidentId, String status);
  Stream<void> watchChanges(String profileId);
  Future<void> dispose();
}

class SupabasePanicGateway implements PanicGateway {
  SupabasePanicGateway(this.client);

  static const _uuid = Uuid();
  final SupabaseClient client;
  bool _retrying = false;
  RealtimeChannel? _channel;
  StreamController<void>? _changes;

  String get _userId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('Sesi sudah berakhir. Silakan masuk kembali.');
    return id;
  }

  String get _queueKey => 'wesbar.panic.outbox.$_userId';

  @override
  Future<PanicSubmission> send(String kind) async {
    if (!PanicTypes.values.contains(kind)) throw ArgumentError.value(kind, 'kind');
    return _dispatch({'request_id': _uuid.v4(), 'jenis': kind});
  }

  Future<PanicSubmission> _dispatch(Map<String, String> item) async {
    try {
      final response = await client.functions.invoke(
        'panic-create',
        body: {
          'request_id': item['request_id'],
          'jenis': item['jenis'],
          'is_latihan': false,
        },
      );
      final body = Map<String, dynamic>.from(response.data as Map);
      final incident = Map<String, dynamic>.from(body['incident'] as Map);
      return PanicSubmission(
        queued: false,
        incidentId: incident['incident_id'] as String?,
        message: 'Alert diterima server dan penerima sudah ditentukan.',
      );
    } on FunctionException catch (error) {
      if (error.status >= 500) {
        await _enqueue(item);
        return const PanicSubmission(queued: true, message: 'Server belum merespons. Alert disimpan untuk dikirim ulang.');
      }
      throw StateError(_functionErrorMessage(error.details));
    } catch (error) {
      if (error is StateError || error is ArgumentError) rethrow;
      await _enqueue(item);
      return const PanicSubmission(queued: true, message: 'Koneksi belum tersedia. Alert disimpan untuk dikirim ulang.');
    }
  }

  String _functionErrorMessage(dynamic details) {
    if (details is Map && details['error'] is String) return details['error'] as String;
    return 'Permintaan alert ditolak server.';
  }

  Future<void> _enqueue(Map<String, String> item) async {
    final preferences = await SharedPreferences.getInstance();
    final queue = preferences.getStringList(_queueKey) ?? <String>[];
    final id = item['request_id'];
    if (queue.any((entry) => (jsonDecode(entry) as Map)['request_id'] == id)) return;
    queue.add(jsonEncode(item));
    await preferences.setStringList(_queueKey, queue);
  }

  @override
  Future<int> retryPending() async {
    if (_retrying || client.auth.currentUser == null) return 0;
    _retrying = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final queue = preferences.getStringList(_queueKey) ?? <String>[];
      var sent = 0;
      for (final entry in queue) {
        final item = Map<String, String>.from(jsonDecode(entry) as Map);
        try {
          final response = await client.functions.invoke(
            'panic-create',
            body: {
              'request_id': item['request_id'],
              'jenis': item['jenis'],
              'is_latihan': false,
            },
          );
          if (response.status >= 200 && response.status < 300) {
            queue.remove(entry);
            sent++;
          }
        } on FunctionException catch (error) {
          if (error.status >= 400 && error.status < 500) queue.remove(entry);
        } catch (_) {
          break;
        }
      }
      await preferences.setStringList(_queueKey, queue);
      return sent;
    } finally {
      _retrying = false;
    }
  }

  @override
  Future<List<EmergencyContact>> contacts(String rtId) async {
    final rows = await client
        .from('kontak_darurat')
        .select('nama, nomor_telepon, jenis')
        .eq('aktif', true)
        .or('rt_id.eq.$rtId,rt_id.is.null')
        .order('nama');
    return rows.map(EmergencyContact.fromJson).toList();
  }

  @override
  Future<List<IncidentSummary>> myActiveIncidents(String profileId) async {
    final rows = await client
        .from('insiden')
        .select('id, pelapor_id, jenis, status, lokasi, created_at, eskalasi_at')
        .eq('pelapor_id', profileId)
        .inFilter('status', ['aktif', 'ditangani'])
        .order('created_at', ascending: false);
    return rows.map(IncidentSummary.fromJson).toList();
  }

  @override
  Future<List<IncidentSummary>> incomingIncidents(String profileId) async {
    final assignments = await client
        .from('insiden_penerima')
        .select('insiden_id, respons')
        .eq('profile_id', profileId);
    if (assignments.isEmpty) return [];

    final responses = <String, String>{
      for (final assignment in assignments)
        assignment['insiden_id'] as String: assignment['respons'] as String,
    };
    final rows = await client
        .from('insiden')
        .select('id, pelapor_id, jenis, status, lokasi, created_at, eskalasi_at')
        .inFilter('id', responses.keys.toList())
        .inFilter('status', ['aktif', 'ditangani'])
        .order('created_at', ascending: false);
    return rows.map((row) => IncidentSummary.fromJson({
          ...row,
          'recipient_response': responses[row['id'] as String],
        })).toList();
  }

  @override
  Future<List<IncidentSummary>> activeIncidents() async {
    final rows = await client
        .from('insiden')
        .select('id, pelapor_id, jenis, status, lokasi, created_at, eskalasi_at')
        .inFilter('status', ['aktif', 'ditangani'])
        .order('created_at', ascending: false);
    return rows.map(IncidentSummary.fromJson).toList();
  }

  @override
  Future<int> responders(String incidentId) async {
    final rows = await client
        .from('insiden_penerima')
        .select('id')
        .eq('insiden_id', incidentId)
        .eq('respons', 'menuju');
    return rows.length;
  }

  @override
  Future<void> respond(String incidentId, String response) async {
    if (!const ['menuju', 'tidak_bisa'].contains(response)) {
      throw ArgumentError.value(response, 'response');
    }
    final updated = await client
        .from('insiden_penerima')
        .update({'respons': response})
        .eq('insiden_id', incidentId)
        .eq('profile_id', _userId)
        .eq('respons', 'menunggu')
        .select('id');
    if (updated.isEmpty) throw StateError('Respons tidak tersedia atau sudah dikirim.');
  }

  @override
  Future<void> updateStatus(String incidentId, String status) async {
    if (!const ['ditangani', 'selesai', 'alarm_palsu'].contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final updated = await client
        .from('insiden')
        .update({'status': status})
        .eq('id', incidentId)
        .select('id');
    if (updated.isEmpty) throw StateError('Insiden tidak ditemukan atau tidak dapat diubah.');
  }

  @override
  Stream<void> watchChanges(String profileId) {
    _changes?.close();
    _changes = StreamController<void>.broadcast();
    _channel = client
        .channel('panic-$profileId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'insiden',
          callback: (_) => _changes?.add(null),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'insiden_penerima',
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
