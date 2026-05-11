import re

with open('lib/main.dart', 'r') as f:
    text = f.read()

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
    
    # Fix the const issues with withOpacity
    t = t.replace('const BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06)', 'BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06)')
    t = t.replace('const Divider(height: 24, color: Color(0xFFE2E8F0).withOpacity(0.06))', 'Divider(height: 24, color: Color(0xFFE2E8F0).withOpacity(0.06))')
    t = t.replace('const Divider(height: 24, color: Color(0xFFE2E8F0).withOpacity(0.06), width: 0.5)', 'Divider(height: 24, color: Color(0xFFE2E8F0).withOpacity(0.06))') # just in case
    t = t.replace('const TableBorder(\n          horizontalInside: BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06), width: 0.5),\n        )', 'TableBorder(\n          horizontalInside: BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06), width: 0.5),\n        )')
    return t

text = replace_colors(text)

with open('lib/main.dart', 'w') as f:
    f.write(text)

