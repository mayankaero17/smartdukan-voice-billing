import logging
from typing import List, Optional
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from pydantic import BaseModel
from langgraph.types import Command

from app.graph import compiled_graph
from app.graph.state import CorrectionSignal, ResolvedItem, BillingState
from app.graph.nodes.transcription import transcription_node
from app.graph.nodes.parsing import parsing_node

router = APIRouter()
logger = logging.getLogger(__name__)

# ─── Request Models ────────────────────────────────────────

class Resolution(BaseModel):
    item_index: int
    sku_id: str
    unit_price: float
    name_manual: Optional[str] = None

class ResolveRequest(BaseModel):
    session_id: str
    resolutions: List[Resolution]

# ─── Endpoints ─────────────────────────────────────────────

@router.post("/billing/start")
async def start_billing(
    audio_file: UploadFile = File(...),
    shop_id: str = Form(...),
    session_id: str = Form(...)
):
    """
    Initialises a billing session, transcribes the audio, and runs the billing graph.
    Returns the finalised bill or a request for human clarification.
    """
    temp_path = f"/tmp/{session_id}.wav"
    try:
        contents = await audio_file.read()
        with open(temp_path, "wb") as buffer:
            buffer.write(contents)
        logger.info(f"Saved audio: {temp_path}, size: {len(contents)} bytes")
        if len(contents) < 1000:
            logger.error(f"Audio file too small: {len(contents)} bytes - likely empty")
            raise HTTPException(status_code=400, detail="Audio file empty or too small")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to save audio file: {e}")
        raise HTTPException(status_code=500, detail="Could not save audio file")
        
    # 2. Build the initial state
    initial_state = {
        "session_id": session_id,
        "shop_id": shop_id,
        "raw_audio_path": temp_path,
        "transcript": None,
        "word_confidences": [],
        "parsed_items": [],
        "resolved_items": [],
        "pending_clarifications": [],
        "flagged_items": [],
        "bill": None,
        "correction_signals": [],
        "routing": None
    }
    
    # 3. Invoke the graph
    config = {"configurable": {"thread_id": session_id}}
    try:
        result = await compiled_graph.ainvoke(initial_state, config=config)
        
        # 4. Check if the graph is interrupted (paused for human review)
        snapshot = await compiled_graph.aget_state(config)
        interrupted = snapshot.next is not None and "human_review" in snapshot.next
        
        if interrupted:
            return {
                "status": "needs_clarification",
                "session_id": session_id,
                "transcript": result.get("transcript", ""),
                "pending_clarifications": result.get("pending_clarifications", []),
                "partial_bill": result.get("resolved_items", [])
            }
        else:
            # 5. Clean run: return the final bill
            return {
                "status": "complete",
                "session_id": session_id,
                "transcript": result.get("transcript", ""),
                "bill": result.get("bill"),
                "flagged_items": result.get("flagged_items", []),
                "correction_signals": result.get("correction_signals", [])
            }
            
    except Exception as e:
        logger.exception(f"Error during graph execution: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/billing/resolve")
async def resolve_billing(req: ResolveRequest):
    """
    Resumes a billing session after the shopkeeper provides resolutions for ambiguous items.
    """
    config = {"configurable": {"thread_id": req.session_id}}
    
    # 1. Load the current graph state
    snapshot = await compiled_graph.aget_state(config)
    if not snapshot.values:
        raise HTTPException(status_code=404, detail="Session not found or expired")
        
    state = snapshot.values
    pending = state.get("pending_clarifications", [])
    resolved = state.get("resolved_items", [])
    corrections = state.get("correction_signals", [])
    
    new_resolved = []
    indices_to_resolve = {res.item_index: res for res in req.resolutions}
    
    # 2. Update items with shopkeeper's resolutions
    for idx, res in indices_to_resolve.items():
        if idx < len(pending):
            item = pending[idx]
            
            # Create updated ResolvedItem with confirmed details
            updated_item = ResolvedItem(
                **item.model_dump(exclude={"sku_id", "unit_price", "total_price", "status", "sku_name"}),
                sku_id=res.sku_id,
                sku_name=res.name_manual or item.name_raw,
                unit_price=res.unit_price,
                total_price=item.qty * res.unit_price,
                status="confirmed"
            )
            new_resolved.append(updated_item)
            
            # Record the correction signal
            corrections.append(CorrectionSignal(
                transcript_fragment=item.name_raw,
                name_raw=item.name_raw,
                resolved_sku_id=res.sku_id,
                correction_type="manual_entry"
            ))
            
    # 3. Update state: Move items from pending to resolved
    updated_pending = [p for i, p in enumerate(pending) if i not in indices_to_resolve]
    updated_resolved = resolved + new_resolved
    
    compiled_graph.update_state(config, {
        "pending_clarifications": updated_pending,
        "resolved_items": updated_resolved,
        "correction_signals": corrections
    })
    
    # 4. Resume the graph by providing the resolution to the interrupt
    try:
        result = await compiled_graph.ainvoke(Command(resume=req.resolutions), config=config)
        
        return {
            "status": "complete",
            "session_id": req.session_id,
            "bill": result.get("bill"),
            "flagged_items": result.get("flagged_items", []),
            "correction_signals": result.get("correction_signals", [])
        }
    except Exception as e:
        logger.exception(f"Error resuming graph: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/billing/simple")
async def simple_billing(
    audio_file: UploadFile = File(...),
    session_id: str = Form(...)
):
    """
    Direct transcription + extraction without the full agentic loop.
    Uses the backend's Groq key.
    """
    temp_path = f"/tmp/simple_{session_id}.wav"
    try:
        contents = await audio_file.read()
        with open(temp_path, "wb") as buffer:
            buffer.write(contents)
    except Exception as e:
        raise HTTPException(status_code=500, detail="Could not save audio file")

    # 1. Transcription
    state = BillingState(raw_audio_path=temp_path, session_id=session_id)
    t_res = transcription_node(state)
    transcript = t_res.get("transcript", "")

    if not transcript:
        return {"status": "complete", "transcript": "", "items": []}

    # 2. Parsing (Extraction)
    state["transcript"] = transcript
    p_res = parsing_node(state)
    parsed_items = p_res.get("parsed_items", [])

    return {
        "status": "complete",
        "session_id": session_id,
        "transcript": transcript,
        "items": [item.model_dump() for item in parsed_items]
    }

@router.get("/billing/session/{session_id}")
async def get_session(session_id: str):
    """
    Debug endpoint to inspect the full state of a billing session.
    """
    config = {"configurable": {"thread_id": session_id}}
    snapshot = await compiled_graph.aget_state(config)
    return {
        "values": snapshot.values,
        "next": snapshot.next,
        "session_id": session_id
    }
