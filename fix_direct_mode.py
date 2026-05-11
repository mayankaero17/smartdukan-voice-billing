import sys

with open('lib/main.dart', 'r') as f:
    content = f.read()

# 1. Replace _transcribeWithGroq call
content = content.replace('await _transcribeWithGroq(audioBytes);', 'await _runSimplePipeline(audioBytes);')

# 2. Replace the Groq methods with _runSimplePipeline
import re
pattern = r'  // ─────────────────────────────────────────────────────────\n  // TRANSCRIPTION VIA GROQ API.*?(?=  // ─────────────────────────────────────────────────────────\n  // UI NEW IMPLEMENTATION)'

replacement = """  // ─────────────────────────────────────────────────────────
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
        _errorLog = 'Direct Mode Error: Could not reach the backend at http://127.0.0.1:8000. Make sure uvicorn is running.\n\nDetails: $e';
      });
    } finally {
      setState(() {
        _isTranscribing = false;
        _isExtracting = false;
      });
    }
  }

"""

new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

with open('lib/main.dart', 'w') as f:
    f.write(new_content)

print("Done replacing.")
