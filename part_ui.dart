  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildMainContent()),
          if (_showAgentPanel) _buildAgentTracePanel(),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 220,
      color: const Color(0xFF111318),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Branding
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4ADE80),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('SmartDukan', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Beta', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                ),
              ],
            ),
          ),
          
          // Divider
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.06),
            margin: const EdgeInsets.symmetric(vertical: 16),
          ),
          
          // Section label
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'NAVIGATION',
              style: TextStyle(color: Color(0xFF475569), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2),
            ),
          ),
          
          // Nav items
          _buildNavItem(0, Icons.receipt_long_outlined, 'Billing'),
          _buildNavItem(1, Icons.history_outlined, 'History'),
          _buildNavItem(2, Icons.inventory_2_outlined, 'Inventory'),
          _buildNavItem(3, Icons.help_outline_rounded, 'Guide'),
          
          const Spacer(),
          
          // Bottom section
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _backendOnline ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _backendStatus,
                        style: TextStyle(color: _backendOnline ? const Color(0xFF4ADE80) : const Color(0xFFF87171), fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!_backendOnline)
                  TextButton(
                    onPressed: _checkBackendHealth,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Retry connection', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 11)),
                  ),
                const SizedBox(height: 16),
                const Text('v0.1.0 · Spike', style: TextStyle(color: Color(0xFF334155), fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedNav == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedNav = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? const Border(left: BorderSide(color: Color(0xFF4ADE80), width: 3)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? const Color(0xFF4ADE80) : const Color(0xFF64748B)),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF64748B),
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    String title = 'Billing';
    if (_selectedNav == 1) title = 'Bill History';
    else if (_selectedNav == 2) title = 'Inventory';
    else if (_selectedNav == 3) title = 'Guide';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Bar
        Container(
          height: 56,
          color: const Color(0xFF111318),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              IconButton(
                icon: Icon(
                  Icons.account_tree_outlined,
                  color: _showAgentPanel ? const Color(0xFF4ADE80) : const Color(0xFF64748B),
                  size: 20,
                ),
                tooltip: 'Agent Trace',
                onPressed: () => setState(() => _showAgentPanel = !_showAgentPanel),
              ),
            ],
          ),
        ),
        
        // Content Area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildActivePage(),
          ),
        ),
      ],
    );
  }

  Widget _buildActivePage() {
    switch (_selectedNav) {
      case 0: return _buildBillingTab();
      case 1: return _buildHistoryTab();
      case 2: return _buildInventoryTab();
      case 3: return _buildGuideTab();
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildBillingTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorLog.isNotEmpty) _buildInlineStatus(),
        if (_errorLog.isNotEmpty) const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: _buildBillingLeftColumn()),
            const SizedBox(width: 24),
            Expanded(flex: 7, child: _buildExtractedBillCard()),
          ],
        ),
      ],
    );
  }

  Widget _buildInlineStatus() {
    final isError = _errorLog.contains('error') || _errorLog.contains('FALLBACK');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFF450A0A) : const Color(0xFF052E16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.warning_amber_outlined : Icons.info_outline,
            size: 16,
            color: isError ? const Color(0xFFF87171) : const Color(0xFF4ADE80),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorLog,
              style: TextStyle(
                color: isError ? const Color(0xFFF87171) : const Color(0xFF4ADE80),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingLeftColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCard(
          title: 'Configuration',
          child: Column(
            children: [
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Groq API Key',
                  hintStyle: const TextStyle(color: Color(0xFF475569)),
                  prefixIcon: const Icon(Icons.key_outlined, color: Color(0xFF475569)),
                  filled: true,
                  fillColor: const Color(0xFF1E2130),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2D3148))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF4ADE80))),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Agent Mode (LangGraph)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  const Spacer(),
                  Switch(
                    value: _useAgentBackend,
                    onChanged: (val) => setState(() => _useAgentBackend = val),
                    activeColor: const Color(0xFF4ADE80),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildCard(
          title: 'Transcription',
          child: _transcribedText.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Hold the mic button and speak your items", style: TextStyle(color: Color(0xFF475569), fontSize: 14)),
                ))
              : Text(
                  _transcribedText,
                  style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, height: 1.6),
                ),
        ),
        const SizedBox(height: 16),
        _buildMicCard(),
      ],
    );
  }

  Widget _buildMicCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          GestureDetector(
            onTapDown: (_) => _startRecording(),
            onTapUp: (_) => _stopRecordingAndTranscribe(),
            onTapCancel: () => _stopRecordingAndTranscribe(),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording ? const Color(0xFF4ADE80) : const Color(0xFF1E2130),
                border: _isRecording ? null : Border.all(color: const Color(0xFF2D3148), width: 2),
                boxShadow: _isRecording
                    ? [BoxShadow(color: const Color(0xFF4ADE80).withOpacity(0.4), blurRadius: 20)]
                    : [],
              ),
              child: Icon(
                _isRecording ? Icons.mic : Icons.mic_none_outlined,
                color: _isRecording ? Colors.black : const Color(0xFF94A3B8),
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text("Hold to speak", style: TextStyle(color: Color(0xFF475569), fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2130),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('STT: $_inferenceTime', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2130),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('LLM: $_llmTime', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(title, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Divider(height: 1, color: Colors.white.withOpacity(0.06)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildExtractedBillCard() {
    if (_billingItems.isEmpty && _transcribedText.isEmpty && !_isExtracting && !_isTranscribing) {
      return Container(
        height: 400,
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
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Extracted Items', style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 14, fontWeight: FontWeight.w600)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${_billingItems.length} items', style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 12)),
                ),
              ],
            ),
          ),
          
          if (_isExtracting || _isTranscribing)
            const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator(color: Color(0xFF4ADE80)))),
          
          if (!_isExtracting && !_isTranscribing && _billingItems.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFF1A1D27)),
                dataRowMinHeight: 48,
                dataRowMaxHeight: 48,
                horizontalMargin: 16,
                columnSpacing: 20,
                headingTextStyle: const TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Item')),
                  DataColumn(label: Text('Qty')),
                  DataColumn(label: Text('Unit')),
                  DataColumn(label: Text('Unit Price')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Status')),
                ],
                rows: _billingItems.asMap().entries.map((entry) {
                  final int index = entry.key;
                  final item = entry.value;
                  final bool hasError = item['missing_info'] != null;
                  
                  String unit = '-';
                  final name = item['name']?.toString().toLowerCase() ?? '';
                  if (name.contains('kg') || name.contains('kilo')) unit = 'kg';
                  else if (name.contains('packet') || name.contains('pkt')) unit = 'packet';
                  else if (name.contains('litre') || name.contains('ltr')) unit = 'litre';
                  else if (name.contains('piece') || name.contains('pc')) unit = 'piece';

                  Widget statusChip;
                  if (hasError) {
                    statusChip = Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF450A0A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFF87171).withOpacity(0.3)),
                      ),
                      child: Text(item['missing_info'].toString(), style: const TextStyle(color: Color(0xFFF87171), fontSize: 11)),
                    );
                  } else {
                    statusChip = Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF052E16),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF4ADE80).withOpacity(0.3)),
                      ),
                      child: const Text('OK', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 11)),
                    );
                  }

                  return DataRow(
                    color: WidgetStateProperty.resolveWith<Color?>((states) => Colors.transparent),
                    cells: [
                      DataCell(Text('${index + 1}', style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13))),
                      DataCell(Text(item['name']?.toString() ?? '-', style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13))),
                      DataCell(Text(item['quantity']?.toString() ?? '-', style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13))),
                      DataCell(Text(unit, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13))),
                      DataCell(Text(item['unit_price'] != null ? '₹${item['unit_price']}' : '–', style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13))),
                      DataCell(Text(item['total_price'] != null ? '₹${item['total_price']}' : '–', style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13))),
                      DataCell(statusChip),
                    ],
                  );
                }).toList(),
              ),
            ),
            
          // Footer
          if (!_isExtracting && !_isTranscribing && _billingItems.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D27),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Items: ${_billingItems.length}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                      Text('Subtotal: ₹${subtotal.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('GST Collected:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                      Text('₹${gstCollected.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: Colors.white.withOpacity(0.06)),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Payable', style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 16, fontWeight: FontWeight.w600)),
                      Text('₹${totalPayable.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 20, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _transcribedText = '';
                              _billingItems.clear();
                              _errorLog = '';
                              _rawJson = '';
                              _lastAgentResponse = null;
                            });
                          },
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const Text('New Bill'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF94A3B8),
                            side: const BorderSide(color: Color(0xFF2D3148)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saveBillToHistory,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Save to History'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4ADE80),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                            textStyle: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
