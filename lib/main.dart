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
import 'package:whisper_hindi_stt/services/catalog_service.dart';
import 'package:whisper_hindi_stt/screens/catalog_screen.dart';
import 'package:whisper_hindi_stt/services/history_service.dart';
import 'package:whisper_hindi_stt/screens/history_screen.dart';
import 'package:whisper_hindi_stt/config.dart';

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
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF0F1117),
          primary: Color(0xFF4ADE80),
          secondary: Color(0xFF4ADE80),
          error: Color(0xFFF87171),
          tertiary: Color(0xFFFBBF24),
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
  bool _useAgentBackend = true;
  final BillingService _billingService = BillingService();
  BillingResponse? _lastAgentResponse;
  Map<int, String> _selectedResolutions = {}; // index -> sku_id
  bool _backendOnline = false;
  String _backendStatus = 'Checking...';
  bool _showAgentPanel = false;
  List<Map<String, dynamic>> _agentTrace = [];

  // New State
  int _selectedNav = 0;
  bool _billSaved = false;
  String _searchQuery = '';
  int _expandedHistoryIndex = -1;

  late final AudioRecorder _recorder;

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
    
    _checkBackendHealth();
    CatalogService().loadCatalog(); // ensure catalog is initialized
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
        await _runSimplePipeline(audioBytes);
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
        Uri.parse('$backendUrl/health'),
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
      _addTrace('backend', 'error', 'Backend unreachable: $e');
      setState(() {
        _errorLog = 'Backend error: Could not reach the agent backend at $backendUrl. Make sure uvicorn is running.\n\nDetails: $e';
      });
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
  // DIRECT MODE (SIMPLE PIPELINE VIA BACKEND)
  // ─────────────────────────────────────────────────────────

  Future<void> _runSimplePipeline(Uint8List audioBytes) async {
    _agentTrace = []; // clear previous trace
    _addTrace('session', 'info', 'New DIRECT billing session started');

    setState(() {
      _isTranscribing = true;
      _isExtracting = true;
      _transcribedText = '';
      _billingItems = [];
      _errorLog = 'DIRECT MODE: Sending to backend /billing/simple...';
      _rawJson = '';
    });

    try {
      final sw = Stopwatch()..start();
      final response = await _billingService.simpleBilling(
        audioBytes: audioBytes,
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      sw.stop();

      setState(() {
        _inferenceTime = '${sw.elapsedMilliseconds}ms';
        _llmTime = '--'; // Simple mode does it in one shot, we just track total time
      });

      if (response.status == 'complete') {
        final items = response.bill?['items'] as List? ?? [];
        setState(() {
          _transcribedText = response.transcript ?? 'Direct pipeline complete';
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
      } else {
        setState(() {
          _errorLog = 'Direct API Error: unexpected status ${response.status}';
        });
      }
    } catch (e) {
      setState(() {
        _errorLog = 'Direct Mode Error: Could not reach the backend at $backendUrl. Make sure uvicorn is running.\\n\\nDetails: $e';
      });
    } finally {
      setState(() {
        _isTranscribing = false;
        _isExtracting = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────
  // UI NEW IMPLEMENTATION
  // ─────────────────────────────────────────────────────────

  @override
  
  @override

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111318),
        elevation: 0,
        title: const Text('Voice Billing AI',
          style: TextStyle(
            color: Color(0xFFE2E8F0),
            fontSize: 16,
            fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: Icon(
              Icons.account_tree_outlined,
              color: _showAgentPanel
                ? const Color(0xFF4ADE80)
                : const Color(0xFF475569),
              size: 18),
            onPressed: () => setState(() =>
              _showAgentPanel = !_showAgentPanel),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Color(0xFFE2E8F0).withOpacity(0.06),
            height: 1)),
      ),
      body: Stack(
        children: [
          Row(
            children: [
              _buildSidebar(),
              Expanded(
                child: _buildMainContent(),
              ),
            ],
          ),
          if (_showAgentPanel)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _buildAgentTracePanel(),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 200,
      color: const Color(0xFF111318),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF4ADE80))),
              const SizedBox(width: 8),
              const Text('SmartDukan',
                style: TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius:
                    BorderRadius.circular(4)),
                child: const Text('Beta',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 9))),
            ]),
          ),
          const SizedBox(height: 20),
          Divider(
            color: Color(0xFFE2E8F0).withOpacity(0.06),
            height: 1),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('NAVIGATION',
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2)),
            ),
          ),
          const SizedBox(height: 8),
          _navItem(0, Icons.receipt_long_outlined,
            'Billing'),
          _navItem(1, Icons.history_outlined,
            'History'),
          _navItem(2, Icons.inventory_2_outlined,
            'Catalog'),
          _navItem(3, Icons.help_outline_rounded,
            'Guide'),
          const Spacer(),
          Divider(
            color: Color(0xFFE2E8F0).withOpacity(0.06),
            height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _backendOnline
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFFF87171))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _backendOnline
                        ? 'Backend online'
                        : 'Backend offline',
                      style: TextStyle(
                        color: _backendOnline
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFF87171),
                        fontSize: 10))),
                ]),
                if (!_backendOnline) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _checkBackendHealth,
                    child: const Text('Retry',
                      style: TextStyle(
                        color: Color(0xFF4ADE80),
                        fontSize: 10,
                        decoration:
                          TextDecoration.underline)),
                  ),
                ],
                const SizedBox(height: 8),
                const Text('v0.1.0 · Spike',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(
      int index, IconData icon, String label) {
    final selected = _selectedNav == index;
    return GestureDetector(
      onTap: () => setState(() =>
        _selectedNav = index),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
            ? const Color(0xFF1E293B)
            : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected ? const Border(
            left: BorderSide(
              color: Color(0xFF4ADE80),
              width: 3),
          ) : null,
        ),
        child: Row(children: [
          Icon(icon,
            size: 16,
            color: selected
              ? const Color(0xFF4ADE80)
              : const Color(0xFF64748B)),
          const SizedBox(width: 10),
          Text(label,
            style: TextStyle(
              color: selected
                ? const Color(0xFFE2E8F0)
                : const Color(0xFF64748B),
              fontSize: 13,
              fontWeight: selected
                ? FontWeight.w500
                : FontWeight.w400)),
        ]),
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_selectedNav) {
      case 0: return _buildBillingPage();
      case 1: return const HistoryScreen();
      case 2: return const CatalogScreen();
      case 3: return _buildGuideTab();
      default: return _buildBillingPage();
    }
  }

  Widget _buildBillingPage() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT COLUMN — controls, 300px fixed
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment:
                CrossAxisAlignment.start,
              children: [
                // Agent toggle only — no API key field
                _buildConfigCard(),
                const SizedBox(height: 12),
                // Transcript output
                _buildTranscriptCard(),
                const SizedBox(height: 12),
                // Mic button card
                _buildMicCard(),
                const Spacer(),
                // STT / LLM timing row
                _buildTimingRow(),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // RIGHT COLUMN — bill table + receipt
          Expanded(
            child: Column(
              crossAxisAlignment:
                CrossAxisAlignment.start,
              children: [
                // Bill header row
                Row(
                  mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Extracted Bill',
                      style: TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                    Row(children: [
                      if (_billingItems.isNotEmpty) ...[
                        _outlinedButton(
                          'New Bill',
                          Icons.refresh_outlined,
                          () => _clearBill(),
                        ),
                        const SizedBox(width: 8),
                        _filledButton(
                          'Save to History',
                          Icons.save_outlined,
                          _saveToHistory,
                        ),
                      ],
                    ]),
                  ],
                ),
                const SizedBox(height: 12),
                // Error/status bar — only when needed
                if (_errorLog.isNotEmpty)
                  _buildStatusBar(),
                SizedBox(height: _errorLog.isNotEmpty 
                  ? 12 : 0),
                // Bill table — scrollable
                Expanded(
                  child: _billingItems.isEmpty && !_isExtracting && !_isTranscribing
                    ? _buildEmptyBillState()
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_isExtracting || _isTranscribing)
                               const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator(color: Color(0xFF4ADE80))))
                            else ...[
                              _lastAgentResponse?.status == 'needs_clarification' ? _buildClarificationTable() : _buildBillingTable(),
                              const SizedBox(height: 16),
                              _buildBillSummary(),
                              if (_lastAgentResponse?.flaggedItems.isNotEmpty == true)
                                _buildFlaggedItemsSection()
                            ]
                          ],
                        ),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBillState() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFFE2E8F0).withOpacity(0.06)),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFF334155)),
            SizedBox(height: 16),
            Text('Your bill will appear here', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16)),
            SizedBox(height: 4),
            Text('Speak items using the mic on the left', style: TextStyle(color: Color(0xFF475569), fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Color(0xFFE2E8F0).withOpacity(0.06)),
      ),
      child: Row(children: [
        const Expanded(
          child: Column(
            crossAxisAlignment:
              CrossAxisAlignment.start,
            children: [
              Text('Agent Mode',
                style: TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
              Text('LangGraph pipeline',
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 11)),
            ],
          ),
        ),
        Switch(
          value: _useAgentBackend,
          onChanged: (v) {
            setState(() => _useAgentBackend = v);
            _checkBackendHealth();
          },
          activeColor: const Color(0xFF4ADE80),
        ),
      ]),
    );
  }

  Widget _buildTranscriptCard() {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 80, maxHeight: 160),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Color(0xFFE2E8F0).withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.mic_none_outlined,
              size: 13,
              color: Color(0xFF4ADE80)),
            SizedBox(width: 6),
            Text('Transcript',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                _transcribedText.isEmpty
                  ? 'Speak to see transcript here...'
                  : _transcribedText,
                style: TextStyle(
                  color: _transcribedText.isEmpty
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
                  fontSize: 13,
                  height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isRecording
            ? const Color(0xFF4ADE80).withOpacity(0.4)
            : Color(0xFFE2E8F0).withOpacity(0.06)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTapDown: (_) => 
              _startRecording(),
            onTapUp: (_) => 
              _stopRecordingAndTranscribe(),
            onTapCancel: () =>
              _stopRecordingAndTranscribe(),
            child: AnimatedContainer(
              duration: const Duration(
                milliseconds: 200),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording
                  ? const Color(0xFF4ADE80)
                  : const Color(0xFF1E2130),
                border: Border.all(
                  color: _isRecording
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFF2D3148),
                  width: 2),
                boxShadow: _isRecording ? [
                  BoxShadow(
                    color: const Color(0xFF4ADE80)
                      .withOpacity(0.3),
                    blurRadius: 16,
                    spreadRadius: 2),
                ] : [],
              ),
              child: Icon(
                _isRecording
                  ? Icons.mic
                  : Icons.mic_none_outlined,
                color: _isRecording
                  ? Colors.black
                  : const Color(0xFF64748B),
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              _isRecording
                ? 'Recording...'
                : _isTranscribing
                  ? 'Transcribing...'
                  : 'Hold to speak',
              style: TextStyle(
                color: _isRecording
                  ? const Color(0xFF4ADE80)
                  : const Color(0xFF475569),
                fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildTimingRow() {
    return Row(children: [
      _timingPill(
        Icons.graphic_eq,
        'STT',
        _inferenceTime),
      const SizedBox(width: 8),
      _timingPill(
        Icons.memory_outlined,
        'LLM',
        _llmTime),
    ]);
  }

  Widget _timingPill(
      IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Color(0xFFE2E8F0).withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
            size: 11,
            color: const Color(0xFF475569)),
          const SizedBox(width: 4),
          Text('$label: $value',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11)),
        ],
      ),
    );
  }

  Widget _outlinedButton(
      String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF2D3148)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
              size: 13,
              color: const Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Text(label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _filledButton(
      String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF4ADE80),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
              size: 13,
              color: Colors.black),
            const SizedBox(width: 6),
            Text(label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    final isError = _errorLog.contains('error') ||
      _errorLog.contains('FALLBACK') ||
      _errorLog.contains('failed');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isError
          ? const Color(0xFF450A0A)
          : const Color(0xFF0C1A2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError
            ? const Color(0xFFF87171).withOpacity(0.3)
            : const Color(0xFF60A5FA).withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(
          isError
            ? Icons.warning_amber_outlined
            : Icons.info_outline,
          size: 13,
          color: isError
            ? const Color(0xFFF87171)
            : const Color(0xFF60A5FA)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_errorLog,
            style: TextStyle(
              color: isError
                ? const Color(0xFFF87171)
                : const Color(0xFF60A5FA),
              fontSize: 11))),
      ]),
    );
  }








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
                      content: const Text('Are you sure you want to delete all saved bills?', style: TextStyle(color: Color(0xFF94A3B8))),
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
                          side: BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06)),
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
                                  Divider(height: 24, color: Color(0xFFE2E8F0).withOpacity(0.06)),
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
        content: const Text('This cannot be undone.', style: TextStyle(color: Color(0xFF94A3B8))),
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
  
Widget _buildGuideTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How to use Voice Billing AI', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0))),
          const SizedBox(height: 8),
          const Text('Speak naturally. The app understands Hindi, English, and Hinglish.', style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8))),
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
              Expanded(child: _buildModeCard('Direct Mode (toggle off)', '⚡ Faster (under 1 second)\nSimple extraction\nNo GST calculation\nNo bill total\nBest for quick billing', Color(0xFF60A5FA))),
              const SizedBox(width: 12),
              Expanded(child: _buildModeCard('Agent Mode (toggle on)', '🤖 Smarter processing\nGST calculated automatically\nBill total shown\nSaves to inventory\nBest for accurate bills', const Color(0xFF4ADE80))),
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
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF4ADE80))),
    );
  }

  Widget _buildGuideText(String text) {
    return Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8), height: 1.5));
  }

  Widget _buildExampleCard(String title, String quote, String expected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1D27), borderRadius: BorderRadius.circular(12), border: Border.all(color: Color(0xFFE2E8F0).withOpacity(0.06))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic, size: 16, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE2E8F0))),
            ],
          ),
          const SizedBox(height: 8),
          Text('"$quote"', style: const TextStyle(color: Color(0xFFE2E8F0), fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Text('Expected: $expected', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildModeCard(String title, String desc, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1A1D27), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
          const SizedBox(height: 8),
          Text(desc, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }

  // ── AGENT TRACE PANEL ──
  
Widget _buildAgentTracePanel() {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Color(0xFF1A1A2E),
        border: Border(
          left: BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Agent Trace',
                  style: TextStyle(
                    color: Color(0xFFE2E8F0),
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
                            color: Color(0xFF475569),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => setState(() => _showAgentPanel = false),
                      child: const Icon(Icons.close, 
                        color: Color(0xFF475569), size: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Trace entries
          Expanded(
            child: _agentTrace.isEmpty
              ? Center(
                  child: Text(
                    'No agent runs yet.\nSpeak a bill with\nagent mode on.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFE2E8F0).withOpacity(0.06), fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _agentTrace.length,
                  itemBuilder: (context, index) {
                    final entry = _agentTrace[index];
                    final status = entry['status'] as String;
                    final color = status == 'done'
                      ? const Color(0xFF4ADE80)
                      : status == 'error'
                        ? const Color(0xFFF87171)
                        : status == 'running'
                          ? const Color(0xFFFBBF24)
                          : Color(0xFF475569);
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
                          color: Color(0xFFE2E8F0).withOpacity(0.04),
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
                                  style: TextStyle(
                                    color: Color(0xFFE2E8F0).withOpacity(0.06),
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry['message'].toString(),
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
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
                                    color: Color(0xFF94A3B8),
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

  void _clearBill() {
    setState(() {
      _billingItems = [];
      _transcribedText = '';
      _rawJson = '';
      _lastAgentResponse = null;
      _billSaved = false;
    });
  }

  void _saveToHistory() {
    if (_billingItems.isEmpty) return;
    
    if (_billSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already saved', style: TextStyle(color: Color(0xFFE2E8F0))), backgroundColor: Color(0xFF1E293B)),
      );
      return;
    }
    
    double subtotal = 0;
    double totalPayable = 0;
    
    if (_useAgentBackend && _lastAgentResponse?.bill != null) {
      subtotal = (_lastAgentResponse!.bill!['subtotal'] ?? 0.0).toDouble();
      totalPayable = (_lastAgentResponse!.bill!['total_payable'] ?? 0.0).toDouble();
    } else {
      subtotal = _billingItems.fold(0.0, (sum, item) => sum + ((item['total_price'] as num?)?.toDouble() ?? 0.0));
      totalPayable = subtotal;
    }

    final billMap = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'created_at': DateTime.now().toIso8601String(),
      'items': List<Map<String, dynamic>>.from(_billingItems),
      'subtotal': subtotal,
      'total_payable': totalPayable,
      'item_count': _billingItems.length,
      'source': _useAgentBackend ? 'agent' : 'direct',
    };

    HistoryService().saveBill(billMap);
    
    setState(() {
      _billSaved = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bill saved', style: TextStyle(color: Color(0xFF111827))), backgroundColor: Color(0xFF4ADE80)),
    );
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
        border: TableBorder(
          horizontalInside: BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06), width: 0.5),
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
                      style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12),
                      dropdownColor: const Color(0xFF1A1D27),
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
          headingRowColor: WidgetStateProperty.all(Color(0xFFE2E8F0).withOpacity(0.05)),
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
                decoration: BoxDecoration(color: const Color(0xFFF87171).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: Text(item['missing_info'].toString(), style: const TextStyle(color: Color(0xFFF87171), fontSize: 11)),
              );
            } else {
              statusChip = Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF4ADE80).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('OK', style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 11)),
              );
            }

            return DataRow(
              color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
                return index % 2 == 1 ? Color(0xFFE2E8F0).withOpacity(0.02) : Colors.transparent;
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
        color: const Color(0xFF0F1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(0xFFE2E8F0).withOpacity(0.06)),
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
          Divider(height: 24, color: Color(0xFFE2E8F0).withOpacity(0.06)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Payable:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('₹${totalPayable.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4ADE80))),
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
        color: const Color(0xFFF87171).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF87171).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF87171)),
              SizedBox(width: 8),
              Text('Needs Attention (Unknown items)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF87171))),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: flagged.map<Widget>((f) => Chip(
              label: Text(f['name_raw'] ?? 'Unknown', style: const TextStyle(fontSize: 11)),
              backgroundColor: const Color(0xFF0F1117),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            )).toList(),
          ),
        ],
      ),
    );
  }

}
