from rapidfuzz import process, fuzz
from app.graph.state import BillingState, ResolvedItem
from app.services.catalog import get_catalog

async def sku_resolution_node(state: BillingState) -> dict:
    """
    Resolves parsed items against the shop's SKU catalog using fuzzy matching.
    Routes items into confirmed, ambiguous, or flagged categories.
    """
    shop_id = state.get("shop_id")
    catalog = await get_catalog(shop_id)
    
    sku_names = [item["name"] for item in catalog]
    
    resolved_items = []
    pending_clarifications = []
    flagged_items = []
    
    for item in state.get("parsed_items", []):
        # Perform fuzzy matching
        matches = process.extract(
            item.name_raw, 
            sku_names, 
            scorer=fuzz.WRatio, 
            limit=2
        )
        
        top_match = matches[0] if matches else None
        second_match = matches[1] if len(matches) > 1 else None
        
        score1 = top_match[1] if top_match else 0
        score2 = second_match[1] if second_match else 0
        
        # Determine if it's ambiguous based on score spread or top score range
        is_ambiguous = (
            (50 <= score1 < 85) or 
            item.uncertain or 
            (top_match and second_match and (score1 - score2 <= 10))
        )
        
        if top_match and score1 >= 85 and not item.uncertain:
            # Path A: Confident Match
            catalog_entry = catalog[top_match[2]]
            
            unit_price = catalog_entry["unit_price"]
            total_price = item.qty * unit_price
            
            # Use spoken price if available
            if not item.missing_info and item.price_spoken is not None:
                if item.price_type == "unit":
                    unit_price = item.price_spoken
                    total_price = item.qty * unit_price
                elif item.price_type == "total":
                    total_price = item.price_spoken
                    unit_price = total_price / item.qty if item.qty != 0 else 0
            
            # Calculate GST (Assuming inclusive pricing)
            gst_slab = catalog_entry["gst_slab"]
            gst_amount = total_price - (total_price / (1 + gst_slab / 100))
            
            parsed_data = item.model_dump(exclude={"unit_price", "total_price"})
            resolved_item = ResolvedItem(
                **parsed_data,
                sku_id=catalog_entry["sku_id"],
                sku_name=catalog_entry["name"],
                unit_price=unit_price,
                total_price=total_price,
                gst_slab=gst_slab,
                gst_amount=gst_amount,
                status="confirmed"
            )
            resolved_items.append(resolved_item)
            
        elif score1 < 85 and getattr(item, "spoken_unit_price", None) is not None:
            # Fallback: Create ConfirmedItem using raw spoken name and spoken price
            unit_price = item.spoken_unit_price
            total_price = item.qty * unit_price
            
            # Assuming 0% GST for unknown items
            gst_slab = 0
            gst_amount = 0.0
            
            parsed_data = item.model_dump(exclude={"unit_price", "total_price"})
            resolved_item = ResolvedItem(
                **parsed_data,
                sku_id=None,
                sku_name=item.name_raw,
                unit_price=unit_price,
                total_price=total_price,
                gst_slab=gst_slab,
                gst_amount=gst_amount,
                status="confirmed"
            )
            resolved_items.append(resolved_item)
            
        elif is_ambiguous and top_match:
            # Path B: Ambiguous
            candidates = []
            for m in matches:
                cat_item = catalog[m[2]]
                candidates.append({
                    "sku_id": cat_item["sku_id"],
                    "name": cat_item["name"],
                    "score": m[1]
                })
            
            resolved_item = ResolvedItem(
                **item.model_dump(),
                status="ambiguous",
                candidates=candidates
            )
            pending_clarifications.append(resolved_item)
            
        else:
            # Path C: Unknown — populate with parsed data
            parsed_data = item.model_dump(exclude={"unit_price", "total_price"})
            resolved_item = ResolvedItem(
                **parsed_data,
                sku_id=None,
                sku_name=item.name_raw,
                unit_price=item.unit_price if item.unit_price is not None else None,
                total_price=item.total_price if item.total_price is not None else None,
                gst_slab=0,
                status="flagged"
            )
            flagged_items.append(resolved_item)

    # Set internal routing flag
    routing = "needs_clarification" if pending_clarifications else "ready_to_finalise"
    
    return {
        "resolved_items": resolved_items,
        "pending_clarifications": pending_clarifications,
        "flagged_items": flagged_items,
        "routing": routing
    }
