import re

with open('lib/main.dart', 'r') as f:
    text = f.read()

# Find build inside _STTHomePageState
state_idx = text.find('class _STTHomePageState')
build_match = re.search(r'^\s*Widget build\(BuildContext context\) \{', text[state_idx:], re.MULTILINE)
build_idx = state_idx + build_match.start()

history_match = re.search(r'^\s*Widget _buildHistoryTab\(\) \{', text[build_idx:], re.MULTILINE)
history_idx = build_idx + history_match.start()

if not build_match or not history_match:
    print("Could not find boundaries")
    exit(1)

# Extract old table methods so we don't lose them
def extract_method(name):
    match = re.search(r'^\s*Widget ' + name + r'\(\) \{', text[build_idx:history_idx], re.MULTILINE)
    if not match: return ""
    start = build_idx + match.start()
    brace_count = 0
    in_string = False
    escape = False
    for i in range(start + text[start:].find('{'), len(text)):
        if in_string:
            if text[i] == '\\': escape = not escape
            elif text[i] == "'" and not escape: in_string = False
            else: escape = False
        elif text[i] == "'": in_string = True
        elif text[i] == '{': brace_count += 1
        elif text[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                return text[start:i+1]
    return ""

clarification_table = extract_method('_buildClarificationTable')
billing_table = extract_method('_buildBillingTable')
bill_summary = extract_method('_buildBillSummary')
flagged_items = extract_method('_buildFlaggedItemsSection')

new_ui = """
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
            color: Colors.white.withOpacity(0.06),
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
            color: Colors.white.withOpacity(0.06),
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
            'Inventory'),
          _navItem(3, Icons.help_outline_rounded,
            'Guide'),
          const Spacer(),
          Divider(
            color: Colors.white.withOpacity(0.06),
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
      case 1: return _buildHistoryTab();
      case 2: return _buildInventoryTab();
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
        border: Border.all(color: Colors.white.withOpacity(0.06)),
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
          color: Colors.white.withOpacity(0.06)),
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
          color: Colors.white.withOpacity(0.06)),
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
            : Colors.white.withOpacity(0.06)),
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
          color: Colors.white.withOpacity(0.06)),
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

"""

new_ui += "\n" + clarification_table + "\n" + billing_table + "\n" + bill_summary + "\n" + flagged_items + "\n\n"

text = text[:build_idx] + new_ui + text[history_idx:]

with open('lib/main.dart', 'w') as f:
    f.write(text)

