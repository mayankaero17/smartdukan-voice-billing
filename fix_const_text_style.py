import re

with open('lib/main.dart', 'r') as f:
    text = f.read()

text = text.replace('const TextStyle(\n                                    color: Colors.white.withOpacity(0.06)',
                    'TextStyle(\n                                    color: Colors.white.withOpacity(0.06)')

with open('lib/main.dart', 'w') as f:
    f.write(text)
