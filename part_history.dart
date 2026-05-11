Widget _buildHistoryTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Saved Bills', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0))),
              TextButton(
                onPressed: _billHistory.isEmpty ? null : () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1D27),
                      title: const Text('Clear History', style: TextStyle(color: Color(0xFFE2E8F0))),
                      content: const Text('Are you sure you want to delete all saved bills?', style: TextStyle(color: Color(0xFFE2E8F0)70)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8)))),
                        TextButton(onPressed: () {
                          setState(() => _billHistory.clear());
                          Navigator.pop(ctx);
                        }, child: const Text('Clear', style: TextStyle(color: Color(0xFFF87171)))),
                      ],
                    )
                  );
                },
                child: const Text('Clear History', style: TextStyle(color: Color(0xFFF87171))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _billHistory.isEmpty
                ? const Center(
                    child: Text(
                      "No bills saved yet.\nComplete a bill and tap Save to History.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    itemCount: _billHistory.length,
                    itemBuilder: (context, index) {
                      final bill = _billHistory[index];
                      final isExpanded = _expandedHistoryIndex == index;
                      final bool isAgent = bill['source'] == 'agent';

                      return Card(
                        color: const Color(0xFF1A1D27),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06)),
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedHistoryIndex = -1;
                              } else {
                                _expandedHistoryIndex = index;
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Bill #${_billHistory.length - index}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFE2E8F0))),
                                        const SizedBox(height: 4),
                                        Text(bill['time'], style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isAgent ? const Color(0xFF4ADE80).withOpacity(0.2) : Color(0xFF60A5FA).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            isAgent ? 'Agent' : 'Direct',
                                            style: TextStyle(color: isAgent ? const Color(0xFF4ADE80) : Color(0xFF60A5FA), fontSize: 10),
                                          ),
                                        )
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('₹${bill['total_payable'].toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4ADE80))),
                                        const SizedBox(height: 4),
                                        Text('${bill['item_count']} items', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                      ],
                                    ),
                                  ],
                                ),
                                if (isExpanded) ...[
                                  const Divider(height: 24, color: Color(0xFFE2E8F0).withOpacity(0.06)),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      headingRowColor: WidgetStateProperty.all(Color(0xFFE2E8F0).withOpacity(0.05)),
                                      dataRowMinHeight: 40,
                                      dataRowMaxHeight: 40,
                                      columnSpacing: 16,
                                      columns: const [
                                        DataColumn(label: Text('Item', style: TextStyle(fontSize: 12))),
                                        DataColumn(label: Text('Qty', style: TextStyle(fontSize: 12))),
                                        DataColumn(label: Text('Total', style: TextStyle(fontSize: 12))),
                                      ],
                                      rows: (bill['items'] as List).map((item) {
                                        return DataRow(
                                          cells: [
                                            DataCell(Text(item['name']?.toString() ?? '-', style: const TextStyle(fontSize: 12))),
                                            DataCell(Text(item['quantity']?.toString() ?? '-', style: const TextStyle(fontSize: 12))),
                                            DataCell(Text('₹${item['total_price'] ?? '-'}', style: const TextStyle(fontSize: 12))),
                                          ]
                                        );
                                      }).toList(),
                                    ),
                                  )
                                ]
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── INVENTORY TAB ──
  