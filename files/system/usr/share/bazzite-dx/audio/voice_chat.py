#!/usr/bin/env python3
import sys, os, time, subprocess, tempfile, requests, json

STT_URL = os.getenv("STT_URL", "http://localhost:61388/v1/audio/transcriptions")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:61382/api/generate")
TTS_URL = os.getenv("TTS_URL", "http://localhost:61386/v1/audio/speech")

USE_CLONE = "--clone" in sys.argv

print("=" * 60)
print("🎙️  BAZZITE AI VOICE ASSISTANT (CONVERSATIONAL LOOP)")
print("=" * 60)
print(f"Modo de Voz: {'🧬 Sua Voz Clonada (--clone)' if USE_CLONE else '🗣️ Voz Padrão Nativa'}")
print("Pressione Ctrl+C para sair.\n")

def record_audio(duration_sec=5):
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp.close()
    print(f"\n🎤 Gravando microfone por {duration_sec}s... (Fale agora!)")
    if subprocess.run(["which", "pw-record"], capture_output=True).returncode == 0:
        subprocess.run(["pw-record", "--rate", "24000", "--channels", "1", tmp.name], timeout=duration_sec)
    else:
        subprocess.run(["arecord", "-d", str(duration_sec), "-f", "cd", "-t", "wav", tmp.name], capture_output=True)
    return tmp.name

def main():
    while True:
        try:
            input("\n👉 Pressione ENTER para falar (ou Ctrl+C para sair)... ")
            audio_path = record_audio(duration_sec=5)
            
            # 1. Transcrever com Faster-Whisper
            print("👂 Transcrevendo áudio via Faster-Whisper...")
            t0 = time.time()
            with open(audio_path, "rb") as f:
                res = requests.post(STT_URL, files={"file": f}, timeout=10)
            os.remove(audio_path)
            
            if res.status_code != 200:
                print(f"❌ Erro no STT ({res.status_code}): {res.text}")
                continue
            
            user_text = res.json().get("text", "").strip()
            detected_lang = res.json().get("language", "pt")
            if not user_text:
                print("⚠️ Nenhuma fala detectada.")
                continue
            
            print(f"🗣️  Você ({detected_lang.upper()}): \"{user_text}\" (em {time.time()-t0:.2f}s)")
            
            # 2. Raciocínio com Ollama MoE
            print("🧠 Raciocinando com o modelo MoE...")
            t1 = time.time()
            ollama_payload = {
                "model": "deepseek-coder-v2:16b",
                "prompt": f"Responda de forma concisa em 1 ou 2 frases no mesmo idioma da pergunta ({detected_lang}): {user_text}",
                "stream": False
            }
            res_llm = requests.post(OLLAMA_URL, json=ollama_payload, timeout=30)
            if res_llm.status_code != 200:
                print(f"❌ Erro no Ollama: {res_llm.text}")
                continue
            
            assistant_reply = res_llm.json().get("response", "").strip()
            print(f"🤖 Assistente: \"{assistant_reply}\" (em {time.time()-t1:.2f}s)")
            
            # 3. Síntese de Voz / TTS
            print("🗣️  Sintetizando voz...")
            t2 = time.time()
            tts_voice = "user_clone" if USE_CLONE else ("pt-br" if detected_lang == "pt" else "en-us")
            tts_payload = {
                "input": assistant_reply,
                "voice": tts_voice,
                "model": "tts-1"
            }
            res_tts = requests.post(TTS_URL, json=tts_payload, timeout=15)
            if res_tts.status_code != 200:
                print(f"❌ Erro no TTS: {res_tts.text}")
                continue
            
            tmp_out = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
            tmp_out.write(res_tts.content)
            tmp_out.close()
            
            # 4. Reproduzir no alto-falante
            print(f"🔊 Reproduzindo resposta (síntese em {time.time()-t2:.2f}s)...")
            subprocess.run(["pw-play", tmp_out.name], check=True)
            os.remove(tmp_out.name)
            
        except KeyboardInterrupt:
            print("\n👋 Sessão de conversa por voz finalizada.")
            break
        except Exception as e:
            print(f"\n⚠️ Ocorreu um erro: {e}")

if __name__ == "__main__":
    main()
