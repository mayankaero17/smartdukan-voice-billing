import re

with open('lib/main.dart', 'r') as f:
    text = f.read()

# 1. Fix line 1807 const issue
text = text.replace('const BorderSide(\n                                    color: Colors.white.withOpacity(0.06),',
                    'BorderSide(\n                                    color: Colors.white.withOpacity(0.06),')
text = text.replace('const BorderSide(color: Colors.white.withOpacity(0.06))',
                    'BorderSide(color: Colors.white.withOpacity(0.06))')

# 2. Add the missing helper methods before the final closing brace of _STTHomePageState
missing_funcs = """
  void _clearBill() {
    setState(() {
      _billingItems = [];
      _transcribedText = '';
      _rawJson = '';
      _lastAgentResponse = null;
    });
  }

  void _saveToHistory() {
    if (_billingItems.isEmpty) return;
    
    double subtotal = 0;
    double totalPayable = 0;
    
    if (_useAgentBackend && _lastAgentResponse?.bill != null) {
      subtotal = (_lastAgentResponse!.bill!['subtotal'] ?? 0.0).toDouble();
      totalPayable = (_lastAgentResponse!.bill!['total_payable'] ?? 0.0).toDouble();
    } else {
      subtotal = _billingItems.fold(0.0, (sum, item) => sum + ((item['total_price'] as num?)?.toDouble() ?? 0.0));
      totalPayable = subtotal;
    }

    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} · ${now.day} ${_getMonth(now.month)}';

    setState(() {
      _billHistory.insert(0, {
        'id': now.millisecondsSinceEpoch.toString(),
        'time': timeStr,
        'items': List<Map<String, dynamic>>.from(_billingItems),
        'subtotal': subtotal,
        'total_payable': totalPayable,
        'item_count': _billingItems.length,
        'source': _useAgentBackend ? 'agent' : 'direct',
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bill saved to history', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF4ADE80)),
    );
    _clearBill();
  }
  
  String _getMonth(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
"""

# The last closing brace in the file is probably the end of _STTHomePageState, but there are multiple classes.
# Actually, the file has a closing brace at the very end.
# Let's use regex to find the last closing brace and insert before it.
last_brace_idx = text.rfind('}')
if last_brace_idx != -1:
    text = text[:last_brace_idx] + missing_funcs + '\n}'

with open('lib/main.dart', 'w') as f:
    f.write(text)

