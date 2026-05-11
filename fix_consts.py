import re

with open('lib/main.dart', 'r') as f:
    text = f.read()

# 1. Rename _saveBillToHistory to _saveToHistory
text = text.replace('_saveBillToHistory', '_saveToHistory')

# 2. Fix const BoxDecoration with Colors.white.withOpacity
text = text.replace('const BoxDecoration(\n        color: Color(0xFF1A1A2E),\n        border: Border(\n          left: BorderSide(color: Colors.white.withOpacity(0.06), width: 1),',
                    'BoxDecoration(\n        color: Color(0xFF1A1A2E),\n        border: Border(\n          left: BorderSide(color: Colors.white.withOpacity(0.06), width: 1),')

text = text.replace('const BoxDecoration(\n              border: Border(\n                bottom: BorderSide(color: Colors.white.withOpacity(0.06), width: 1),',
                    'BoxDecoration(\n              border: Border(\n                bottom: BorderSide(color: Colors.white.withOpacity(0.06), width: 1),')

text = text.replace('const Center(\n                  child: Text(\n                    \'No agent runs yet.\\nSpeak a bill with\\nagent mode on.\',\n                    textAlign: TextAlign.center,\n                    style: TextStyle(color: Colors.white.withOpacity(0.06), fontSize: 12),\n                  ),\n                )',
                    'Center(\n                  child: Text(\n                    \'No agent runs yet.\\nSpeak a bill with\\nagent mode on.\',\n                    textAlign: TextAlign.center,\n                    style: TextStyle(color: Colors.white.withOpacity(0.06), fontSize: 12),\n                  ),\n                )')

with open('lib/main.dart', 'w') as f:
    f.write(text)

