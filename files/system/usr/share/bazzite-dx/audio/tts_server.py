import io, os, time, wave, torch, librosa, soundfile as sf
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel
from typing import Optional
from piper import PiperVoice
from seed_vc.modules.openvoice.api import ToneColorConverter

app = FastAPI(title="AI Studio — Multi-Language TTS & Voice Cloning API")

MODELS_DIR = "/models"
if not os.path.exists(MODELS_DIR):
    MODELS_DIR = "/var/srv/comfyui/audio/tts/models"

VOICES_DIR = "/voices"
if not os.path.exists(VOICES_DIR):
    VOICES_DIR = "/var/srv/comfyui/audio/voices"

# Inicializar Tone Converter
ckpt_converter = f"{MODELS_DIR}/openvoice_v2/converter"
converter = ToneColorConverter(f"{ckpt_converter}/config.json", device="cpu")
converter.load_ckpt(f"{ckpt_converter}/checkpoint.pth")

# Cache de embeddings
user_ref_audio = f"{VOICES_DIR}/user_voice_clean_7s.wav"
tgt_user_se = None

def get_se(audio_path):
    wav, sr = librosa.load(audio_path, sr=24000)
    wav_tensor = torch.FloatTensor(wav).unsqueeze(0)
    lengths = torch.LongTensor([wav_tensor.size(1)])
    with torch.no_grad():
        se = converter.extract_se(wav_tensor, lengths)
    return se, wav_tensor, lengths

if os.path.exists(user_ref_audio):
    try:
        tgt_user_se, _, _ = get_se(user_ref_audio)
        print("✅ Embedding do usuário carregado no servidor TTS!")
    except Exception as e:
        print(f"⚠️ Aviso ao carregar embedding do usuário: {e}")

PIPER_VOICES = {
    "pt-br": {
        "model": f"{MODELS_DIR}/piper_ptbr/pt_BR-faber-medium.onnx",
        "config": f"{MODELS_DIR}/piper_ptbr/pt_BR-faber-medium.onnx.json"
    },
    "en-us": {
        "model": f"{MODELS_DIR}/piper_en/en_US-lessac-medium.onnx",
        "config": f"{MODELS_DIR}/piper_en/en_US-lessac-medium.onnx.json"
    },
    "es-es": {
        "model": f"{MODELS_DIR}/piper_es/es_ES-davefx-medium.onnx",
        "config": f"{MODELS_DIR}/piper_es/es_ES-davefx-medium.onnx.json"
    }
}

class SpeechRequest(BaseModel):
    model: Optional[str] = "tts-1"
    input: str
    voice: Optional[str] = "pt-br"
    speed: Optional[float] = 1.0

class SynthesizeRequest(BaseModel):
    text: str
    lang: Optional[str] = "pt-br"
    clone: Optional[bool] = False

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "service": "AI Voice & TTS",
        "languages": list(PIPER_VOICES.keys()),
        "user_clone_ready": tgt_user_se is not None
    }

def generate_speech(text: str, lang: str = "pt-br", clone: bool = False) -> bytes:
    lang_key = lang.lower()
    if lang_key not in PIPER_VOICES:
        lang_key = "pt-br" if any(c in text.lower() for c in "ãõéáíóúç") else "en-us"
    
    cfg = PIPER_VOICES[lang_key]
    voice = PiperVoice.load(cfg["model"], config_path=cfg["config"])
    
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        voice.synthesize_wav(text, wf)
    base_wav_bytes = buf.getvalue()
    
    if not clone or tgt_user_se is None:
        return base_wav_bytes
    
    # Aplicar Tone Color Converter
    src_wav, sr = sf.read(io.BytesIO(base_wav_bytes))
    src_tensor = torch.FloatTensor(src_wav).unsqueeze(0)
    src_lengths = torch.LongTensor([src_tensor.size(1)])
    with torch.no_grad():
        src_se = converter.extract_se(src_tensor, src_lengths)
        converted_wav = converter.convert(
            src_waves=src_tensor,
            src_wave_lengths=src_lengths,
            src_se=src_se,
            tgt_se=tgt_user_se,
            tau=0.3
        )
    
    out_buf = io.BytesIO()
    sf.write(out_buf, converted_wav[0, 0].cpu().numpy(), 24000, format="WAV")
    return out_buf.getvalue()

@app.post("/v1/audio/speech")
def openai_speech(req: SpeechRequest):
    clone_mode = "user" in req.voice.lower() or "clone" in req.voice.lower()
    lang = "en-us" if req.voice.lower() in ["alloy", "echo", "fable", "onyx", "nova", "shimmer", "en"] else "pt-br"
    wav_bytes = generate_speech(req.input, lang=lang, clone=clone_mode)
    return Response(content=wav_bytes, media_type="audio/wav")

@app.post("/synthesize")
def synthesize(req: SynthesizeRequest):
    wav_bytes = generate_speech(req.text, lang=req.lang, clone=req.clone)
    return Response(content=wav_bytes, media_type="audio/wav")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)
