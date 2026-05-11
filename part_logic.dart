import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:whisper_hindi_stt/services/billing_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WhisperHindiSTTApp());
}

class WhisperHindiSTTApp extends StatelessWidget {
  const WhisperHindiSTTApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Billing AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF0D0D0D),
          primary: Color(0xFF00C853),
          secondary: Color(0xFF00C853),
          error: Color(0xFFD50000),
          tertiary: Color(0xFFFFAB00),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const STTHomePage(),
    );
  }
}

class STTHomePage extends StatefulWidget {
  const STTHomePage({super.key});

  @override
  State<STTHomePage> createState() => _STTHomePageState();
}

class _STTHomePageState extends State<STTHomePage> {
  // ── State ──
  final TextEditingController _apiKeyController = TextEditingController(text: '');
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isExtracting = false;
  String _transcribedText = '';
  String _inferenceTime = '--';
  String _llmTime = '--';
  String _errorLog = '';
  List<Map<String, dynamic>> _billingItems = [];
  String _rawJson = '';
  bool _useAgentBackend = false;
  final BillingService _billingService = BillingService();
  BillingResponse? _lastAgentResponse;
  Map<int, String> _selectedResolutions = {}; // index -> sku_id
  bool _backendOnline = false;
  String _backendStatus = 'Checking...';
  bool _showAgentPanel = false;
  List<Map<String, dynamic>> _agentTrace = [];

  // New State
  int _selectedNav = 0;
  List<Map<String, dynamic>> _billHistory = [];
  List<Map<String, dynamic>> _skuCatalog = [];
  String _searchQuery = '';
  int _expandedHistoryIndex = -1;

  late final AudioRecorder _recorder;

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
    
    _checkBackendHealth();
    _initSkuCatalog();
  }

  void _initSkuCatalog() {
    final defaultSkus = [
      {'name': 'Aloo', 'unit_price': 30.0, 'gst_slab': 0, 'unit': 'kg'},
      {'name': 'Pyaaz', 'unit_price': 40.0, 'gst_slab': 0, 'unit': 'kg'},
      {'name': 'Tamatar', 'unit_price': 50.0, 'gst_slab': 0, 'unit': 'kg'},
      {'name': 'Maggi Noodles', 'unit_price': 14.0, 'gst_slab': 18, 'unit': 'packet'},
      {'name': 'Parle-G Biscuit', 'unit_price': 5.0, 'gst_slab': 18, 'unit': 'packet'},
      {'name': 'Amul Butter', 'unit_price': 58.0, 'gst_slab': 12, 'unit': 'piece'},
      {'name': 'Tata Salt', 'unit_price': 25.0, 'gst_slab': 0, 'unit': 'kg'},
      {'name': 'Chini', 'unit_price': 42.0, 'gst_slab': 5, 'unit': 'kg'},
      {'name': 'Chai Patti', 'unit_price': 120.0, 'gst_slab': 5, 'unit': 'kg'},
      {'name': 'Atta', 'unit_price': 35.0, 'gst_slab': 0, 'unit': 'kg'},
      {'name': 'Chawal', 'unit_price': 60.0, 'gst_slab': 0, 'unit': 'kg'},
      {'name': 'Dal', 'unit_price': 110.0, 'gst_slab': 0, 'unit': 'kg'},
      {'name': 'Moong Dal', 'unit_price': 120.0, 'gst_slab': 0, 'unit': 'kg'},
      {'name': 'Sarso Tel', 'unit_price': 140.0, 'gst_slab': 5, 'unit': 'litre'},
      {'name': 'Doodh', 'unit_price': 33.0, 'gst_slab': 0, 'unit': 'litre'},
      {'name': 'Bread', 'unit_price': 40.0, 'gst_slab': 0, 'unit': 'packet'},
      {'name': 'Ande', 'unit_price': 7.0, 'gst_slab': 0, 'unit': 'piece'},
      {'name': 'Haldi', 'unit_price': 25.0, 'gst_slab': 5, 'unit': 'packet'},
      {'name': 'Mirchi', 'unit_price': 30.0, 'gst_slab': 5, 'unit': 'packet'},
      {'name': 'Dhania', 'unit_price': 25.0, 'gst_slab': 5, 'unit': 'packet'},
      {'name': 'Sabun', 'unit_price': 35.0, 'gst_slab': 18, 'unit': 'piece'},
      {'name': 'Shampoo', 'unit_price': 150.0, 'gst_slab': 18, 'unit': 'piece'},
      {'name': 'Biscuit', 'unit_price': 20.0, 'gst_slab': 18, 'unit': 'packet'},
      {'name': 'Chips', 'unit_price': 20.0, 'gst_slab': 12, 'unit': 'packet'},
      {'name': 'Cold Drink', 'unit_price': 40.0, 'gst_slab': 28, 'unit': 'litre'},
    ];

    for (int i = 0; i < defaultSkus.length; i++) {
      final item = defaultSkus[i];
      _skuCatalog.add({
        'sku_id': 'SKU${(1001 + i).toString()}',
        'name': item['name'],
        'unit_price': item['unit_price'],
        'gst_slab': item['gst_slab'],
        'stock_count': 100,
        'unit': item['unit'],
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _recorder.dispose();
    
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // PERMISSIONS
  // ─────────────────────────────────────────────────────────

  Future<bool> _ensureMicPermission() async {
    if (kIsWeb) {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        setState(() => _errorLog = 'Microphone permission denied by browser.');
        return false;
      }
      return true;
    }
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => _errorLog = 'Microphone permission denied.');
      return false;
    }
    return true;
  }

  // ─────────────────────────────────────────────────────────
  // RECORDING
  // ─────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!_useAgentBackend && _apiKeyController.text.trim().isEmpty) {
      setState(() => _errorLog = 'Please enter your Groq API Key for direct mode, or use Agent Backend.');
      return;
    }

    if (!await _ensureMicPermission()) return;

    setState(() {
      _isRecording = true;
      _transcribedText = '';
      _inferenceTime = '--';
      _llmTime = '--';
      _errorLog = '';
      _billingItems = [];
      _rawJson = '';
    });

    try {
      String? path;
      if (!kIsWeb) {
        final Directory docDir = await getApplicationDocumentsDirectory();
        path = '${docDir.path}/groq_temp_recording.wav';
      }

      const config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      );

      if (kIsWeb) {
        await _recorder.start(config, path: '');
      } else {
        await _recorder.start(config, path: path!);
      }
      debugPrint('[Recorder] Started');
    } catch (e) {
      debugPrint('[Recorder] Start error: $e');
      setState(() {
        _isRecording = false;
        _errorLog = 'Recording start error:\n$e';
      });
    }
  }

  Future<void> _stopRecordingAndTranscribe() async {
    if (!_isRecording) return;

    try {
      final String? pathOrUrl = await _recorder.stop();
      debugPrint('[Recorder] Stopped → $pathOrUrl');

      setState(() => _isRecording = false);

      if (pathOrUrl == null || pathOrUrl.isEmpty) {
        setState(() => _errorLog = 'No audio recorded.');
        return;
      }

      Uint8List? audioBytes;

      if (kIsWeb) {
        final response = await http.get(Uri.parse(pathOrUrl));
        if (response.statusCode == 200) {
          audioBytes = response.bodyBytes;
        } else {
          setState(() => _errorLog = 'Failed to load audio blob.');
          return;
        }
      } else {
        final file = File(pathOrUrl);
        if (file.existsSync()) {
          audioBytes = await file.readAsBytes();
          file.delete().ignore();
        }
      }

      if (audioBytes == null || audioBytes.isEmpty) {
        setState(() => _errorLog = 'Failed to extract audio bytes.');
        return;
      }

      if (_useAgentBackend) {
        await _runAgentPipeline(audioBytes);
      } else {
        await _transcribeWithGroq(audioBytes);
      }
    } catch (e) {
      debugPrint('[Recorder] Stop error: $e');
      setState(() {
        _isRecording = false;
        _errorLog = 'Recording stop error:\n$e';
      });
    }
  }

  Future<void> _checkBackendHealth() async {
    try {
      final response = await http.get(
        Uri.parse('https://smartdukan-voice-billing-production.up.railway.app/health'),
      ).timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        setState(() {
          _backendOnline = true;
          _backendStatus = 'Agent backend: online';
        });
      } else {
        setState(() {
          _backendOnline = false;
          _backendStatus = 'Agent backend: error (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _backendOnline = false;
        _backendStatus = 'Agent backend: offline';
      });
    }
  }

  void _addTrace(String node, String status, String message, {Map<String, dynamic>? data}) {
    setState(() {
      _agentTrace.insert(0, {
        'time': DateTime.now().toIso8601String().substring(11, 19),
        'node': node,
        'status': status, // 'running', 'done', 'error', 'info'
        'message': message,
        'data': data,
        'expanded': false,
      });
    });
  }

  // ─────────────────────────────────────────────────────────
  // AGENT PIPELINE VIA LOCAL BACKEND
  // ─────────────────────────────────────────────────────────

  Future<void> _runAgentPipeline(Uint8List audioBytes) async {
    _agentTrace = []; // clear previous trace
    _addTrace('session', 'info', 'New billing session started');

    setState(() {
      _isTranscribing = true;
      _isExtracting = true;
      _transcribedText = '';
      _billingItems = [];
      _errorLog = 'AGENT: Attempting LangGraph backend...';
      _rawJson = '';
      _lastAgentResponse = null;
      _selectedResolutions = {};
    });

    _addTrace('audio', 'running', 'Audio captured, sending to backend...');

    try {
      final sw = Stopwatch()..start();
      final response = await _billingService.startBilling(
        audioBytes: audioBytes,
        shopId: 'test-shop',
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      sw.stop();

      setState(() {
        _inferenceTime = '${sw.elapsedMilliseconds}ms';
        _lastAgentResponse = response;
      });

      _addTrace('backend', 'done', 'Response received from FastAPI', 
        data: {'status': response.status, 'transcript': response.transcript});

      if (response.status == 'complete') {
        _addTrace('transcription', 'done', 
          'Transcript: ${response.transcript ?? 'empty'}');
        _addTrace('parsing', 'done', 
          'Items parsed: ${(response.bill?['items'] as List?)?.length ?? 0}');
        _addTrace('sku_resolution', 'done', 
          'Flagged items: ${response.flaggedItems.length}');
        _addTrace('bill_finalisation', 'done', 
          'Total payable: ${response.bill?['total_payable']}',
          data: response.bill);

        final items = response.bill?['items'] as List? ?? [];
        setState(() {
          _transcribedText = response.transcript ?? 'Agent pipeline complete';
          _rawJson = '';
          _billingItems = items.map<Map<String, dynamic>>((item) => {
            'name': item['name'],
            'quantity': item['qty'],
            'unit_price': item['unit_price'],
            'total_price': item['total_price'],
            'is_unit_price': true,
            'missing_info': null,
          }).toList();
        });

        if (response.flaggedItems.isNotEmpty) {
          setState(() {
            _errorLog = 'Needs attention: ${response.flaggedItems.map((f) => f['name_raw']).join(', ')}';
          });
        }
      } else if (response.status == 'needs_clarification') {
        _addTrace('sku_resolution', 'info', 
          'Ambiguous items need clarification: ${response.pendingClarifications.length} items',
          data: {'pending': response.pendingClarifications});

        setState(() {
          _transcribedText = 'Agent: clarification needed';
          _errorLog = 'Ambiguous items detected. Please select correct SKUs.';
          // Pre-select the first candidate for each pending item
          for (int i = 0; i < response.pendingClarifications.length; i++) {
            final candidates = response.pendingClarifications[i]['candidates'] as List? ?? [];
            if (candidates.isNotEmpty) {
              _selectedResolutions[i] = candidates[0]['sku_id'];
            }
          }
        });
      }
    } catch (e) {
      _addTrace('backend', 'error', 'Backend unreachable, fell back to direct Groq: $e');
      setState(() {
        _errorLog = 'AGENT FALLBACK: Backend unreachable, running direct Groq. Reason: $e';
      });
      await _transcribeWithGroq(audioBytes);
    } finally {
      setState(() {
        _isTranscribing = false;
        _isExtracting = false;
      });
    }
  }

  Future<void> _handleResolve() async {
    if (_lastAgentResponse == null) return;

    setState(() => _isExtracting = true);

    try {
      final resolutions = _selectedResolutions.entries.map((e) {
        final item = _lastAgentResponse!.pendingClarifications[e.key];
        final candidates = item['candidates'] as List;
        final selectedCandidate = candidates.firstWhere((c) => c['sku_id'] == e.value);
        
        return {
          'item_index': e.key,
          'sku_id': e.value,
          'unit_price': 0.0, // Backend will fetch price from catalog if not provided
          'name_manual': selectedCandidate['name'],
        };
      }).toList();

      final response = await _billingService.resolveItems(
        sessionId: _lastAgentResponse!.sessionId,
        resolutions: resolutions,
      );

      setState(() {
        _lastAgentResponse = response;
        if (response.status == 'complete') {
          final items = response.bill?['items'] as List? ?? [];
          _billingItems = items.map<Map<String, dynamic>>((item) => {
            'name': item['name'],
            'quantity': item['qty'],
            'unit_price': item['unit_price'],
            'total_price': item['total_price'],
            'is_unit_price': true,
            'missing_info': null,
          }).toList();
          _transcribedText = 'Agent: Resolution complete';
          _errorLog = '';
        }
      });
    } catch (e) {
      setState(() => _errorLog = 'Resolution error: $e');
    } finally {
      setState(() => _isExtracting = false);
    }
  }

  // ─────────────────────────────────────────────────────────
  // TRANSCRIPTION VIA GROQ API
  // ─────────────────────────────────────────────────────────

  Future<void> _transcribeWithGroq(Uint8List audioBytes) async {
    setState(() {
      _isTranscribing = true;
      _transcribedText = '';
      _errorLog = '';
    });

    final apiKey = _apiKeyController.text.trim();
    final uri = Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions');

    try {
      final sw = Stopwatch()..start();

      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..fields['model'] = 'whisper-large-v3-turbo'
        ..fields['language'] = 'hi'
        ..fields['response_format'] = 'json';

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          audioBytes,
          filename: 'audio.wav',
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      sw.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['text'] ?? '';
        setState(() {
          _transcribedText = text.isNotEmpty ? text : '(no speech detected)';
          _inferenceTime = '${sw.elapsedMilliseconds}ms';
        });

        // Trigger LLM Extraction if text exists
        if (text.isNotEmpty) {
          await _extractBillingItems(text);
        }
      } else {
        setState(() {
          _errorLog = 'STT API Error (${response.statusCode}):\n${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _errorLog = 'Network Error during STT:\n$e';
      });
    } finally {
      setState(() {
        _isTranscribing = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────
  // LLM BILLING EXTRACTION VIA GROQ
  // ─────────────────────────────────────────────────────────

  Future<void> _extractBillingItems(String text) async {
    setState(() {
      _isExtracting = true;
      _billingItems = [];
      _rawJson = '';
    });

    final apiKey = _apiKeyController.text.trim();
    final uri = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

    try {
      final sw = Stopwatch()..start();

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "model": "llama-3.3-70b-versatile",
          "messages": [
            {
              "role": "system",
              "content": "You are a billing extraction assistant. Extract billing items from the user's speech (Hindi, English, or Hinglish). Identify if the price mentioned is a unit price or a total price. If it is a unit price, calculate the total_price (quantity * unit_price). If info is missing to make the bill (e.g. missing price or quantity), flag it. Return ONLY valid JSON and nothing else: {\"items\": [{\"name\": \"item name\", \"quantity\": 2, \"unit_price\": 50.0, \"total_price\": 100.0, \"is_unit_price\": true, \"missing_info\": null}]}. If missing info, set missing_info to a short string like 'Missing price'."
            },
            {
              "role": "user",
              "content": text
            }
          ],
          "response_format": {"type": "json_object"},
          "temperature": 0.0,
        }),
      );

      sw.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];
        
        setState(() {
          _llmTime = '${sw.elapsedMilliseconds}ms';
          _rawJson = content;
        });

        try {
          final Map<String, dynamic> parsedJson = jsonDecode(content);
          if (parsedJson.containsKey('items') && parsedJson['items'] is List) {
            setState(() {
              _billingItems = List<Map<String, dynamic>>.from(parsedJson['items']);
            });
          }
        } catch (e) {
          debugPrint('JSON Parse error: $e');
        }

      } else {
        setState(() {
          _errorLog = 'LLM API Error (${response.statusCode}):\n${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _errorLog = 'Network Error during LLM extraction:\n$e';
      });
    } finally {
      setState(() {
        _isExtracting = false;
      });
    }
  }


  // ─────────────────────────────────────────────────────────
  // UI NEW IMPLEMENTATION
  // ─────────────────────────────────────────────────────────

  @override
  