import os, tempfile
from fastapi import FastAPI, UploadFile, File, Form
from typing import Optional
from faster_whisper import WhisperModel

app = FastAPI(title="AI Studio — Faster-Whisper Speech-to-Text API")

MODELS_DIR = "/models"
if not os.path.exists(MODELS_DIR):
    MODELS_DIR = "/var/srv/comfyui/audio/stt/models"

print("Inicializando Faster-Whisper Small na CPU (AVX-512)...")
model = WhisperModel("small", device="cpu", compute_type="int8", download_root=MODELS_DIR)
print("✅ Faster-Whisper Small pronto!")

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "service": "Faster-Whisper STT",
        "model": "small (int8 CPU)",
        "vram_usage": "0 MB"
    }

@app.post("/v1/audio/transcriptions")
async def transcribe(
    file: UploadFile = File(...),
    model_name: Optional[str] = Form("whisper-1"),
    language: Optional[str] = Form(None)
):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name
    
    try:
        segments, info = model.transcribe(tmp_path, language=language, beam_size=1)
        full_text = " ".join([seg.text for seg in segments]).strip()
        return {
            "text": full_text,
            "language": info.language,
            "language_probability": round(info.language_probability, 3),
            "duration": round(info.duration, 2)
        }
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)
