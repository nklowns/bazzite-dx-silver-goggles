import io, os, time, subprocess, tempfile, scipy.io.wavfile as wavfile
from fastapi import FastAPI, UploadFile, File, Response
from pydantic import BaseModel
from typing import Optional
from transformers import AutoProcessor, MusicgenForConditionalGeneration

app = FastAPI(title="AI Studio — Music Generation & Stem Separation API")

print("Carregando MusicGen Small no servidor de Música...")
processor = AutoProcessor.from_pretrained("facebook/musicgen-small")
model = MusicgenForConditionalGeneration.from_pretrained("facebook/musicgen-small")
model.to("cpu")
print("✅ MusicGen Small pronto na CPU!")

class MusicRequest(BaseModel):
    prompt: str
    duration_seconds: Optional[int] = 10

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "service": "AI Music & Stem Separation",
        "model": "facebook/musicgen-small",
        "stem_separator": "demucs (htdemucs)"
    }

@app.post("/generate_music")
def generate_music(req: MusicRequest):
    tokens = min(max(req.duration_seconds * 50, 100), 1500)
    inputs = processor(text=[req.prompt], padding=True, return_tensors="pt")
    audio_values = model.generate(**inputs, max_new_tokens=tokens)
    
    sr = model.config.audio_encoder.sampling_rate
    audio_data = audio_values[0, 0].cpu().numpy()
    
    buf = io.BytesIO()
    wavfile.write(buf, rate=sr, data=audio_data)
    return Response(content=buf.getvalue(), media_type="audio/wav")

@app.post("/separate_stems")
async def separate_stems(file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_in:
        tmp_in.write(await file.read())
        tmp_path = tmp_in.name
    
    out_dir = tempfile.mkdtemp()
    cmd = ["demucs", "-n", "htdemucs", "--two-stems=vocals", "-d", "cpu", "-o", out_dir, tmp_path]
    subprocess.run(cmd, check=True)
    
    # Retorna o instrumental limpo como padrão
    base_name = os.path.splitext(os.path.basename(tmp_path))[0]
    no_vocals = os.path.join(out_dir, "htdemucs", base_name, "no_vocals.wav")
    
    with open(no_vocals, "rb") as f:
        data = f.read()
    return Response(content=data, media_type="audio/wav")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)
