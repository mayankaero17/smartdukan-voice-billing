import re

with open('lib/main.dart', 'r') as f:
    text = f.read()

# Fix the 70 suffix issue
text = text.replace('Color(0xFFE2E8F0)70', 'Color(0xFF94A3B8)')

# Fix const BorderSide with .withOpacity
text = re.sub(r'const\s+BorderSide\(\s*color:\s*([^\)]+)\.withOpacity\([^\)]+\)', r'BorderSide(color: \1.withOpacity(0.06)', text)
# Wait, let's just remove const from things with .withOpacity
# const BorderSide -> BorderSide
text = text.replace('const BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06))', 'BorderSide(color: Colors.white.withOpacity(0.06))')
text = text.replace('const BorderSide(color: Colors.white.withOpacity(0.06))', 'BorderSide(color: Colors.white.withOpacity(0.06))')

text = text.replace('const Divider(height: 24, color: Color(0xFFE2E8F0).withOpacity(0.06))', 'Divider(height: 24, color: Colors.white.withOpacity(0.06))')
text = text.replace('const Divider(height: 24, color: Colors.white.withOpacity(0.06))', 'Divider(height: 24, color: Colors.white.withOpacity(0.06))')

text = text.replace('const TextStyle(color: Color(0xFFE2E8F0).withOpacity(0.06)', 'TextStyle(color: Colors.white.withOpacity(0.06)')
text = text.replace('const TextStyle(color: Colors.white.withOpacity(0.06)', 'TextStyle(color: Colors.white.withOpacity(0.06)')

text = text.replace('Color(0xFFE2E8F0).withOpacity', 'Colors.white.withOpacity')

# Remove any remaining 'const ' before .withOpacity using regex is better, but maybe we can just fix the specific errors.
# The errors were:
# line 1229: `color: Color(0xFFE2E8F0)70` -> handled
# line 1265: `side: const BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06))` -> handled
# line 1318: `const Divider(height: 24, color: Color(0xFFE2E8F0).withOpacity(0.06))` -> handled
# line 1580: `Color(0xFFE2E8F0)70` -> handled
# line 1643: `Color(0xFFE2E8F0)70` -> handled
# line 1679: `Color(0xFFE2E8F0)70` -> handled
# line 1693: `left: BorderSide(color: Color(0xFFE2E8F0).withOpacity(0.06), width: 1)` -> handled via Color(0xFFE2E8F0).withOpacity -> Colors.white.withOpacity
# line 1704: same
# line 1750: `style: TextStyle(color: Color(0xFFE2E8F0).withOpacity(0.06), fontSize: 12)` -> handled
# line 1807: `color: Color(0xFFE2E8F0).withOpacity(0.06)` -> handled
# line 1817: `color: Color(0xFFE2E8F0)70` -> handled

with open('lib/main.dart', 'w') as f:
    f.write(text)

