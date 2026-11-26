import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'm0_repository.dart';

abstract final class TicketCategories {
  static const labels = {
    'fasilitas': 'Fasilitas',
    'keamanan': 'Keamanan',
    'hewan': 'Hewan',
    'listrik': 'Listrik',
  };
}

class ResidentTicket {
  const ResidentTicket({
    required this.id,
    required this.category,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.address,
    this.photoPath,
  });

  final String id;
  final String category;
  final String description;
  final String status;
  final DateTime createdAt;
  final String address;
  final String? photoPath;

  factory ResidentTicket.fromJson(Map<String, dynamic> json) {
    final unit = json['unit'] as Map<String, dynamic>?;
    final road = unit?['jalan'] as Map<String, dynamic>?;
    final rt = unit?['rt'] as Map<String, dynamic>?;
    final rw = rt?['rw'] as Map<String, dynamic>?;
    final addressParts = [
      if (road?['nama'] is String) road!['nama'] as String,
      if (unit?['nomor'] is String) 'No. ${unit!['nomor']}',
      if (rt?['kode'] is String) 'RT ${rt!['kode']}',
      if (rw?['kode'] is String) 'RW ${rw!['kode']}',
    ];
    return ResidentTicket(
      id: json['id'] as String,
      category: json['kategori'] as String,
      description: json['deskripsi'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      address: addressParts.isEmpty
          ? 'Alamat tidak tersedia'
          : addressParts.join(' · '),
      photoPath: json['foto_path'] as String?,
    );
  }
}

abstract interface class TicketGateway {
  Future<List<ResidentTicket>> myTickets(String profileId);
  Future<void> createTicket({
    required ResidentProfile profile,
    required String category,
    required String description,
    XFile? photo,
  });
  Future<String> signedPhotoUrl(String path);
}

class SupabaseTicketGateway implements TicketGateway {
  SupabaseTicketGateway(this.client);

  static const bucket = 'ticket-photos';
  static const maxPhotoBytes = 5 * 1024 * 1024;
  static const photoExpirySeconds = 600;
  static const _uuid = Uuid();
  static const _ticketSelect =
      'id, kategori, deskripsi, status, created_at, foto_path, '
      'unit:unit_rumah!tiket_unit_id_fkey('
      'nomor, jalan:jalan!unit_rumah_jalan_id_fkey(nama), '
      'rt:rt!unit_rumah_rt_id_fkey(kode, rw:rw!rt_rw_id_fkey(kode)))';

  final SupabaseClient client;

  @override
  Future<List<ResidentTicket>> myTickets(String profileId) async {
    final rows = await client
        .from('tiket')
        .select(_ticketSelect)
        .eq('pelapor_id', profileId)
        .order('created_at', ascending: false);
    return rows.map(ResidentTicket.fromJson).toList();
  }

  @override
  Future<void> createTicket({
    required ResidentProfile profile,
    required String category,
    required String description,
    XFile? photo,
  }) async {
    final currentUserId = client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != profile.id) {
      throw StateError('Sesi warga tidak valid. Silakan masuk kembali.');
    }
    if (profile.role != 'warga' ||
        profile.rtId == null ||
        profile.unitId == null) {
      throw StateError('Hanya warga terverifikasi yang dapat membuat tiket.');
    }
    if (!TicketCategories.labels.containsKey(category)) {
      throw ArgumentError.value(category, 'category');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError.value(description, 'description');
    }

    final ticketId = _uuid.v4();
    String? photoPath;
    try {
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        if (bytes.isEmpty || bytes.length > maxPhotoBytes) {
          throw StateError('Ukuran foto harus antara 1 byte dan 5 MB.');
        }
        final extension = _photoExtension(photo);
        photoPath = '$currentUserId/$ticketId/foto.$extension';
        await client.storage.from(bucket).uploadBinary(
              photoPath,
              bytes,
              fileOptions: FileOptions(
                contentType: _contentType(extension),
                upsert: false,
              ),
            );
      }

      await client.from('tiket').insert({
        'id': ticketId,
        'pelapor_id': currentUserId,
        'rt_id': profile.rtId,
        'unit_id': profile.unitId,
        'kategori': category,
        'deskripsi': description.trim(),
        if (photoPath != null) 'foto_path': photoPath,
      });
    } catch (_) {
      if (photoPath != null) {
        try {
          await client.storage.from(bucket).remove([photoPath]);
        } catch (_) {
          // Keep the original ticket error; storage cleanup is best-effort.
        }
      }
      rethrow;
    }
  }

  @override
  Future<String> signedPhotoUrl(String path) =>
      client.storage.from(bucket).createSignedUrl(path, photoExpirySeconds);

  String _photoExtension(XFile photo) {
    final mimeType = photo.mimeType?.toLowerCase();
    if (mimeType == 'image/jpeg' || mimeType == 'image/jpg') return 'jpg';
    if (mimeType == 'image/png') return 'png';
    if (mimeType == 'image/webp') return 'webp';

    final extension = photo.name.split('.').last.toLowerCase();
    if (const ['jpg', 'jpeg'].contains(extension)) return 'jpg';
    if (const ['png', 'webp'].contains(extension)) return extension;
    throw StateError('Format foto yang didukung: JPG, PNG, atau WebP.');
  }

  String _contentType(String extension) => switch (extension) {
        'jpg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => throw ArgumentError.value(extension, 'extension'),
      };
}
