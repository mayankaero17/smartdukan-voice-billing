# SmartDukan MVP

SmartDukan is a full-stack, AI-powered voice billing application designed specifically for Indian Kirana shopkeepers. It uses a LangGraph-based FastAPI backend with Groq Whisper for Hindi/English speech-to-text to automatically identify grocery items from spoken audio. The Flutter Web frontend provides a seamless, offline-first feel for managing the shop's catalog and recording bills through a dark-themed, intuitive UI.

## Local Development Setup

### Backend (FastAPI)
1. Navigate to the backend directory:
   ```bash
   cd smartdukan-agent
   ```
2. Create a virtual environment and install dependencies:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```
3. Set your Groq API key:
   ```bash
   export GROQ_API_KEY=your_groq_api_key_here
   ```
4. Run the development server:
   ```bash
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```

### Frontend (Flutter Web)
1. Ensure you have the Flutter SDK installed and on your PATH.
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the web app locally:
   ```bash
   flutter run -d chrome
   ```

## Deployment Instructions

### 1. Deploying Backend to Railway
1. Push your repository to GitHub.
2. Create a new Railway project and connect your GitHub repo.
3. Railway will automatically detect the `Procfile` and `runtime.txt`.
4. In the Railway dashboard, go to Variables and add your `GROQ_API_KEY`.
5. Once deployed, note your Railway app URL (e.g., `https://smartdukan-backend.railway.app`).

### 2. Deploying Frontend to Netlify
1. Connect the Flutter repo to Netlify via netlify.com → "Add new site" → "Import from Git"
2. Set environment variable in Netlify dashboard: `BACKEND_URL` = `https://smartdukan-voice-billing-production.up.railway.app`
3. Every push to `main` auto-deploys.

## Environment Variables

| Variable | Location | Description |
|----------|----------|-------------|
| `GROQ_API_KEY` | Backend (Railway) | Required for Whisper Audio transcription and Llama3 extraction. |
| `BACKEND_URL` | Frontend (Build Flag) | Points the Flutter app to the Railway backend URL. Defaults to `http://127.0.0.1:8000` if not set. |
