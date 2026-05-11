import 'package:flutter/material.dart';
import 'package:whisper_hindi_stt/services/history_service.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistoryService _historyService = HistoryService();
  List<Map<String, dynamic>> _historyItems = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    setState(() {
      _historyItems = _historyService.loadHistory();
    });
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Clear History', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Are you sure you want to delete all saved bills? This cannot be undone.',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF87171),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                _historyService.clearHistory();
                _loadHistory();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('History cleared.'), backgroundColor: Color(0xFF1E293B)),
                );
              },
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('MMM d, yyyy • h:mm a').format(dt);
    } catch (e) {
      return isoString;
    }
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
                  Text('Bill History', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('Review previously saved bills.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                ],
              ),
              if (_historyItems.isNotEmpty)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: const Color(0xFFF87171),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: const Color(0xFFF87171).withOpacity(0.3)),
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Clear History', style: TextStyle(fontWeight: FontWeight.w600)),
                  onPressed: _confirmClearHistory,
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
              child: _historyItems.isEmpty
                ? const Center(child: Text("No saved bills yet.", style: TextStyle(color: Color(0xFF94A3B8))))
                : ListView.builder(
                    itemCount: _historyItems.length,
                    itemBuilder: (context, index) {
                      final bill = _historyItems[index];
                      final items = bill['items'] as List? ?? [];
                      final createdAt = bill['created_at'] ?? '';
                      final total = bill['total_payable'] ?? 0.0;
                      
                      return Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          collapsedIconColor: const Color(0xFF94A3B8),
                          iconColor: const Color(0xFF4ADE80),
                          title: Text(_formatDate(createdAt), style: const TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w500)),
                          subtitle: Text('${items.length} item${items.length == 1 ? '' : 's'}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('₹$total', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w600, fontSize: 15)),
                              const SizedBox(width: 8),
                              const Icon(Icons.expand_more), // The default ExpansionTile icon will override this, but it forces spacing if needed.
                            ],
                          ),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F1117).withOpacity(0.5),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(flex: 2, child: Text('Item', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold))),
                                      const Expanded(flex: 1, child: Text('Qty', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold))),
                                      const Expanded(flex: 1, child: Text('Price', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold))),
                                      const Expanded(flex: 1, child: Text('Total', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold))),
                                    ],
                                  ),
                                  const Divider(color: Color(0xFF334155), height: 16),
                                  ...items.map((item) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          Expanded(flex: 2, child: Text(item['name'] ?? '', style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13))),
                                          Expanded(flex: 1, child: Text('${item['qty']}', textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13))),
                                          Expanded(flex: 1, child: Text('₹${item['unit_price']}', textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13))),
                                          Expanded(flex: 1, child: Text('₹${item['total_price']}', textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13))),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            )
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
