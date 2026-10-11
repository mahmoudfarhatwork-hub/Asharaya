"""
Kaggle Audio Generator — Voices + SFX (قابل للاستئناف زي سكريبت الـ3D)
================================================================================
بيولّد: (1) أصوات NPCs بشخصيات مختلفة عن طريق Bark، (2) مؤثرات صوتية عن طريق
AudioLDM2 — الاتنين مفتوحين المصدر بالكامل. بيتبع نفس مبدأ الاستئناف: يتأكد
من اللي خلص على HuggingFace الأول، ويشتغل بس على الباقي، ويرفع أول بأول.

قبل التشغيل:
1. Settings > Accelerator > GPU T4 x2
2. Settings > Internet > On
3. Add-ons > Secrets > ضيف HF_TOKEN
"""

import subprocess
subprocess.run(["pip", "install", "-q", "diffusers", "transformers", "accelerate",
                 "huggingface_hub", "scipy", "soundfile"], check=True)

import os
import time
import torch
import torch.multiprocessing as mp
import scipy.io.wavfile
from pathlib import Path
from huggingface_hub import HfApi, create_repo

HF_REPO_ID = "your-username/asharaya-audio-assets"   # زي ما اتفقنا، ريبو جديد مخصص للصوت

# ══════════════════════════════════════════════════════════
# 1) أصوات NPCs — كل NPC بصوت مختلف (Bark بيدعم presets متنوعة جاهزة)
# ══════════════════════════════════════════════════════════
VOICE_LINES = [
    {"path": "voices/elara_greeting", "text": "Welcome, traveler. The forest ahead hides more than trees.", "voice_preset": "v2/en_speaker_9"},
    {"path": "voices/aldrik_shop_open", "text": "Looking to trade? I have the finest goods this side of the village.", "voice_preset": "v2/en_speaker_6"},
    {"path": "voices/bern_shop_open", "text": "Bring me iron, I'll bring you steel.", "voice_preset": "v2/en_speaker_2"},
    {"path": "voices/goblin_boss_taunt", "text": "You dare enter my domain? [laughs] You will regret this.", "voice_preset": "v2/en_speaker_0"},
    {"path": "voices/night_guard_warning", "text": "Careful out there. There are goblins in the cave, and worse at night.", "voice_preset": "v2/en_speaker_3"},
    # زوّد أي عدد من جمل الـ NPCs براحتك
]

# ══════════════════════════════════════════════════════════
# 2) مؤثرات صوتية — AudioLDM2 بيولّد صوت قصير من وصف نصي
# ══════════════════════════════════════════════════════════
SFX_LIST = [
    {"path": "sfx/sword_clash", "prompt": "metal sword clashing against another sword, sharp clang", "duration": 3},
    {"path": "sfx/slime_hit", "prompt": "wet squishy slime creature being hit, splat sound", "duration": 2},
    {"path": "sfx/footsteps_grass", "prompt": "footsteps walking on grass, single step", "duration": 1.5},
    {"path": "sfx/chest_open", "prompt": "wooden treasure chest creaking open", "duration": 2.5},
    {"path": "sfx/coin_pickup", "prompt": "coins jingling, picking up gold coins", "duration": 1.5},
    {"path": "sfx/level_up", "prompt": "magical sparkling chime, character leveling up in a fantasy game", "duration": 2.5},
    {"path": "sfx/torch_ignite", "prompt": "torch igniting with a whoosh of fire", "duration": 1.5},
    {"path": "sfx/wolf_growl", "prompt": "wolf growling menacingly", "duration": 2},
    # زوّد أي عدد براحتك
]

MAX_RUNTIME_HOURS = 11.0
OUTPUT_DIR_BASE = Path("/kaggle/working/audio_gpu")


def get_pending_items(all_items, hf_token):
    api = HfApi(token=hf_token)
    try:
        create_repo(HF_REPO_ID, repo_type="dataset", token=hf_token, exist_ok=True)
        existing_files = set(api.list_repo_files(HF_REPO_ID, repo_type="dataset"))
    except Exception as e:
        print(f"⚠️ {e}")
        existing_files = set()
    pending = [item for item in all_items if f"{item['path']}.wav" not in existing_files]
    print(f"📊 {len(all_items) - len(pending)}/{len(all_items)} خلصوا قبل كده. باقي {len(pending)}.")
    return pending


def split_list(lst, n):
    k, m = divmod(len(lst), n)
    return [lst[i * k + min(i, m):(i + 1) * k + min(i + 1, m)] for i in range(n)]


def upload_now(api, local_path, remote_path, hf_token):
    try:
        api.upload_file(path_or_fileobj=str(local_path), path_in_repo=remote_path,
                         repo_id=HF_REPO_ID, repo_type="dataset", token=hf_token)
        print(f"   ⬆️  اترفع: {remote_path}")
    except Exception as e:
        print(f"   ❌ فشل رفع {remote_path}: {e}")


def voice_worker(items, device, hf_token, start_time):
    if not items:
        return
    from transformers import AutoProcessor, BarkModel

    api = HfApi(token=hf_token)
    out_dir = OUTPUT_DIR_BASE / device.replace(":", "_")
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[{device}] 📥 تحميل Bark (أصوات الشخصيات)...")
    processor = AutoProcessor.from_pretrained("suno/bark")
    model = BarkModel.from_pretrained("suno/bark", torch_dtype=torch.float16).to(device)

    for item in items:
        if (time.time() - start_time) / 3600 >= MAX_RUNTIME_HOURS:
            print(f"[{device}] ⏰ وقف بأمان — شغّل تاني وهيكمل")
            break
        try:
            print(f"[{device}] 🗣️  صوت لـ: {item['path']}")
            inputs = processor(item["text"], voice_preset=item["voice_preset"]).to(device)
            audio_array = model.generate(**inputs).cpu().numpy().squeeze()

            local_path = out_dir / f"{item['path'].replace('/', '_')}.wav"
            local_path.parent.mkdir(parents=True, exist_ok=True)
            scipy.io.wavfile.write(str(local_path), rate=model.generation_config.sample_rate, data=audio_array)

            upload_now(api, local_path, f"{item['path']}.wav", hf_token)
            print(f"[{device}] ✅ خلص: {item['path']}")
        except Exception as e:
            print(f"[{device}] ❌ خطأ في {item['path']}: {e}")
            continue

    del model
    torch.cuda.empty_cache()


def sfx_worker(items, device, hf_token, start_time):
    if not items:
        return
    from diffusers import AudioLDM2Pipeline

    api = HfApi(token=hf_token)
    out_dir = OUTPUT_DIR_BASE / device.replace(":", "_") / "sfx"
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[{device}] 📥 تحميل AudioLDM2 (مؤثرات صوتية)...")
    pipe = AudioLDM2Pipeline.from_pretrained("cvssp/audioldm2", torch_dtype=torch.float16).to(device)

    for item in items:
        if (time.time() - start_time) / 3600 >= MAX_RUNTIME_HOURS:
            print(f"[{device}] ⏰ وقف بأمان — شغّل تاني وهيكمل")
            break
        try:
            print(f"[{device}] 🔊 مؤثر صوتي لـ: {item['path']}")
            audio = pipe(
                prompt=item["prompt"], num_inference_steps=50,
                audio_length_in_s=item.get("duration", 2.0),
            ).audios[0]

            local_path = out_dir / f"{item['path'].split('/')[-1]}.wav"
            scipy.io.wavfile.write(str(local_path), rate=16000, data=audio)

            upload_now(api, local_path, f"{item['path']}.wav", hf_token)
            print(f"[{device}] ✅ خلص: {item['path']}")
        except Exception as e:
            print(f"[{device}] ❌ خطأ في {item['path']}: {e}")
            continue

    del pipe
    torch.cuda.empty_cache()


if __name__ == "__main__":
    hf_token = os.environ.get("HF_TOKEN") or __import__("kaggle_secrets").UserSecretsClient().get_secret("HF_TOKEN")
    start_time = time.time()
    num_gpus = torch.cuda.device_count()
    print(f"✅ عدد الـ GPU: {num_gpus}")

    pending_voices = get_pending_items(VOICE_LINES, hf_token)
    pending_sfx = get_pending_items(SFX_LIST, hf_token)

    if not pending_voices and not pending_sfx:
        print("🎉 كل حاجة خلصت بالفعل!")
    elif num_gpus >= 2:
        # GPU 0: الأصوات (Bark) — GPU 1: المؤثرات (AudioLDM2) — يشتغلوا بالتوازي
        mp.set_start_method("spawn", force=True)
        p1 = mp.Process(target=voice_worker, args=(pending_voices, "cuda:0", hf_token, start_time))
        p2 = mp.Process(target=sfx_worker, args=(pending_sfx, "cuda:1", hf_token, start_time))
        p1.start(); p2.start()
        p1.join(); p2.join()
    else:
        device = "cuda:0" if num_gpus == 1 else "cpu"
        voice_worker(pending_voices, device, hf_token, start_time)
        sfx_worker(pending_sfx, device, hf_token, start_time)

    still_voices = get_pending_items(VOICE_LINES, hf_token)
    still_sfx = get_pending_items(SFX_LIST, hf_token)
    remaining = len(still_voices) + len(still_sfx)
    if remaining:
        print(f"\n⏳ باقي {remaining} عنصر. شغّل تاني (منك أو من صاحبك) وهيكمل تلقائي.")
    else:
        print(f"\n🎉 كل حاجة خلصت! على: https://huggingface.co/datasets/{HF_REPO_ID}")
