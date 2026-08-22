import os, tempfile, torch
from fastapi import FastAPI, UploadFile, File, Form
from typing import Optional
from faster_whisper import WhisperModel

app = FastAPI(title="AI Studio — Hybrid Faster-Whisper Speech-to-Text API")

MODELS_DIR = "/models"
if not os.path.exists(MODELS_DIR):
    MODELS_DIR = "/var/srv/comfyui/audio/stt/models"

def get_optimal_whisper_config(min_free_vram_mb=800):
    if not torch.cuda.is_available():
        return "cpu", "int8"
    try:
        free_bytes, _ = torch.cuda.mem_get_info()
        free_mb = free_bytes / (1024 * 1024)
        if free_mb >= min_free_vram_mb:
            return "cuda", "float16"
    except Exception:
        pass
    return "cpu", "int8"

dev, ctype = get_optimal_whisper_config(800)
print(f"👂 Inicializando Faster-Whisper Small no dispositivo: {dev.upper()} ({ctype})...")
model = WhisperModel("small", device=dev, compute_type=ctype, download_root=MODELS_DIR)
current_dev = dev
print("✅ Faster-Whisper Small pronto!")

@app.get("/health")
def health():
    free_mb = round(torch.cuda.mem_get_info()[0] / (1024*1024), 1) if torch.cuda.is_available() else 0
    return {
        "status": "healthy",
        "service": "Faster-Whisper STT (Hybrid)",
        "active_device": current_dev,
        "free_vram_mb": free_mb,
        "model": "small"
    }

@app.post("/v1/audio/transcriptions")
async def transcribe(
    file: UploadFile = File(...),
    model_name: Optional[str] = Form("whisper-1"),
    language: Optional[str] = Form(None)
):
    global model, current_dev
    target_dev, target_ctype = get_optimal_whisper_config(800)
    if target_dev != current_dev:
        try:
            model = WhisperModel("small", device=target_dev, compute_type=target_ctype, download_root=MODELS_DIR)
            current_dev = target_dev
        except Exception:
            pass

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
            "duration": round(info.duration, 2),
            "device_used": current_dev
        }
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)
