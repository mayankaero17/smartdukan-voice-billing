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

class _STTHomePageState extends State<STTHomePage> with SingleTickerProviderStateMixin {
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
  late TabController _tabController;
  List<Map<String, dynamic>> _billHistory = [];
  List<Map<String, dynamic>> _skuCatalog = [];
  String _searchQuery = '';
  int _expandedHistoryIndex = -1;

  late final AudioRecorder _recorder;

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
    _tabController = TabController(length: 4, vsync: this);
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
    _tabController.dispose();
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text('Voice Billing AI'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0D0D0D),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(
              Icons.account_tree_outlined,
              color: _showAgentPanel 
                ? const Color(0xFF00C853) 
                : Colors.white38,
              size: 20,
            ),
            tooltip: 'Agent Trace',
            onPressed: () => setState(() => _showAgentPanel = !_showAgentPanel),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00C853),
          labelColor: const Color(0xFF00C853),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: '🎙 Billing'),
            Tab(text: '📋 History'),
            Tab(text: '📦 Inventory'),
            Tab(text: '❓ Guide'),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            TabBarView(
              controller: _tabController,
              children: [
                _buildBillingTab(),
                _buildHistoryTab(),
                _buildInventoryTab(),
                _buildGuideTab(),
              ],
            ),
            if (_showAgentPanel)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: _buildAgentTracePanel(),
              ),
          ],
        ),
      ),
    );
  }

  // ── BILLING TAB ──
  Widget _buildBillingTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildApiKeyField(),
          const SizedBox(height: 16),
          _buildOutputCard(),
          const SizedBox(height: 16),
          Expanded(child: _buildBillingCard()),
          const SizedBox(height: 16),
          _buildBenchmarkBar(),
          const SizedBox(height: 16),
          _buildRecordButton(),
          const SizedBox(height: 12),
          if (_errorLog.isNotEmpty) _buildErrorBanner(),
        ],
      ),
    );
  }

  Widget _buildApiKeyField() {
    return Column(
      children: [
        TextField(
          controller: _apiKeyController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: _useAgentBackend ? 'Groq API Key (Optional in Agent Mode)' : 'Groq API Key (Required)',
            hintText: 'gsk_...',
            prefixIcon: const Icon(Icons.vpn_key),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Switch(
              value: _useAgentBackend,
              activeColor: const Color(0xFF00C853),
              onChanged: (val) {
                setState(() => _useAgentBackend = val);
                _checkBackendHealth();
              },
            ),
            const Text(
              "Use Agent Backend (LangGraph)",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(width: 12),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _backendOnline ? const Color(0xFF00C853) : const Color(0xFFD50000),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _backendStatus,
              style: TextStyle(
                fontSize: 11,
                color: _backendOnline 
                  ? const Color(0xFF00C853) 
                  : const Color(0xFFD50000),
              ),
            ),
          ],
        ),
        if (!_backendOnline)
          TextButton(
            onPressed: _checkBackendHealth,
            child: const Text(
              'Retry connection',
              style: TextStyle(fontSize: 11, color: Color(0xFF00C853)),
            ),
          ),
      ],
    );
  }

  Widget _buildOutputCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mic_none, size: 18, color: Color(0xFF00C853)),
              SizedBox(width: 8),
              Text(
                'Transcription Output',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isTranscribing)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C853))),
                    SizedBox(width: 12),
                    Text('Transcribing with Groq…', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            SelectableText(
              _transcribedText.isEmpty
                  ? 'Enter API key, hold mic button to record.'
                  : _transcribedText,
              style: TextStyle(
                fontSize: _transcribedText.isEmpty ? 14 : 16,
                color: _transcribedText.isEmpty
                    ? Colors.white54
                    : Colors.white,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBillingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long, size: 18, color: Color(0xFF00C853)),
              const SizedBox(width: 8),
              const Text(
                'Extracted Billing Items',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
              ),
              const Spacer(),
              if (_lastAgentResponse?.status == 'needs_clarification')
                ElevatedButton.icon(
                  onPressed: _isExtracting ? null : _handleResolve,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Confirm Selections', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFAB00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isExtracting
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF00C853)),
                        SizedBox(height: 12),
                        Text('Extracting via LLM…', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  )
                : _lastAgentResponse?.status == 'needs_clarification'
                    ? _buildClarificationTable()
                    : _billingItems.isNotEmpty
                        ? Column(
                            children: [
                              Expanded(child: _buildBillingTable()),
                              _buildBillSummary(),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _clearBill,
                                    icon: const Icon(Icons.print, size: 16),
                                    label: const Text('New Bill'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF00C853),
                                      side: const BorderSide(color: Color(0xFF00C853)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  ElevatedButton.icon(
                                    onPressed: _saveToHistory,
                                    icon: const Icon(Icons.save, size: 16),
                                    label: const Text('Save to History'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00C853),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              )
                            ],
                          )
                        : (!_useAgentBackend && _rawJson.isNotEmpty) 
                            ? SingleChildScrollView(
                                child: SelectableText(
                                  _rawJson,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                                ),
                              )
                            : const Center(
                                child: Text(
                                  'Awaiting transcription...',
                                  style: TextStyle(color: Colors.white54, fontSize: 13),
                                ),
                              ),
          ),
          if (_lastAgentResponse?.flaggedItems.isNotEmpty == true)
            _buildFlaggedItemsSection(),
        ],
      ),
    );
  }

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
      totalPayable = subtotal; // Direct mode doesn't have GST easily
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
      const SnackBar(content: Text('Bill saved to history', style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFF00C853)),
    );
    _clearBill();
  }
  
  String _getMonth(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Widget _buildClarificationTable() {
    final pending = _lastAgentResponse?.pendingClarifications ?? [];
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.5),
          1: FlexColumnWidth(2.5),
          2: IntrinsicColumnWidth(),
        },
        border: const TableBorder(
          horizontalInside: BorderSide(color: Colors.white12, width: 0.5),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1)),
            children: const [
              Padding(padding: EdgeInsets.all(8.0), child: Text('Spoken', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Padding(padding: EdgeInsets.all(8.0), child: Text('Match Selection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Padding(padding: EdgeInsets.all(8.0), child: Text('Score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            ],
          ),
          ...List.generate(pending.length, (index) {
            final item = pending[index];
            final candidates = item['candidates'] as List? ?? [];
            final selectedSkuId = _selectedResolutions[index];

            return TableRow(
              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.05)),
              children: [
                Padding(padding: const EdgeInsets.all(8.0), child: Text(item['name_raw'] ?? '-', style: const TextStyle(fontSize: 13))),
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedSkuId,
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      dropdownColor: const Color(0xFF1A1A1A),
                      items: candidates.map<DropdownMenuItem<String>>((c) {
                        return DropdownMenuItem<String>(
                          value: c['sku_id'],
                          child: Text(c['name'], overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedResolutions[index] = val);
                        }
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    candidates.firstWhere((c) => c['sku_id'] == selectedSkuId)['score']?.toString() ?? '-',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBillingTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.white.withOpacity(0.05)),
          dataRowMinHeight: 52,
          dataRowMaxHeight: 52,
          horizontalMargin: 12,
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            DataColumn(label: Text('Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            DataColumn(label: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            DataColumn(label: Text('Unit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            DataColumn(label: Text('Unit Price', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            DataColumn(label: Text('GST%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          ],
          rows: _billingItems.asMap().entries.map((entry) {
            final int index = entry.key;
            final item = entry.value;
            final bool hasError = item['missing_info'] != null;
            
            // Try to infer unit from name if missing
            String unit = '-';
            final name = item['name']?.toString().toLowerCase() ?? '';
            if (name.contains('kg') || name.contains('kilo')) unit = 'kg';
            else if (name.contains('packet') || name.contains('pkt')) unit = 'packet';
            else if (name.contains('litre') || name.contains('ltr')) unit = 'litre';
            else if (name.contains('piece') || name.contains('pc')) unit = 'piece';

            Widget statusChip;
            if (hasError) {
              statusChip = Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFD50000).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: Text(item['missing_info'].toString(), style: const TextStyle(color: Color(0xFFD50000), fontSize: 11)),
              );
            } else {
              statusChip = Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF00C853).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('OK', style: const TextStyle(color: Color(0xFF00C853), fontSize: 11)),
              );
            }

            return DataRow(
              color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
                return index % 2 == 1 ? Colors.white.withOpacity(0.02) : Colors.transparent;
              }),
              cells: [
                DataCell(Text('${index + 1}', style: const TextStyle(fontSize: 13))),
                DataCell(Text(item['name']?.toString() ?? '-', style: const TextStyle(fontSize: 13))),
                DataCell(Text(item['quantity']?.toString() ?? '-', style: const TextStyle(fontSize: 13))),
                DataCell(Text(unit, style: const TextStyle(fontSize: 13))),
                DataCell(Text(item['unit_price'] != null ? '₹${item['unit_price']}' : '–', style: const TextStyle(fontSize: 13))),
                DataCell(Text(item['total_price'] != null ? '₹${item['total_price']}' : '–', style: const TextStyle(fontSize: 13))),
                DataCell(const Text('0%', style: TextStyle(fontSize: 13))), // Defaults to 0% if missing
                DataCell(statusChip),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBillSummary() {
    double subtotal = 0;
    double totalPayable = 0;
    double gstCollected = 0;
    
    if (_useAgentBackend && _lastAgentResponse?.bill != null) {
      subtotal = (_lastAgentResponse!.bill!['subtotal'] ?? 0.0).toDouble();
      totalPayable = (_lastAgentResponse!.bill!['total_payable'] ?? 0.0).toDouble();
      final gstBreakdown = _lastAgentResponse!.bill!['gst_breakdown'] as Map? ?? {};
      gstBreakdown.forEach((k, v) => gstCollected += (v as num).toDouble());
    } else {
      subtotal = _billingItems.fold(0.0, (sum, item) => sum + ((item['total_price'] as num?)?.toDouble() ?? 0.0));
      totalPayable = subtotal;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items: ${_billingItems.length}', style: const TextStyle(fontSize: 14)),
              Text('Subtotal: ₹${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('GST Collected:', style: TextStyle(fontSize: 14)),
              Text('₹${gstCollected.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
            ],
          ),
          const Divider(height: 24, color: Colors.white24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Payable:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('₹${totalPayable.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00C853))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlaggedItemsSection() {
    final flagged = _lastAgentResponse?.flaggedItems ?? [];
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFD50000).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD50000).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFD50000)),
              SizedBox(width: 8),
              Text('Needs Attention (Unknown items)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD50000))),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: flagged.map<Widget>((f) => Chip(
              label: Text(f['name_raw'] ?? 'Unknown', style: const TextStyle(fontSize: 11)),
              backgroundColor: const Color(0xFF0D0D0D),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBenchmarkBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Row(
            children: [
              const Icon(Icons.hearing, size: 16, color: Color(0xFFFFAB00)),
              const SizedBox(width: 6),
              Text('STT: $_inferenceTime', style: const TextStyle(color: Color(0xFFFFAB00), fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          Container(width: 1, height: 16, color: Colors.white12),
          Row(
            children: [
              const Icon(Icons.psychology, size: 16, color: Color(0xFF00C853)),
              const SizedBox(width: 6),
              Text('LLM: $_llmTime', style: const TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordButton() {
    final bool canRecord = !_isTranscribing && !_isExtracting;

    return GestureDetector(
      onTapDown: canRecord ? (_) => _startRecording() : null,
      onTapUp: canRecord ? (_) => _stopRecordingAndTranscribe() : null,
      onTapCancel: canRecord ? () => _stopRecordingAndTranscribe() : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 72,
        decoration: BoxDecoration(
          color: _isRecording
              ? const Color(0xFFD50000)
              : canRecord
                  ? const Color(0xFF00C853)
                  : Colors.white24,
          borderRadius: BorderRadius.circular(20),
          boxShadow: _isRecording
              ? [
                  BoxShadow(
                    color: const Color(0xFFD50000).withOpacity(0.4),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isRecording ? Icons.stop : Icons.mic,
                color: Colors.black,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                _isRecording
                    ? 'Recording… Release to stop'
                    : (_isTranscribing || _isExtracting)
                        ? 'Processing…'
                        : 'Hold to Speak',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFD50000).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFD50000), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              _errorLog,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── HISTORY TAB ──
  Widget _buildHistoryTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Saved Bills', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              TextButton(
                onPressed: _billHistory.isEmpty ? null : () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1A1A1A),
                      title: const Text('Clear History', style: TextStyle(color: Colors.white)),
                      content: const Text('Are you sure you want to delete all saved bills?', style: TextStyle(color: Colors.white70)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                        TextButton(onPressed: () {
                          setState(() => _billHistory.clear());
                          Navigator.pop(ctx);
                        }, child: const Text('Clear', style: TextStyle(color: Color(0xFFD50000)))),
                      ],
                    )
                  );
                },
                child: const Text('Clear History', style: TextStyle(color: Color(0xFFD50000))),
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
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    itemCount: _billHistory.length,
                    itemBuilder: (context, index) {
                      final bill = _billHistory[index];
                      final isExpanded = _expandedHistoryIndex == index;
                      final bool isAgent = bill['source'] == 'agent';

                      return Card(
                        color: const Color(0xFF1A1A1A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.white12),
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
                                        Text('Bill #${_billHistory.length - index}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                                        const SizedBox(height: 4),
                                        Text(bill['time'], style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isAgent ? const Color(0xFF00C853).withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            isAgent ? 'Agent' : 'Direct',
                                            style: TextStyle(color: isAgent ? const Color(0xFF00C853) : Colors.blue, fontSize: 10),
                                          ),
                                        )
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('₹${bill['total_payable'].toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF00C853))),
                                        const SizedBox(height: 4),
                                        Text('${bill['item_count']} items', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                      ],
                                    ),
                                  ],
                                ),
                                if (isExpanded) ...[
                                  const Divider(height: 24, color: Colors.white12),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      headingRowColor: WidgetStateProperty.all(Colors.white.withOpacity(0.05)),
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
  Widget _buildInventoryTab() {
    final filteredSkus = _skuCatalog.where((sku) => sku['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Inventory (${_skuCatalog.length} items)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ElevatedButton.icon(
                onPressed: () => _showSkuModal(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Item'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C853),
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
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.white.withOpacity(0.05)),
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
                                icon: const Icon(Icons.edit, size: 18, color: Colors.white54),
                                onPressed: () => _showSkuModal(sku: sku),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18, color: Color(0xFFD50000)),
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
      backgroundColor: const Color(0xFF1A1A1A),
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
                  Text(isEdit ? 'Edit Item' : 'Add Item', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name', filled: true, fillColor: Color(0xFF0D0D0D)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Unit Price (₹)', filled: true, fillColor: Color(0xFF0D0D0D)),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => setModalState(() => advancedExpanded = !advancedExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Text('Advanced options', style: TextStyle(color: advancedExpanded ? const Color(0xFF00C853) : Colors.white54)),
                          Icon(advancedExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: advancedExpanded ? const Color(0xFF00C853) : Colors.white54),
                        ],
                      ),
                    ),
                  ),
                  if (advancedExpanded) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: gstSlab,
                      decoration: const InputDecoration(labelText: 'GST Slab', filled: true, fillColor: Color(0xFF0D0D0D)),
                      dropdownColor: const Color(0xFF1A1A1A),
                      items: [0, 5, 12, 18, 28].map((e) => DropdownMenuItem(value: e, child: Text('$e%'))).toList(),
                      onChanged: (v) => setModalState(() => gstSlab = v!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(labelText: 'Unit', filled: true, fillColor: Color(0xFF0D0D0D)),
                      dropdownColor: const Color(0xFF1A1A1A),
                      items: ['kg', 'packet', 'litre', 'piece', 'other'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setModalState(() => unit = v!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Stock Count', filled: true, fillColor: Color(0xFF0D0D0D)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: skuIdCtrl,
                      decoration: const InputDecoration(labelText: 'SKU ID (Auto-generated if empty)', filled: true, fillColor: Color(0xFF0D0D0D)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
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
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C853), foregroundColor: Colors.black),
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
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Delete ${sku['name']}?', style: const TextStyle(color: Colors.white)),
        content: const Text('This cannot be undone.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () {
            setState(() => _skuCatalog.remove(sku));
            Navigator.pop(ctx);
          }, child: const Text('Delete', style: TextStyle(color: Color(0xFFD50000)))),
        ],
      )
    );
  }

  // ── GUIDE TAB ──
  Widget _buildGuideTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How to use Voice Billing AI', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('Speak naturally. The app understands Hindi, English, and Hinglish.', style: TextStyle(fontSize: 14, color: Colors.white54)),
          const SizedBox(height: 24),
          
          _buildGuideSectionTitle('Getting Started'),
          _buildGuideText('Step 1: Enter your Groq API key at the top\nStep 2: Hold the mic button and speak your items\nStep 3: Release to see the extracted bill\nStep 4: Save to History when done'),
          
          const SizedBox(height: 24),
          _buildGuideSectionTitle('Sample Phrases That Work Well'),
          _buildExampleCard('Items with unit price:', 'दो किलो आलू तीस रुपये किलो\n2 kg potato at 30 rupees per kg', 'Aloo | 2 kg | ₹30/u | Tot: ₹60'),
          _buildExampleCard('Items with total price:', 'तीन पैकेट मैगी पचास रुपये\n3 packets Maggi for 50 rupees total', 'Maggi | 3 pkt | ₹16.67/u | Tot: ₹50'),
          _buildExampleCard('Mixed Hindi/English:', '2 kg aalu, 1 packet Maggi, aadha kilo chini', '3 items, chini flagged missing price'),
          _buildExampleCard('Hindi fractions:', 'Dhai kilo atta, derh kilo dal', 'Atta 2.5kg, Dal 1.5kg'),
          _buildExampleCard('Multiple items in one breath:', 'Aloo 2 kilo, pyaaz 1 kilo, tamatar आधा किलो, sab ka rate tees rupaye kilo', '3 items all at ₹30/kg'),

          const SizedBox(height: 24),
          _buildGuideSectionTitle('Agent Mode vs Direct Mode'),
          Row(
            children: [
              Expanded(child: _buildModeCard('Direct Mode (toggle off)', '⚡ Faster (under 1 second)\nSimple extraction\nNo GST calculation\nNo bill total\nBest for quick billing', Colors.blue)),
              const SizedBox(width: 12),
              Expanded(child: _buildModeCard('Agent Mode (toggle on)', '🤖 Smarter processing\nGST calculated automatically\nBill total shown\nSaves to inventory\nBest for accurate bills', const Color(0xFF00C853))),
            ],
          ),

          const SizedBox(height: 24),
          _buildGuideSectionTitle('Tips'),
          _buildGuideText('• Speak clearly, pause between items\n• Say the price after the item name\n• "rupaye kilo" means per kg price\n• "sab mila ke" means total price for all\n• You can say items in any order\n• Missing prices can be added manually'),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildGuideSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00C853))),
    );
  }

  Widget _buildGuideText(String text) {
    return Text(text, style: const TextStyle(fontSize: 14, color: Colors.white70, height: 1.5));
  }

  Widget _buildExampleCard(String title, String quote, String expected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 8),
          Text('"$quote"', style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Text('Expected: $expected', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildModeCard(String title, String desc, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
          const SizedBox(height: 8),
          Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }

  // ── AGENT TRACE PANEL ──
  Widget _buildAgentTracePanel() {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        border: Border(
          left: BorderSide(color: Colors.white12, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white12, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Agent Trace',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Row(
                  children: [
                    if (_agentTrace.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _agentTrace = []),
                        child: const Text(
                          'Clear',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => setState(() => _showAgentPanel = false),
                      child: const Icon(Icons.close, 
                        color: Colors.white38, size: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Trace entries
          Expanded(
            child: _agentTrace.isEmpty
              ? const Center(
                  child: Text(
                    'No agent runs yet.\nSpeak a bill with\nagent mode on.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _agentTrace.length,
                  itemBuilder: (context, index) {
                    final entry = _agentTrace[index];
                    final status = entry['status'] as String;
                    final color = status == 'done'
                      ? const Color(0xFF00C853)
                      : status == 'error'
                        ? const Color(0xFFD50000)
                        : status == 'running'
                          ? const Color(0xFFFFAB00)
                          : Colors.white38;
                    final icon = status == 'done' ? '✓'
                      : status == 'error' ? '✗'
                      : status == 'running' ? '⟳'
                      : '·';

                    return GestureDetector(
                      onTap: () => setState(() {
                        _agentTrace[index]['expanded'] = 
                          !(_agentTrace[index]['expanded'] as bool);
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: color.withOpacity(0.3), width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(icon, 
                                  style: TextStyle(color: color, fontSize: 12)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    entry['node'].toString().toUpperCase(),
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                Text(
                                  entry['time'].toString(),
                                  style: const TextStyle(
                                    color: Colors.white24,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry['message'].toString(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                            if (entry['expanded'] == true && 
                                entry['data'] != null) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  const JsonEncoder.withIndent('  ')
                                    .convert(entry['data']),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 9,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ],
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
}
