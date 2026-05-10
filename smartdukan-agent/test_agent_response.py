import wave
import struct
import requests
import json
import os

# Create a 1-second silent WAV file
wav_path = "/tmp/test_billing.wav"
with wave.open(wav_path, "w") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(16000)
    f.writeframes(struct.pack('<' + 'h' * 16000, *([0] * 16000)))

url = "http://localhost:8000/billing/start"
try:
    with open(wav_path, "rb") as f:
        files = {'audio_file': ('test_billing.wav', f, 'audio/wav')}
        data = {'shop_id': 'test-shop', 'session_id': 'debug-session-123'}
        r = requests.post(url, files=files, data=data)
        
    print(f"STATUS: {r.status_code}")
    print(f"AGENT RESPONSE: {r.text}")
except Exception as e:
    print(f"ERROR: {e}")
finally:
    if os.path.exists(wav_path):
        os.remove(wav_path)
