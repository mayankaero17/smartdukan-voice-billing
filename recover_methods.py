import re

with open('lib/main_old.dart', 'r') as f:
    old_text = f.read()

def extract_method(name):
    match = re.search(r'^\s*Widget ' + name + r'\(\) \{', old_text, re.MULTILINE)
    if not match: return ""
    start = match.start()
    brace_count = 0
    in_string = False
    escape = False
    for i in range(start + old_text[start:].find('{'), len(old_text)):
        if in_string:
            if old_text[i] == '\\': escape = not escape
            elif old_text[i] == "'" and not escape: in_string = False
            else: escape = False
        elif old_text[i] == "'": in_string = True
        elif old_text[i] == '{': brace_count += 1
        elif old_text[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                return old_text[start:i+1]
    return ""

clarification_table = extract_method('_buildClarificationTable')
billing_table = extract_method('_buildBillingTable')
bill_summary = extract_method('_buildBillSummary')
flagged_items = extract_method('_buildFlaggedItemsSection')

methods = "\n" + clarification_table + "\n\n" + billing_table + "\n\n" + bill_summary + "\n\n" + flagged_items + "\n"

# In main.dart, we need to append these before the last '}'
with open('lib/main.dart', 'r') as f:
    text = f.read()

last_brace = text.rfind('}')
if last_brace != -1:
    text = text[:last_brace] + methods + '\n}\n'

with open('lib/main.dart', 'w') as f:
    f.write(text)

