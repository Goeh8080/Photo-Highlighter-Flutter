import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

/// One saved album entry (IndexedDB store `user_album` in the original).
class AlbumItem {
  final int id;
  final String name;
  final Uint8List bytes;
  final String date;
  final int timestamp;
  final int sizeKb;
  final String? metaState;
  AlbumItem({
    required this.id,
    required this.name,
    required this.bytes,
    required this.date,
    required this.timestamp,
    required this.sizeKb,
    this.metaState,
  });

  String get sizeLabel => sizeKb >= 1024 ? '${(sizeKb / 1024).toStringAsFixed(2)} MB' : '$sizeKb KB';
}

/// Hive box (IndexedDB on web, files on mobile) replacing `PhotoEditorAppDB`.
class AlbumRepository {
  static const boxName = 'user_album';
  late Box _box;
  bool _memory = false;
  final Map<int, Map> _mem = {};
  int _memId = 0;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(boxName);
  }

  /// If on-device storage can't be opened, keep the album in memory so the
  /// app still starts (instead of hanging on the splash screen).
  void useMemoryFallback() => _memory = true;

  Future<void> add({required String name, required Uint8List bytes, String? metaState}) async {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${now.day}/${now.month}/${now.year} ${two(now.hour)}:${two(now.minute)}';
    final rec = {
      'name': name,
      'bytes': bytes,
      'date': date,
      'timestamp': now.millisecondsSinceEpoch,
      'sizeKb': (bytes.length / 1024).round(),
      'metaState': metaState,
    };
    if (_memory) {
      _mem[_memId++] = rec;
    } else {
      await _box.add(rec);
    }
  }

  /// Newest first (`getAll().reverse()`).
  List<AlbumItem> all() {
    final out = <AlbumItem>[];
    final keys = _memory ? _mem.keys.toList() : _box.keys.toList();
    for (final k in keys) {
      final m = Map<String, dynamic>.from((_memory ? _mem[k] : _box.get(k)) as Map);
      final raw = m['bytes'];
      out.add(AlbumItem(
        id: k as int,
        name: m['name'] as String,
        bytes: raw is Uint8List ? raw : Uint8List.fromList(List<int>.from(raw as List)),
        date: m['date'] as String,
        timestamp: m['timestamp'] as int,
        sizeKb: m['sizeKb'] as int,
        metaState: m['metaState'] as String?,
      ));
    }
    return out.reversed.toList();
  }

  Future<void> delete(int id) async => _memory ? _mem.remove(id) : await _box.delete(id);
}
