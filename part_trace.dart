Widget _buildAgentTracePanel() {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
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
            decoration: const BoxDecoration(
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
              ? const Center(
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
                                  style: const TextStyle(
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
                                color: Color(0xFFE2E8F0)70,
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
}
