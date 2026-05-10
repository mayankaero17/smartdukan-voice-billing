import operator
from typing import TypedDict, Annotated, List, Dict, Optional, Any
from pydantic import BaseModel

class ParsedItem(BaseModel):
    name_raw: str
    qty: float
    unit: Optional[str] = None
    price_spoken: Optional[float] = None
    price_type: Optional[str] = None  # "unit" or "total"
    unit_price: Optional[float] = None
    total_price: Optional[float] = None
    missing_info: bool
    uncertain: bool = False  # True if reconstructed from a low-confidence word

class ResolvedItem(ParsedItem):
    sku_id: Optional[str] = None
    sku_name: Optional[str] = None
    unit_price: Optional[float] = None
    total_price: Optional[float] = None
    gst_slab: Optional[float] = None  # 0, 5, 12, 18, or 28
    gst_amount: Optional[float] = None
    status: str  # "confirmed", "ambiguous", "flagged"
    candidates: Optional[List[Dict[str, Any]]] = None  # top 2 fuzzy matches if ambiguous

class BillLineItem(BaseModel):
    sku_id: str
    name: str
    qty: float
    unit_price: float
    total_price: float
    gst_slab: float
    gst_amount: float

class Bill(BaseModel):
    items: List[BillLineItem]
    subtotal: float
    gst_breakdown: Dict[str, float]  # keys are slab strings ("5%", "12%", etc.), values are total GST collected at that slab
    discount_amount: float
    total_payable: float
    created_at: str  # ISO timestamp

class CorrectionSignal(BaseModel):
    transcript_fragment: str
    name_raw: str
    resolved_sku_id: str
    correction_type: str  # "sku_match", "price_fill", "manual_entry"

class BillingState(TypedDict):
    session_id: str
    shop_id: str
    raw_audio_path: Optional[str]  # path to the temp audio file on disk
    transcript: Optional[str]
    word_confidences: Annotated[List[Dict[str, Any]], operator.add]  # each dict has keys: word (str), confidence (float)
    parsed_items: Annotated[List[ParsedItem], operator.add]
    resolved_items: Annotated[List[ResolvedItem], operator.add]
    pending_clarifications: Annotated[List[ResolvedItem], operator.add]  # items on Path B awaiting shopkeeper input
    flagged_items: Annotated[List[ResolvedItem], operator.add]  # items on Path C, unknown SKU or missing price
    bill: Optional[Bill]
    correction_signals: Annotated[List[CorrectionSignal], operator.add]
    routing: Optional[str]  # internal field, values: "needs_clarification", "ready_to_finalise"
