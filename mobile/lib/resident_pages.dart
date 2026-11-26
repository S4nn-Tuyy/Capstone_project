import 'package:flutter/material.dart';

import 'm0_repository.dart';
import 'resident_repository.dart';

class ResidentManagementPage extends StatefulWidget {
  const ResidentManagementPage({
    super.key,
    required this.profile,
    required this.gateway,
  });

  final ResidentProfile profile;
  final ResidentManagementGateway gateway;

  @override
  State<ResidentManagementPage> createState() => _ResidentManagementPageState();
}

class _ResidentManagementPageState extends State<ResidentManagementPage> {
  late Future<_ResidentManagementData> _data;
  String _search = '';
  bool _saving = false;

  bool get _canManage =>
      widget.profile.role == 'admin' ||
      (widget.profile.role == 'pengurus_rt' && widget.profile.rtId != null);

  String? get _scopeRtId =>
      widget.profile.role == 'pengurus_rt' ? widget.profile.rtId : null;

  @override
  void initState() {
    super.initState();
    if (_canManage) _data = _loadData();
  }

  Future<_ResidentManagementData> _loadData() async {
    final scopeRtId = _scopeRtId;
    final residents = await widget.gateway.residents(rtId: scopeRtId);
    final houses = await widget.gateway.houses(rtId: scopeRtId);
    return _ResidentManagementData(residents: residents, houses: houses);
  }

  void _reload() {
    if (!_canManage) return;
    setState(() => _data = _loadData());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Data warga'),
          actions: [
            if (_canManage)
              IconButton(
                tooltip: 'Muat ulang data',
                onPressed: _saving ? null : _reload,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: !_canManage
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child:
                      Text('Akses untuk mengelola data warga tidak tersedia.'),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: TextField(
                          key: const Key('resident_search'),
                          decoration: const InputDecoration(
                            labelText: 'Cari nama atau alamat',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) =>
                              setState(() => _search = value.trim()),
                        ),
                      ),
                      Expanded(
                        child: FutureBuilder<_ResidentManagementData>(
                          future: _data,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('Gagal memuat data warga.'),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${snapshot.error}',
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      OutlinedButton.icon(
                                        onPressed: _reload,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Coba lagi'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            final data = snapshot.data!;
                            final query = _search.toLowerCase();
                            final residents = data.residents.where((resident) {
                              return query.isEmpty ||
                                  resident.name.toLowerCase().contains(query) ||
                                  resident.address
                                      .toLowerCase()
                                      .contains(query);
                            }).toList();

                            if (residents.isEmpty) {
                              return Center(
                                child: Text(
                                  data.residents.isEmpty
                                      ? 'Belum ada data warga untuk wilayah ini.'
                                      : 'Warga tidak ditemukan.',
                                ),
                              );
                            }

                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              itemCount: residents.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final resident = residents[index];
                                return Card(
                                  child: ListTile(
                                    key: Key('resident_${resident.id}'),
                                    leading: CircleAvatar(
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer,
                                      foregroundColor: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer,
                                      child: const Icon(Icons.person_outline),
                                    ),
                                    title: Text(resident.name),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(resident.address),
                                        Text(
                                          _verificationLabel(
                                            resident.verificationStatus,
                                          ),
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Ubah data ${resident.name}',
                                      onPressed: _saving
                                          ? null
                                          : () => _edit(resident, data.houses),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    onTap: _saving
                                        ? null
                                        : () => _edit(resident, data.houses),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      );

  String _verificationLabel(String status) => switch (status) {
        'menunggu' => 'Menunggu verifikasi',
        'terverifikasi' => 'Terverifikasi',
        'ditolak' => 'Pendaftaran ditolak',
        _ => status,
      };

  Future<void> _edit(
    ManagedResident resident,
    List<ResidentHouse> houses,
  ) async {
    final draft = await showDialog<_ResidentEditDraft>(
      context: context,
      builder: (_) => _ResidentEditDialog(
        resident: resident,
        houses: houses,
      ),
    );
    if (draft == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.gateway.updateResident(
        resident: resident,
        name: draft.name,
        house: draft.house,
      );
      if (!mounted) return;
      setState(() => _data = _loadData());
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Data ${draft.name} berhasil diperbarui.')),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text('Gagal memperbarui data: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ResidentManagementData {
  const _ResidentManagementData({
    required this.residents,
    required this.houses,
  });

  final List<ManagedResident> residents;
  final List<ResidentHouse> houses;
}

class _ResidentEditDraft {
  const _ResidentEditDraft({required this.name, required this.house});

  final String name;
  final ResidentHouse house;
}

class _ResidentEditDialog extends StatefulWidget {
  const _ResidentEditDialog({required this.resident, required this.houses});

  final ManagedResident resident;
  final List<ResidentHouse> houses;

  @override
  State<_ResidentEditDialog> createState() => _ResidentEditDialogState();
}

class _ResidentEditDialogState extends State<_ResidentEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String? _houseId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.resident.name);
    if (widget.houses.any((house) => house.id == widget.resident.unitId)) {
      _houseId = widget.resident.unitId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final house = widget.houses.firstWhere((item) => item.id == _houseId);
    Navigator.of(context).pop(
      _ResidentEditDraft(name: _nameController.text.trim(), house: house),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ubah data warga'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    key: const Key('resident_name_input'),
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(labelText: 'Nama lengkap'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Nama wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (widget.houses.isEmpty)
                    const Text(
                        'Tidak ada rumah yang dapat dipilih di wilayah ini.')
                  else
                    DropdownButtonFormField<String>(
                      key: const Key('resident_house_input'),
                      initialValue: _houseId,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Alamat rumah'),
                      items: [
                        for (final house in widget.houses)
                          DropdownMenuItem(
                            value: house.id,
                            child: Text(
                              house.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _houseId = value),
                      validator: (value) =>
                          value == null ? 'Pilih alamat rumah' : null,
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: widget.houses.isEmpty ? null : _submit,
            child: const Text('Simpan perubahan'),
          ),
        ],
      );
}
