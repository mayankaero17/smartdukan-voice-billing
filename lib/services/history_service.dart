import 'dart:convert';
import 'dart:html' as html;

class HistoryService {
  static const String _storageKey = 'smartdukan_history';
  static final HistoryService _instance = HistoryService._internal();

  factory HistoryService() {
    return _instance;
  }

  HistoryService._internal();

  /// Loads the history from localStorage.
  /// Returns a list of bills (Maps).
  List<Map<String, dynamic>> loadHistory() {
    final String? jsonStr = html.window.localStorage[_storageKey];
    if (jsonStr == null || jsonStr.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      return List<Map<String, dynamic>>.from(decoded);
    } catch (e) {
      print('Error decoding history: $e');
      return [];
    }
  }

  /// Saves a new bill to history.
  /// Inserts at the beginning (newest first). Caps at 500 entries.
  void saveBill(Map<String, dynamic> bill) {
    final history = loadHistory();
    history.insert(0, bill);

    if (history.length > 500) {
      history.removeRange(500, history.length);
    }

    final String jsonStr = jsonEncode(history);
    html.window.localStorage[_storageKey] = jsonStr;
  }

  /// Clears the entire history.
  void clearHistory() {
    html.window.localStorage.remove(_storageKey);
  }
}
