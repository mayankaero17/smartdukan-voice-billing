from datetime import datetime, timezone
from app.graph.state import BillingState, Bill, BillLineItem

def bill_finalisation_node(state: BillingState) -> dict:
    """
    Finalises the bill by calculating totals, back-calculating GST, 
    and generating the final Bill object for confirmed and billable flagged items.
    """
    resolved_items = state.get("resolved_items", [])
    flagged_items = state.get("flagged_items", [])
    
    # Combine confirmed items and flagged items with known prices
    all_billable = []
    for item in resolved_items:
        if item.status == "confirmed":
            all_billable.append(item)
    for item in flagged_items:
        if item.status == "flagged" and item.total_price is not None:
            all_billable.append(item)
    
    bill_items = []
    subtotal = 0.0
    gst_breakdown = {}
    
    for item in all_billable:
        total_price = item.total_price or 0.0
        gst_slab = item.gst_slab or 0.0
        
        # Flagged items get zero GST
        if item.status == "flagged":
            gst_slab = 0.0
            gst_amount = 0.0
        else:
            # Back-calculate GST from the inclusive price
            # Formula: GST = Total - (Total / (1 + slab/100))
            gst_amount = total_price * (gst_slab / 100) / (1 + gst_slab / 100)
        
        line_item = BillLineItem(
            sku_id=item.sku_id or "UNKNOWN",
            name=item.sku_name or item.name_raw,
            qty=item.qty,
            unit_price=item.unit_price or 0.0,
            total_price=total_price,
            gst_slab=gst_slab,
            gst_amount=gst_amount
        )
        bill_items.append(line_item)
        
        # Subtotal is the sum of inclusive prices
        subtotal += total_price
        
        # Update GST grouping
        if gst_slab > 0:
            slab_key = f"{int(gst_slab)}%"
            gst_breakdown[slab_key] = gst_breakdown.get(slab_key, 0.0) + gst_amount
                
    # Discount logic (fetch from state if present, fallback to 0)
    discount_amount = state.get("discount_amount", 0.0)
    total_payable = subtotal - discount_amount
    
    # Construct the final Bill object
    bill = Bill(
        items=bill_items,
        subtotal=subtotal,
        gst_breakdown=gst_breakdown,
        discount_amount=discount_amount,
        total_payable=total_payable,
        created_at=datetime.now(timezone.utc).isoformat()
    )
    
    # Return updated state. 
    # Note: flagged_items are included as-is to ensure they remain in state for UI display.
    return {
        "bill": bill,
        "flagged_items": flagged_items
    }
