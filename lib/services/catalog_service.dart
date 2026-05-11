import 'dart:convert';
import 'dart:html' as html;
import 'package:uuid/uuid.dart';

class CatalogService {
  static const String _storageKey = 'smartdukan_catalog';
  static final CatalogService _instance = CatalogService._internal();
  final _uuid = const Uuid();

  factory CatalogService() {
    return _instance;
  }

  CatalogService._internal();

  /// Loads the catalog from localStorage.
  /// Returns a list of catalog items.
  List<Map<String, dynamic>> loadCatalog() {
    final String? jsonStr = html.window.localStorage[_storageKey];
    if (jsonStr == null || jsonStr.isEmpty) {
      return _initDefaultCatalog();
    }
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return List<Map<String, dynamic>>.from(decoded);
    } catch (e) {
      print('Error decoding catalog: $e');
      return _initDefaultCatalog();
    }
  }

  /// Saves the entire catalog to localStorage.
  void saveCatalog(List<Map<String, dynamic>> items) {
    final String jsonStr = jsonEncode(items);
    html.window.localStorage[_storageKey] = jsonStr;
  }

  /// Adds a new item to the catalog.
  void addItem({
    required String name,
    List<String> aliases = const [],
    required double unitPrice,
    required String unit,
    int gstSlab = 0,
  }) {
    final items = loadCatalog();
    items.add({
      'sku_id': _uuid.v4(),
      'name': name,
      'aliases': aliases,
      'unit_price': unitPrice,
      'unit': unit,
      'gst_slab': gstSlab,
    });
    saveCatalog(items);
  }

  /// Updates an existing item in the catalog.
  void updateItem({
    required String id,
    String? name,
    List<String>? aliases,
    double? unitPrice,
    String? unit,
    int? gstSlab,
  }) {
    final items = loadCatalog();
    final index = items.indexWhere((item) => item['sku_id'] == id);
    if (index != -1) {
      final currentItem = items[index];
      items[index] = {
        'sku_id': currentItem['sku_id'],
        'name': name ?? currentItem['name'],
        'aliases': aliases ?? currentItem['aliases'],
        'unit_price': unitPrice ?? currentItem['unit_price'],
        'unit': unit ?? currentItem['unit'],
        'gst_slab': gstSlab ?? currentItem['gst_slab'] ?? 0,
      };
      saveCatalog(items);
    }
  }

  /// Deletes an item from the catalog.
  void deleteItem(String id) {
    final items = loadCatalog();
    items.removeWhere((item) => item['sku_id'] == id);
    saveCatalog(items);
  }

  /// Provides a fallback default catalog if none exists.
  List<Map<String, dynamic>> _initDefaultCatalog() {
    final defaultCatalog = [
      {'sku_id': _uuid.v4(), 'name': 'Aloo', 'aliases': [], 'unit_price': 30.0, 'unit': 'kg', 'gst_slab': 0},
      {'sku_id': _uuid.v4(), 'name': 'Pyaaz', 'aliases': [], 'unit_price': 40.0, 'unit': 'kg', 'gst_slab': 0},
      {'sku_id': _uuid.v4(), 'name': 'Maggi Noodles', 'aliases': [], 'unit_price': 14.0, 'unit': 'packet', 'gst_slab': 18},
      {'sku_id': _uuid.v4(), 'name': 'Sabun', 'aliases': [], 'unit_price': 35.0, 'unit': 'piece', 'gst_slab': 18},
    ];
    saveCatalog(defaultCatalog);
    return defaultCatalog;
  }
}
