import 'package:flutter/material.dart';
import 'package:whisper_hindi_stt/services/catalog_service.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final CatalogService _catalogService = CatalogService();
  List<Map<String, dynamic>> _catalogItems = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  void _loadItems() {
    setState(() {
      _catalogItems = _catalogService.loadCatalog();
    });
  }

  void _showItemForm({Map<String, dynamic>? item}) {
    final isEditing = item != null;
    final nameController = TextEditingController(text: isEditing ? item['name'] : '');
    final priceController = TextEditingController(text: isEditing ? item['unit_price'].toString() : '');
    
    // Dynamically extract unique units from catalog, with fallbacks
    final defaultUnits = ['kg', 'packet', 'piece', 'litre'];
    final existingUnits = _catalogItems.map((e) => e['unit'].toString()).toSet().toList();
    final allUnits = {...defaultUnits, ...existingUnits}.toList();
    
    String selectedUnit = isEditing 
        ? item['unit'] 
        : (allUnits.isNotEmpty ? allUnits.first : 'piece');

    if (!allUnits.contains(selectedUnit)) {
      allUnits.add(selectedUnit);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditing ? 'Edit Catalog Item' : 'Add New Item',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  _buildTextField(
                    controller: nameController,
                    label: 'Item Name',
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          controller: priceController,
                          label: 'Unit Price (₹)',
                          icon: Icons.currency_rupee,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          value: selectedUnit,
                          dropdownColor: const Color(0xFF1E293B),
                          decoration: InputDecoration(
                            labelText: 'Unit',
                            labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFF0F1117),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: const TextStyle(color: Color(0xFFE2E8F0)),
                          items: allUnits.map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            if (newValue != null) {
                              setModalState(() => selectedUnit = newValue);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4ADE80),
                          foregroundColor: const Color(0xFF0F1117),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          final name = nameController.text.trim();
                          final price = double.tryParse(priceController.text.trim()) ?? 0.0;
                          if (name.isNotEmpty) {
                            if (isEditing) {
                              _catalogService.updateItem(
                                id: item['sku_id'],
                                name: name,
                                unitPrice: price,
                                unit: selectedUnit,
                              );
                            } else {
                              _catalogService.addItem(
                                name: name,
                                unitPrice: price,
                                unit: selectedUnit,
                              );
                            }
                            _loadItems();
                            Navigator.pop(ctx);
                          }
                        },
                        child: Text(isEditing ? 'Save Changes' : 'Add Item'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Color(0xFFE2E8F0)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 18),
        filled: true,
        fillColor: const Color(0xFF0F1117),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shop Catalog', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Manage your local inventory and prices.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4ADE80),
                  foregroundColor: const Color(0xFF0F1117),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Item', style: TextStyle(fontWeight: FontWeight.w600)),
                onPressed: () => _showItemForm(),
              )
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _catalogItems.isEmpty 
                ? const Center(child: Text("No items in catalog.", style: TextStyle(color: Color(0xFF94A3B8))))
                : ListView.separated(
                itemCount: _catalogItems.length,
                separatorBuilder: (_, __) => Divider(color: const Color(0xFFE2E8F0).withOpacity(0.06), height: 1),
                itemBuilder: (context, index) {
                  final item = _catalogItems[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    title: Text(item['name'], style: const TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w500)),
                    subtitle: Text('Unit: ${item['unit']}  •  ID: ${item['sku_id'].toString().split('-').first}', 
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('₹${item['unit_price']}', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Color(0xFF94A3B8), size: 20),
                          onPressed: () => _showItemForm(item: item),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFF87171), size: 20),
                          onPressed: () {
                            _catalogService.deleteItem(item['sku_id']);
                            _loadItems();
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          )
        ],
      ),
    );
  }
}
