import io, os, time, subprocess, tempfile, torch, scipy.io.wavfile as wavfile
from fastapi import FastAPI, UploadFile, File, Response
from pydantic import BaseModel
from typing import Optional
from transformers import AutoProcessor, MusicgenForConditionalGeneration

app = FastAPI(title="AI Studio — Hybrid Music Generation & Stem Separation API")

def get_optimal_device(min_free_vram_mb=2000) -> str:
    if not torch.cuda.is_available():
        return "cpu"
    try:
        free_bytes, _ = torch.cuda.mem_get_info()
        free_mb = free_bytes / (1024 * 1024)
        if free_mb >= min_free_vram_mb:
            return "cuda"
    except Exception:
        pass
    return "cpu"

print("Inicializando MusicGen Small com suporte Híbrido GPU/CPU...")
processor = AutoProcessor.from_pretrained("facebook/musicgen-small")
model = MusicgenForConditionalGeneration.from_pretrained("facebook/musicgen-small")
initial_dev = get_optimal_device(2000)
model.to(initial_dev)
print(f"✅ MusicGen Small pronto no dispositivo inicial: {initial_dev.upper()}!")

class MusicRequest(BaseModel):
    prompt: str
    duration_seconds: Optional[int] = 10

@app.get("/health")
def health():
    dev = get_optimal_device(2000)
    free_mb = round(torch.cuda.mem_get_info()[0] / (1024*1024), 1) if torch.cuda.is_available() else 0
    return {
        "status": "healthy",
        "service": "AI Music & Stem Separation (Hybrid)",
        "active_device": dev,
        "free_vram_mb": free_mb,
        "model": "facebook/musicgen-small",
        "stem_separator": "demucs (htdemucs)"
    }

@app.post("/generate_music")
def generate_music(req: MusicRequest):
    dev = get_optimal_device(2000)
    model.to(dev)
    
    tokens = min(max(req.duration_seconds * 50, 100), 1500)
    inputs = processor(text=[req.prompt], padding=True, return_tensors="pt").to(dev)
    
    with torch.no_grad():
        audio_values = model.generate(**inputs, max_new_tokens=tokens)
    
    sr = model.config.audio_encoder.sampling_rate
    audio_data = audio_values[0, 0].cpu().numpy()
    
    buf = io.BytesIO()
    wavfile.write(buf, rate=sr, data=audio_data)
    return Response(content=buf.getvalue(), media_type="audio/wav")

@app.post("/separate_stems")
async def separate_stems(file: UploadFile = File(...)):
    dev = get_optimal_device(1500)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_in:
        tmp_in.write(await file.read())
        tmp_path = tmp_in.name
    
    out_dir = tempfile.mkdtemp()
    cmd = ["demucs", "-n", "htdemucs", "--two-stems=vocals", "-d", dev, "-o", out_dir, tmp_path]
    subprocess.run(cmd, check=True)
    
    base_name = os.path.splitext(os.path.basename(tmp_path))[0]
    no_vocals = os.path.join(out_dir, "htdemucs", base_name, "no_vocals.wav")
    
    with open(no_vocals, "rb") as f:
        data = f.read()
    return Response(content=data, media_type="audio/wav")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)
