# SmartDukan - AI Voice Billing Platform: Project Context Book

## 1. Project Overview

**SmartDukan** is an AI-powered voice billing system designed primarily for shopkeepers (e.g., Indian Kirana stores). It allows a shopkeeper to simply speak out the items a customer is purchasing (e.g., in Hindi or English), and the system automatically converts that speech into a finalized bill, complete with item quantities, price calculations, and GST breakdown. 

The project resolves a crucial pain point for small businesses: manually entering items into a billing system is slow. With SmartDukan, a shopkeeper hits record, speaks the items ("Aloo do kilo, Maggi ek, Sabun teen"), and the system instantly generates the invoice.

## 2. Architecture & Tech Stack

The platform is split into a **Flutter Frontend** (Web/Mobile) and a **FastAPI/LangGraph Backend Agent**.

### 2.1 Frontend (Flutter)
- **Framework**: Flutter (currently optimized for Web).
- **Core Packages**:
  - `record`: For capturing 16kHz PCM WAV audio.
  - `http`: For communicating with the FastAPI backend and sending multipart form data (audio files).
  - `permission_handler`: For managing microphone permissions.
- **UI/UX Workflow**:
  - **Recording State**: User records voice input.
  - **Processing State**: App sends the `.wav` file to the backend and waits for the AI agent to process it.
  - **Human-in-the-Loop (Clarification)**: If the backend cannot confidently match an item to the catalog (ambiguous match), the UI presents a clarification dialog/panel. The shopkeeper selects the correct item from a list of candidates.
  - **Final Bill**: Displays the finalized bill with subtotal, GST, discounts, and total payable amount.
- **Key Files**: 
  - `lib/main.dart`: Contains the main application UI and state management.
  - `lib/services/billing_service.dart`: The API client connecting to the backend endpoints.

### 2.2 Backend (FastAPI + LangGraph)
The backend acts as an intelligent agent. It receives the audio, transcribes it, extracts meaning, resolves items against the database, and calculates the math.

- **Framework**: FastAPI (Python) running on `uvicorn` (`http://127.0.0.1:8000`).
- **AI Agent Framework**: LangGraph (for stateful, multi-step agentic workflows with memory).
- **Transcription Engine**: Groq API (Whisper model) for extremely fast and accurate Hindi/English Speech-to-Text.
- **Key Modules**:
  - `main.py`: FastAPI application entry point.
  - `app/api/routes.py`: Defines endpoints like `/billing/start`, `/billing/resolve`, and `/billing/simple`.
  - `app/graph/state.py`: Defines the `BillingState` using Pydantic and TypedDict, carrying the session state (transcript, parsed items, resolved items, bill).
  - `app/graph/__init__.py`: Assembles the LangGraph workflow.
  - `app/services/catalog.py`: Simulates a database of store items (SKUs, names, prices, GST slabs).

## 3. The LangGraph Agent Pipeline

The core intelligence of the backend runs through a LangGraph pipeline. The nodes execute sequentially, but with a conditional edge for human-in-the-loop interactions.

### Pipeline Steps:
1. **Transcription Node (`transcription_node`)**: 
   - Uses Groq's Whisper API to transcribe the `.wav` file into text.
2. **Parsing Node (`parsing_node`)**: 
   - Uses an LLM to extract structured data from the raw transcript.
   - Outputs a list of `ParsedItem` objects containing raw item names, quantities, units, and spoken prices.
3. **SKU Resolution Node (`sku_resolution_node`)**: 
   - Attempts to match the `ParsedItem` names against the shop's catalog (`app/services/catalog.py`).
   - Uses fuzzy matching.
   - If a match is highly confident, it is marked as `confirmed`.
   - If multiple similar items exist or confidence is low, it is marked as `ambiguous` and candidates are attached.
4. **Human Review Node (`human_review_node`) - Interrupt**:
   - If there are `ambiguous` items, the graph **interrupts execution**.
   - It returns the state to the Flutter app. 
   - The Flutter app shows the shopkeeper the candidates. The shopkeeper selects the correct ones, and sends the resolutions back via `/billing/resolve`.
   - The graph resumes and cycles back to SKU Resolution to apply the manual fixes.
5. **Bill Finalisation Node (`bill_finalisation_node`)**:
   - Once all items are confirmed, it calculates line-item totals.
   - Computes GST amounts based on the specific slab (0%, 5%, 12%, 18%, 28%) for each product.
   - Generates the final `Bill` object with subtotal and total payable amounts.
6. **Inventory Update Node (`inventory_update_node`)**:
   - Placeholder for writing the final transaction to the database (e.g., Supabase) and decrementing stock counts.

## 4. Current State & Known Details
- **Mocked Catalog**: Currently, the system uses an in-memory mock catalog containing typical Indian Kirana items (Aloo, Pyaaz, Parle-G, Atta, etc.) to test the fuzzy matching and GST logic.
- **Local Execution**: The backend runs locally via `start.sh` or `start.command` on port 8000.
- **CORS Setup**: FastAPI is configured to allow all origins, ensuring the Flutter web app can connect without CORS issues.
- **State Persistence**: LangGraph uses a `MemorySaver` checkpointer to remember the state of a session while it waits for the human-in-the-loop clarification.

## 5. Next Steps / Future Roadmap
- Integrate a real database (like Supabase or PostgreSQL) to replace `catalog.py`.
- Finalize production deployment for the FastAPI backend (e.g., to Railway, Render, or AWS).
- Finalize production deployment for the Flutter web frontend (e.g., Vercel, Firebase Hosting).
- Add user authentication to support multiple shopkeepers uniquely.
- Handle complex billing edge cases (e.g., returns, partial payments, credit ledger).
