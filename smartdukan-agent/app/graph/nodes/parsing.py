import json
import logging
import re
from langchain_core.messages import SystemMessage, HumanMessage
from langchain_groq import ChatGroq
from app.graph.state import BillingState, ParsedItem

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are an expert billing assistant for Indian kirana stores.
Your input is a Hindi, English, or Hinglish voice transcript 
from a shopkeeper listing items to bill.

Your job is to extract every item and return ONLY a valid JSON 
array. No explanation. No markdown. No preamble. Raw JSON only.

Each element must have these keys:

- name_raw: string. Item name as spoken, normalised to title case.
  Clean up speech artifacts — "aloo" → "Aloo", "pyaaz" → "Pyaaz",
  "maggi noodles" → "Maggi Noodles".

- qty: number. Quantity spoken. Default 1 if not mentioned.

- unit: string. Infer intelligently even if not spoken:
  Vegetables and grains (aloo, pyaaz, chawal, atta, dal) → "kg"
  Packaged goods (maggi, biscuit, chips, soap) → "packet"
  Liquids (tel, doodh, juice) → "litre"
  Eggs, bread, individual items → "piece"
  If unit explicitly spoken, use that.
  Only set null if you truly cannot determine.

- spoken_unit_price: number or null. The inline price mentioned for the item if any. (e.g. "X rupaye", "X ka", "X wala", "X per kilo"). Null if not spoken.

- price_spoken: number or null. Price mentioned. Null if not spoken.

- price_type: "unit" or "total" or null.
  Rules:
  "X rupaye kilo / litre / piece" → unit price
  "X rupaye ka ek / do / teen [item]" → unit price
  "sab mila ke / total / altogether X rupaye" → total price
  "teen packet pachaas rupaye" (qty + item + price, no per-unit word) → total price
  Single item with single price → assume unit price
  If unclear → default to "unit"

- unit_price: number or null.
  If price_type is "unit": unit_price = price_spoken
  If price_type is "total": unit_price = price_spoken / qty
  If price_spoken is null: null

- total_price: number or null.
  Always calculate as qty * unit_price.
  If unit_price is null: null

- missing_info: boolean.
  True only if price_spoken is null.
  False if price was spoken or can be calculated.

- uncertain: boolean.
  True if not confident about name, qty, or price due to unclear speech.
  False otherwise.

Hindi number words to resolve:
dhai=2.5, paav=0.25, sawa=1.25, derh=1.5, aadha=0.5,
ek=1, do=2, teen=3, chaar=4, paanch=5, chhe=6, saat=7,
aath=8, nau=9, das=10, pachaas=50, sau=100, hazaar=1000

Hindi price words:
"rupaye", "rupaiya", "rs", "rupe" all mean INR price.
"ka bhav", "rate" indicate unit price context.

Examples:

Input: "do kilo aalu tees rupaye kilo"
Output: [{"name_raw":"Aloo","qty":2,"unit":"kg","spoken_unit_price":30,
"price_spoken":30,"price_type":"unit",
"unit_price":30,"total_price":60,
"missing_info":false,"uncertain":false}]

Input: "teen packet Maggi pachaas rupaye"
Output: [{"name_raw":"Maggi Noodles","qty":3,"unit":"packet","spoken_unit_price":null,
"price_spoken":50,"price_type":"total",
"unit_price":16.67,"total_price":50,
"missing_info":false,"uncertain":false}]

Input: "aadha kilo haldi"
Output: [{"name_raw":"Haldi","qty":0.5,"unit":"kg","spoken_unit_price":null,
"price_spoken":null,"price_type":null,
"unit_price":null,"total_price":null,
"missing_info":true,"uncertain":false}]

Input: "ek litre sarso ka tel aur do sabun"
Output: [
{"name_raw":"Sarso Tel","qty":1,"unit":"litre","spoken_unit_price":null,
"price_spoken":null,"price_type":null,
"unit_price":null,"total_price":null,
"missing_info":true,"uncertain":false},
{"name_raw":"Sabun","qty":2,"unit":"piece","spoken_unit_price":null,
"price_spoken":null,"price_type":null,
"unit_price":null,"total_price":null,
"missing_info":true,"uncertain":false}
]"""

def parsing_node(state: BillingState) -> dict:
    """
    Calls the LLM to parse the transcript into JSON, maps confidence scores to parsed items,
    and returns a list of ParsedItem objects.
    """
    transcript = state.get("transcript", "")
    word_confidences = state.get("word_confidences", [])
    
    if not transcript or not transcript.strip():
        return {"parsed_items": []}
        
    llm = ChatGroq(model="llama-3.3-70b-versatile", temperature=0)
    
    messages = [
        SystemMessage(content=SYSTEM_PROMPT),
        HumanMessage(content=transcript)
    ]
    
    text_content = ""
    try:
        response = llm.invoke(messages)
        text_content = response.content
        
        # Strip markdown if accidentally included by the LLM
        text_content = text_content.strip()
        if text_content.startswith("```"):
            lines = text_content.split('\n')
            if lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].startswith("```"):
                lines = lines[:-1]
            text_content = '\n'.join(lines).strip()
            
        # Parse the JSON
        raw_items = json.loads(text_content)
        
        if not isinstance(raw_items, list):
            # If the LLM wraps the array in an object, try to extract it
            if isinstance(raw_items, dict) and "items" in raw_items:
                raw_items = raw_items["items"]
            else:
                raw_items = []
        
        # Build confidence map for fast lookup
        def normalize_word(w):
            return re.sub(r'[^\w\s]', '', w.lower())
            
        conf_map = {}
        for wc in word_confidences:
            w = normalize_word(wc.get("word", ""))
            if w:
                conf_map[w] = wc.get("confidence", 1.0)
                
        parsed_items = []
        for item in raw_items:
            name_raw = item.get("name_raw", "")
            
            uncertain = item.get("uncertain", False)
            if name_raw:
                name_words = name_raw.split()
                for nw in name_words:
                    norm_nw = normalize_word(nw)
                    # If any word in the name is below 0.75 confidence, mark uncertain
                    if norm_nw in conf_map and conf_map[norm_nw] < 0.75:
                        uncertain = True
                        break
            
            # Construct the ParsedItem from the dictionary
            p_item = ParsedItem(
                name_raw=name_raw,
                qty=float(item.get("qty", 1.0)),
                unit=item.get("unit"),
                spoken_unit_price=item.get("spoken_unit_price"),
                price_spoken=item.get("price_spoken"),
                price_type=item.get("price_type"),
                unit_price=item.get("unit_price"),
                total_price=item.get("total_price"),
                missing_info=bool(item.get("missing_info", False)),
                uncertain=uncertain
            )
            parsed_items.append(p_item)
            
        return {"parsed_items": parsed_items}
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON parsing failed: {e}. Raw response: {text_content}")
        return {"parsed_items": []}
    except Exception as e:
        logger.exception(f"Error in parsing_node: {e}")
        return {"parsed_items": []}
