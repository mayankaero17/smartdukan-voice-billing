import re

with open('lib/main_old.dart', 'r') as f:
    text = f.read()

# 1. Logic up to build() inside _STTHomePageState
# Find the build method inside _STTHomePageState
state_class_idx = text.find('class _STTHomePageState')
build_idx = text.find('Widget build(BuildContext context) {', state_class_idx)

logic_part = text[:build_idx]

# Replace state variables
logic_part = logic_part.replace('late TabController _tabController;', 'int _selectedNav = 0;')
logic_part = logic_part.replace('_tabController = TabController(length: 4, vsync: this);', '')
logic_part = logic_part.replace('_tabController.dispose();', '')
logic_part = logic_part.replace('with SingleTickerProviderStateMixin ', '')

# 2. Extract History UI
history_idx = text.find('Widget _buildHistoryTab() {')
inventory_idx = text.find('Widget _buildInventoryTab() {')
sku_modal_idx = text.find('void _showSkuModal(')
guide_idx = text.find('Widget _buildGuideTab() {')
trace_idx = text.find('Widget _buildAgentTracePanel() {')

history_part = text[history_idx:inventory_idx]
inventory_part = text[inventory_idx:guide_idx]
guide_part = text[guide_idx:trace_idx]
trace_part = text[trace_idx:]

def replace_colors(t):
    t = t.replace('Color(0xFF0D0D0D)', 'Color(0xFF0F1117)')
    t = t.replace('Color(0xFF1A1A1A)', 'Color(0xFF1A1D27)')
    t = t.replace('Color(0xFF00C853)', 'Color(0xFF4ADE80)')
    t = t.replace('Color(0xFFD50000)', 'Color(0xFFF87171)')
    t = t.replace('Color(0xFFFFAB00)', 'Color(0xFFFBBF24)')
    t = t.replace('Colors.white12', 'Colors.white.withOpacity(0.06)')
    t = t.replace('Colors.white24', 'Colors.white.withOpacity(0.06)')
    t = t.replace('Colors.white38', 'Color(0xFF475569)')
    t = t.replace('Colors.white54', 'Color(0xFF94A3B8)')
    t = t.replace('Colors.white', 'Color(0xFFE2E8F0)')
    t = t.replace('Colors.blue', 'Color(0xFF60A5FA)')
    return t

history_part = replace_colors(history_part)
inventory_part = replace_colors(inventory_part)
guide_part = replace_colors(guide_part)
trace_part = replace_colors(trace_part)

trace_part = trace_part.replace('border: const Border(left: BorderSide(color: Color(0xFF4ADE80), width: 1))',
                                'border: Border(left: BorderSide(color: const Color(0xFF4ADE80).withOpacity(0.3), width: 2))')

with open('part_logic.dart', 'w') as f: f.write(logic_part)
with open('part_history.dart', 'w') as f: f.write(history_part)
with open('part_inventory.dart', 'w') as f: f.write(inventory_part)
with open('part_guide.dart', 'w') as f: f.write(guide_part)
with open('part_trace.dart', 'w') as f: f.write(trace_part)

