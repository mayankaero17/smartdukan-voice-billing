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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
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

  late final AudioRecorder _recorder;

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
    _checkBackendHealth();
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
    if (_apiKeyController.text.trim().isEmpty) {
      setState(() => _errorLog = 'Please enter your Groq API Key first.');
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
  // UI
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Voice Billing AI'),
        centerTitle: true,
        backgroundColor: cs.surface,
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
      ),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── API Key Input ──
                    _buildApiKeyField(cs),
                    const SizedBox(height: 16),
      
                    // ── Transcription output ──
                    _buildOutputCard(cs),
                    const SizedBox(height: 16),
      
                    // ── Billing Items Output ──
                    Expanded(child: _buildBillingCard(cs)),
                    const SizedBox(height: 16),
      
                    // ── Benchmark bar ──
                    _buildBenchmarkBar(cs),
                    const SizedBox(height: 16),
      
                    // ── Record button ──
                    _buildRecordButton(cs),
                    const SizedBox(height: 12),
      
                    // ── Error log ──
                    if (_errorLog.isNotEmpty) _buildErrorBanner(cs),
                  ],
                ),
              ),
            ),
            if (_showAgentPanel) _buildAgentTracePanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeyField(ColorScheme cs) {
    return Column(
      children: [
        TextField(
          controller: _apiKeyController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Groq API Key',
            hintText: 'gsk_...',
            prefixIcon: const Icon(Icons.vpn_key),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Switch(
              value: _useAgentBackend,
              onChanged: (val) {
                setState(() => _useAgentBackend = val);
                _checkBackendHealth();
              },
            ),
            Text(
              "Use Agent Backend (LangGraph)",
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
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
              style: TextStyle(fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _buildOutputCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mic_none, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Transcription Output',
                style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
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
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
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
                    ? cs.onSurface.withValues(alpha: 0.4)
                    : cs.onSurface,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBillingCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, size: 18, color: cs.secondary),
              const SizedBox(width: 8),
              Text(
                'Extracted Billing Items',
                style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
              const Spacer(),
              if (_lastAgentResponse?.status == 'needs_clarification')
                ElevatedButton.icon(
                  onPressed: _isExtracting ? null : _handleResolve,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Confirm Selections', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
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
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Extracting via LLM…', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  )
                : _lastAgentResponse?.status == 'needs_clarification'
                    ? _buildClarificationTable(cs)
                    : _billingItems.isNotEmpty
                        ? Column(
                            children: [
                              Expanded(child: _buildBillingTable(cs)),
                              if (_lastAgentResponse?.bill != null)
                                _buildBillSummary(cs, _lastAgentResponse!.bill!),
                            ],
                          )
                        : (!_useAgentBackend && _rawJson.isNotEmpty) 
                            ? SingleChildScrollView(
                                child: SelectableText(
                                  _rawJson,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                                ),
                              )
                            : Center(
                                child: Text(
                                  'Awaiting transcription...',
                                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 13),
                                ),
                              ),
          ),
          if (_lastAgentResponse?.flaggedItems.isNotEmpty == true)
            _buildFlaggedItemsSection(cs),
        ],
      ),
    );
  }

  Widget _buildClarificationTable(ColorScheme cs) {
    final pending = _lastAgentResponse?.pendingClarifications ?? [];
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.5),
          1: FlexColumnWidth(2.5),
          2: IntrinsicColumnWidth(),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1)),
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
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.05)),
              children: [
                Padding(padding: const EdgeInsets.all(8.0), child: Text(item['name_raw'] ?? '-', style: const TextStyle(fontSize: 13))),
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedSkuId,
                      isExpanded: true,
                      style: TextStyle(color: cs.onSurface, fontSize: 12),
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

  Widget _buildBillSummary(ColorScheme cs, Map<String, dynamic> bill) {
    final subtotal = bill['subtotal'] ?? 0.0;
    final total = bill['total_payable'] ?? 0.0;
    final gst = bill['gst_breakdown'] as Map? ?? {};

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal (Inc. GST)', style: TextStyle(fontSize: 12)),
              Text('₹${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          ...gst.entries.map((e) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('GST Collected (${e.key})', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                Text('₹${e.value.toStringAsFixed(2)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          )),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Payable', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('₹${total.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: cs.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlaggedItemsSection(ColorScheme cs) {
    final flagged = _lastAgentResponse?.flaggedItems ?? [];
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: cs.error),
              const SizedBox(width: 8),
              Text('Needs Attention (Unknown items)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.error)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: flagged.map<Widget>((f) => Chip(
              label: Text(f['name_raw'] ?? 'Unknown', style: const TextStyle(fontSize: 11)),
              backgroundColor: cs.surface,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingTable(ColorScheme cs) {
    return SingleChildScrollView(
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.5),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1.5),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: cs.outlineVariant, width: 0.5),
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: cs.surfaceContainerHigh),
            children: const [
              Padding(padding: EdgeInsets.all(8.0), child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Padding(padding: EdgeInsets.all(8.0), child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Padding(padding: EdgeInsets.all(8.0), child: Text('Unit/Tot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Padding(padding: EdgeInsets.all(8.0), child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            ],
          ),
          ..._billingItems.map((item) {
            final bool hasError = item['missing_info'] != null;
            final bool isUnit = item['is_unit_price'] == true;
            final String priceLabel = isUnit 
                ? '${item['unit_price'] ?? '-'}/u\nTot: ${item['total_price'] ?? '-'}' 
                : 'Tot: ${item['total_price'] ?? item['unit_price'] ?? '-'}';

            return TableRow(
              decoration: BoxDecoration(
                color: hasError ? cs.errorContainer.withValues(alpha: 0.2) : null,
              ),
              children: [
                Padding(padding: const EdgeInsets.all(8.0), child: Text(item['name']?.toString() ?? '-', style: const TextStyle(fontSize: 13))),
                Padding(padding: const EdgeInsets.all(8.0), child: Text(item['quantity']?.toString() ?? '-', style: const TextStyle(fontSize: 13))),
                Padding(padding: const EdgeInsets.all(8.0), child: Text(priceLabel, style: const TextStyle(fontSize: 12))),
                Padding(
                  padding: const EdgeInsets.all(8.0), 
                  child: Text(
                    item['missing_info']?.toString() ?? 'OK', 
                    style: TextStyle(
                      fontSize: 12, 
                      fontWeight: FontWeight.bold,
                      color: hasError ? cs.error : Colors.green,
                    )
                  )
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBenchmarkBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Row(
            children: [
              Icon(Icons.hearing, size: 16, color: cs.tertiary),
              const SizedBox(width: 6),
              Text('STT: $_inferenceTime', style: TextStyle(color: cs.tertiary, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          Container(width: 1, height: 16, color: cs.outlineVariant),
          Row(
            children: [
              Icon(Icons.psychology, size: 16, color: cs.secondary),
              const SizedBox(width: 6),
              Text('LLM: $_llmTime', style: TextStyle(color: cs.secondary, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordButton(ColorScheme cs) {
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
              ? Colors.red
              : canRecord
                  ? cs.primary
                  : cs.onSurface.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          boxShadow: _isRecording
              ? [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.4),
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
                color: Colors.white,
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
                  color: Colors.white,
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

  Widget _buildErrorBanner(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cs.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              _errorLog,
              style: TextStyle(color: cs.onErrorContainer, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

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
