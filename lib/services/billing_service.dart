import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class BillingResponse {
  final String status;
  final String sessionId;
  final String? transcript;
  final List<dynamic> pendingClarifications;
  final List<dynamic> partialBill;
  final Map<String, dynamic>? bill;
  final List<dynamic> flaggedItems;

  BillingResponse({
    required this.status,
    required this.sessionId,
    this.transcript,
    this.pendingClarifications = const [],
    this.partialBill = const [],
    this.bill,
    this.flaggedItems = const [],
  });

  factory BillingResponse.fromJson(Map<String, dynamic> json) {
    return BillingResponse(
      status: json['status'] ?? 'error',
      sessionId: json['session_id'] ?? '',
      transcript: json['transcript'],
      pendingClarifications: json['pending_clarifications'] ?? [],
      partialBill: json['partial_bill'] ?? [],
      bill: json['bill'],
      flaggedItems: json['flagged_items'] ?? [],
    );
  }
}

class BillingService {
  static const String _baseUrl = 'http://localhost:8000';

  Future<BillingResponse> startBilling({
    required Uint8List audioBytes,
    required String shopId,
    required String sessionId,
  }) async {
    final uri = Uri.parse('$_baseUrl/billing/start');
    
    final request = http.MultipartRequest('POST', uri)
      ..fields['shop_id'] = shopId
      ..fields['session_id'] = sessionId;

    request.files.add(
      http.MultipartFile.fromBytes(
        'audio_file',
        audioBytes,
        filename: '$sessionId.wav',
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      print('AGENT RESPONSE: ${response.body}');
      return BillingResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to start billing: ${response.statusCode}\n${response.body}');
    }
  }

  Future<BillingResponse> resolveItems({
    required String sessionId,
    required List<Map<String, dynamic>> resolutions,
  }) async {
    final uri = Uri.parse('$_baseUrl/billing/resolve');
    
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'session_id': sessionId,
        'resolutions': resolutions,
      }),
    );

    if (response.statusCode == 200) {
      print('AGENT RESPONSE: ${response.body}');
      return BillingResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to resolve items: ${response.statusCode}\n${response.body}');
    }
  }
}
