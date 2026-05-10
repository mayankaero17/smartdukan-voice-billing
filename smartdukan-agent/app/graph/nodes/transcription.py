import os
import logging
from dotenv import load_dotenv
from groq import Groq
from app.graph.state import BillingState

load_dotenv()
logger = logging.getLogger(__name__)

def transcription_node(state: BillingState) -> dict:
    """
    Reads the raw audio file, calls Groq Whisper API, and returns
    the transcript along with word-level confidences derived from
    segment avg_logprob scores.
    """
    raw_audio_path = state.get("raw_audio_path")

    if not raw_audio_path or not os.path.exists(raw_audio_path):
        logger.error(f"Audio file not found at path: {raw_audio_path}")
        return {"transcript": "", "word_confidences": []}

    file_size = os.path.getsize(raw_audio_path)
    logger.info(f"Audio file: {raw_audio_path}, size: {file_size} bytes")

    if file_size < 1000:
        logger.error(f"Audio file too small ({file_size} bytes) — likely empty or corrupt")
        return {"transcript": "", "word_confidences": []}

    try:
        client = Groq(api_key=os.environ.get("GROQ_API_KEY"))

        with open(raw_audio_path, "rb") as audio_file:
            response = client.audio.transcriptions.create(
                file=(os.path.basename(raw_audio_path), audio_file),
                model="whisper-large-v3-turbo",
                response_format="verbose_json"
            )

        # Extract transcript
        if isinstance(response, dict):
            transcript = response.get("text", "")
            segments = response.get("segments", [])
        else:
            transcript = getattr(response, "text", "")
            if hasattr(response, "model_dump"):
                resp_dict = response.model_dump()
                segments = resp_dict.get("segments", [])
            else:
                segments = getattr(response, "segments", [])

        logger.info(f"Transcript: '{transcript}'")
        logger.info(f"Segments count: {len(segments)}")

        # Build word confidences from segment avg_logprob
        word_confidences = []
        for seg in segments:
            if isinstance(seg, dict):
                avg_logprob = seg.get("avg_logprob", 0.0)
                seg_text = seg.get("text", "")
            else:
                avg_logprob = getattr(seg, "avg_logprob", 0.0)
                seg_text = getattr(seg, "text", "")

            confidence = min(1.0, max(0.0, 1.0 + avg_logprob / 5.0))

            for word in seg_text.strip().split():
                word_confidences.append({
                    "word": word,
                    "confidence": confidence
                })

        return {
            "transcript": transcript,
            "word_confidences": word_confidences
        }

    except Exception as e:
        logger.exception(f"Transcription failed: {e}")
        return {"transcript": "", "word_confidences": []}
