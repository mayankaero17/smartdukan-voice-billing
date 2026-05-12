# SmartDukan Voice Billing — Project Handoff

A production-ready voice-to-bill application for shopkeepers, featuring AI-driven SKU resolution and a clean, minimalist interface.

## 🚀 Live URLs
- **Frontend (Netlify)**: [smartdukan-voice-billing.netlify.app](https://smartdukan-voice-billing.netlify.app)
- **Backend (Railway)**: `https://smartdukan-voice-billing-production.up.railway.app`

## 🛠 Tech Stack
- **Frontend**: Flutter Web (Material 3, Clean UI)
- **Backend**: FastAPI (Python 3.10)
- **AI Orchestration**: LangGraph (Stateful graph for billing logic)
- **Models**: Groq Whisper (STT), Llama-3-70b (Extraction/Resolution)

## ✨ Key Features
1. **Voice-to-Bill**: Shopkeeper holds the mic, speaks the order (Hindi/English/Hinglish), and gets a structured bill.
2. **Ambiguity Resolution**: If a spoken item (e.g., "Aloo") matches multiple SKUs, the app presents a dropdown for manual confirmation.
3. **Persistent UI**: The bill stays visible even during clarification and processing stages.
4. **Clean Production Mode**: All debug toggles, timing metrics, and GST calculations have been removed for a streamlined user experience.
5. **History & Reset**: One-tap saving to history and quick reset for new customers.

## ⚙️ Configuration & Deployment
### Frontend (Netlify)
- **Build Command**: `rm -rf flutter && git clone https://github.com/flutter/flutter.git -b stable && export PATH="$PATH:`pwd`/flutter/bin" && flutter build web --dart-define=BACKEND_URL=$BACKEND_URL`
- **Environment Variables**:
  - `BACKEND_URL`: Set to the Railway production URL.

### Backend (Railway)
- **Environment Variables**:
  - `GROQ_API_KEY`: Required for Whisper and LLM extraction.
  - `DATABASE_URL`: (If using persistent history)

## 💻 Local Development
### Frontend
```bash
flutter pub get
flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:8000
```

### Backend
```bash
cd smartdukan-agent
pip install -r requirements.txt
python main.py
```

## 📝 Recent Improvements
- Fixed "disappearing bill" issue; partial results are now visible during clarification.
- Disabled mic interactions while processing to prevent duplicate requests.
- Implemented `_updateBillingItems` to handle naming inconsistencies between graph states.
- Force-pushed corrected UI code to resolve previous Netlify build failures.
