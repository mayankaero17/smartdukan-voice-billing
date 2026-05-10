import logging
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
from langgraph.types import interrupt

from app.graph.state import BillingState
from app.graph.nodes.transcription import transcription_node
from app.graph.nodes.parsing import parsing_node
from app.graph.nodes.sku_resolution import sku_resolution_node
from app.graph.nodes.bill_finalisation import bill_finalisation_node

logger = logging.getLogger(__name__)

# ─── Custom Nodes ──────────────────────────────────────────

def human_review_node(state: BillingState):
    """
    Interrupts execution to ask the shopkeeper for clarification on ambiguous items.
    """
    pending = state.get("pending_clarifications", [])
    
    # Format the payload for the client
    clarifications_payload = []
    for idx, item in enumerate(pending):
        clarifications_payload.append({
            "item_index": idx,
            "name_raw": item.name_raw,
            "candidates": item.candidates
        })
    
    # Pause execution and surface the clarifications to the client.
    # The value returned by resume will be stored in 'user_input'.
    user_input = interrupt(value=clarifications_payload)
    
    # After resume, we would typically update the state with user resolutions.
    # For now, we return an empty dict as we expect the next iteration 
    # of sku_resolution to handle the updated state.
    return {}

def inventory_update_node(state: BillingState):
    """
    Stub for updating inventory after a bill is finalised.
    """
    bill = state.get("bill")
    if bill:
        logger.info(f"Inventory Update: Finalised bill with {len(bill.items)} items.")
        # TODO: Implement Supabase write logic here to decrement stock counts
    
    return state # Return state unchanged as requested

# ─── Graph Assembly ─────────────────────────────────────────

# 1. Instantiate the graph
graph = StateGraph(BillingState)

# 2. Add nodes
graph.add_node("transcription", transcription_node)
graph.add_node("parsing", parsing_node)
graph.add_node("sku_resolution", sku_resolution_node)
graph.add_node("human_review", human_review_node)
graph.add_node("bill_finalisation", bill_finalisation_node)
graph.add_node("inventory_update", inventory_update_node)

# 3. Set entry point
graph.set_entry_point("transcription")

# 4. Add basic edges
graph.add_edge("transcription", "parsing")
graph.add_edge("parsing", "sku_resolution")

# 5. Add conditional routing from SKU resolution
def route_after_sku(state: BillingState):
    """
    Decides whether to go to human review or finalisation.
    """
    return state.get("routing")

graph.add_conditional_edges(
    "sku_resolution",
    route_after_sku,
    {
        "needs_clarification": "human_review",
        "ready_to_finalise": "bill_finalisation"
    }
)

# 6. Cycle back from human review to resolution
graph.add_edge("human_review", "sku_resolution")

# 7. Final path
graph.add_edge("bill_finalisation", "inventory_update")
graph.add_edge("inventory_update", END)

# 8. Compile with MemorySaver and configured interrupts
checkpointer = MemorySaver()

compiled_graph = graph.compile(
    checkpointer=checkpointer,
    interrupt_before=["human_review"]
)
