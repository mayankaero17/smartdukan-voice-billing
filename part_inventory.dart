Widget _buildInventoryTab() {
    final filteredSkus = _skuCatalog.where((sku) => sku['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Inventory (${_skuCatalog.length} items)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0))),
              ElevatedButton.icon(
                onPressed: () => _showSkuModal(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Item'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4ADE80),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search items...',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: const Color(0xFF1A1D27),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D27),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Color(0xFFE2E8F0).withOpacity(0.06)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Color(0xFFE2E8F0).withOpacity(0.05)),
                    columns: const [
                      DataColumn(label: Text('SKU ID', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Unit', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Price (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('GST%', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: filteredSkus.map((sku) {
                      return DataRow(
                        cells: [
                          DataCell(Text(sku['sku_id'].toString())),
                          DataCell(Text(sku['name'].toString())),
                          DataCell(Text(sku['unit'].toString())),
                          DataCell(Text(sku['unit_price'].toString())),
                          DataCell(Text(sku['gst_slab'].toString())),
                          DataCell(Text(sku['stock_count'].toString())),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18, color: Color(0xFF94A3B8)),
                                onPressed: () => _showSkuModal(sku: sku),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18, color: Color(0xFFF87171)),
                                onPressed: () => _confirmDeleteSku(sku),
                              ),
                            ],
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSkuModal({Map<String, dynamic>? sku}) {
    final bool isEdit = sku != null;
    final nameCtrl = TextEditingController(text: isEdit ? sku['name'] : '');
    final priceCtrl = TextEditingController(text: isEdit ? sku['unit_price'].toString() : '');
    final stockCtrl = TextEditingController(text: isEdit ? sku['stock_count'].toString() : '100');
    final skuIdCtrl = TextEditingController(text: isEdit ? sku['sku_id'] : '');
    
    int gstSlab = isEdit ? (sku['gst_slab'] as int) : 0;
    String unit = isEdit ? sku['unit'] : 'piece';
    bool advancedExpanded = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1D27),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(isEdit ? 'Edit Item' : 'Add Item', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0))),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name', filled: true, fillColor: Color(0xFF0F1117)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Unit Price (₹)', filled: true, fillColor: Color(0xFF0F1117)),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => setModalState(() => advancedExpanded = !advancedExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Text('Advanced options', style: TextStyle(color: advancedExpanded ? const Color(0xFF4ADE80) : Color(0xFF94A3B8))),
                          Icon(advancedExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: advancedExpanded ? const Color(0xFF4ADE80) : Color(0xFF94A3B8)),
                        ],
                      ),
                    ),
                  ),
                  if (advancedExpanded) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: gstSlab,
                      decoration: const InputDecoration(labelText: 'GST Slab', filled: true, fillColor: Color(0xFF0F1117)),
                      dropdownColor: const Color(0xFF1A1D27),
                      items: [0, 5, 12, 18, 28].map((e) => DropdownMenuItem(value: e, child: Text('$e%'))).toList(),
                      onChanged: (v) => setModalState(() => gstSlab = v!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(labelText: 'Unit', filled: true, fillColor: Color(0xFF0F1117)),
                      dropdownColor: const Color(0xFF1A1D27),
                      items: ['kg', 'packet', 'litre', 'piece', 'other'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setModalState(() => unit = v!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Stock Count', filled: true, fillColor: Color(0xFF0F1117)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: skuIdCtrl,
                      decoration: const InputDecoration(labelText: 'SKU ID (Auto-generated if empty)', filled: true, fillColor: Color(0xFF0F1117)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          if (nameCtrl.text.isEmpty || priceCtrl.text.isEmpty) return;
                          
                          setState(() {
                            if (isEdit) {
                              sku['name'] = nameCtrl.text;
                              sku['unit_price'] = double.tryParse(priceCtrl.text) ?? 0.0;
                              sku['gst_slab'] = gstSlab;
                              sku['unit'] = unit;
                              sku['stock_count'] = int.tryParse(stockCtrl.text) ?? 0;
                              if (skuIdCtrl.text.isNotEmpty) sku['sku_id'] = skuIdCtrl.text;
                            } else {
                              _skuCatalog.insert(0, {
                                'sku_id': skuIdCtrl.text.isNotEmpty ? skuIdCtrl.text : 'SKU${DateTime.now().millisecondsSinceEpoch.toString().substring(9)}',
                                'name': nameCtrl.text,
                                'unit_price': double.tryParse(priceCtrl.text) ?? 0.0,
                                'gst_slab': gstSlab,
                                'unit': unit,
                                'stock_count': int.tryParse(stockCtrl.text) ?? 0,
                              });
                            }
                          });
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4ADE80), foregroundColor: Colors.black),
                        child: const Text('Save Changes'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          }
        );
      }
    );
  }

  void _confirmDeleteSku(Map<String, dynamic> sku) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D27),
        title: Text('Delete ${sku['name']}?', style: const TextStyle(color: Color(0xFFE2E8F0))),
        content: const Text('This cannot be undone.', style: TextStyle(color: Color(0xFFE2E8F0)70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
          TextButton(onPressed: () {
            setState(() => _skuCatalog.remove(sku));
            Navigator.pop(ctx);
          }, child: const Text('Delete', style: TextStyle(color: Color(0xFFF87171)))),
        ],
      )
    );
  }

  // ── GUIDE TAB ──
  