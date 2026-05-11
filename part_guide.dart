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
    return Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFFE2E8F0)70, height: 1.5));
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
          Text(desc, style: const TextStyle(color: Color(0xFFE2E8F0)70, fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }

  // ── AGENT TRACE PANEL ──
  