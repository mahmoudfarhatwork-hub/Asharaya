"""
Kaggle Master Asset Generator #1 — Asharaya
================================================================================
سكريبت واحد شامل: يولّد 3D (أسلحة/مباني/عناصر/موارد/أشجار)، المؤثرات
الضوئية (VFX)، أصوات NPCs، الموسيقى، والمؤثرات الصوتية (SFX) — ويرفعهم على
ريبو جديد يُنشأ تلقائياً على HuggingFace (الـ HF_TOKEN بصلاحية Write كافي
لإنشائه، مفيش خطوة يدوية مطلوبة منك).

ملحوظة: الوحوش مش موجودة هنا — عندك بالفعل مجموعة وحوش حقيقية (5 منقولين
فعلاً جوه المشروع، والباقي في Drive) — مفيش داعي نكررها.

قابل للاستئناف بالكامل: يتأكد الأول من اللي خلص، ويكمل من اللي فاضل بس،
ويرفع كل عنصر أول ما يخلص.

قبل التشغيل:
1. Settings > Accelerator > GPU T4 x2
2. Settings > Internet > On
3. Add-ons > Secrets > ضيف HF_TOKEN (صلاحية Write)

بعد ما يخلص: قولي "خلص" وهقولك تحمّل إيه بالظبط وتحطه فين عشان AutoSetup.gd
يوزعه تلقائي جوه Godot.
"""

import subprocess
subprocess.run(["pip", "install", "-q", "diffusers", "transformers", "accelerate",
                 "huggingface_hub", "scipy", "soundfile", "safetensors",
                 "rembg", "trimesh", "onnxruntime-gpu"], check=True)
subprocess.run(["pip", "install", "-q", "git+https://github.com/Tencent-Hunyuan/Hunyuan3D-2.git"], check=True)

import os
import time
import torch
import scipy.io.wavfile
from pathlib import Path
from PIL import Image
from huggingface_hub import HfApi, create_repo

# ══════════════════════════════════════════════════════════
# الإعدادات
# ══════════════════════════════════════════════════════════

HF_REPO_ID = "your-username/asharaya-full-assets"   # هيتعمل تلقائي أول مرة لو مش موجود
MAX_RUNTIME_HOURS = 11.0
OUTPUT_DIR_BASE = Path("/kaggle/working/master_assets")

# ── 0) موديلات 3D (أسلحة/مباني/عناصر/موارد/أشجار — الوحوش والشجرة الأساسية
#      موجودين بالفعل عندك في Drive، مفيش داعي نكررهم هنا) ──
#
# ⚠️ ملحوظة صادقة: النموذج اللي بنستخدمه (Hunyuan3D-2mini) بيتعامل صح مع
# عناصر منفردة بسيطة (سلاح، صندوق، شجرة). المباني (بيوت/دكاكين) أعقد بكتير
# (تفاصيل معمارية، غرف داخلية) — النتيجة هتكون "شكل تقريبي/واجهة" مقبول
# كـ placeholder للاختبار، مش تصميم معماري نهائي جاهز للعبة كاملة.

PROPS_3D_LIST = [
    # أسلحة
    {"path": "weapons/rusty_sword", "prompt": "rusty medieval sword, isolated on white background, game asset"},
    {"path": "weapons/iron_sword", "prompt": "polished iron sword, isolated on white background, game asset"},
    {"path": "weapons/wooden_staff", "prompt": "wooden magic staff, isolated on white background, game asset"},
    {"path": "weapons/iron_axe", "prompt": "small iron axe, isolated on white background, game asset"},
    {"path": "weapons/wooden_shield", "prompt": "round wooden shield, isolated on white background, game asset"},
    {"path": "weapons/farmer_sickle", "prompt": "rusty farming sickle tool, isolated on white background, game asset"},
    {"path": "weapons/blacksmith_hammer", "prompt": "small blacksmith hammer, isolated on white background, game asset"},

    # مباني (placeholder تقريبي — راجع الملحوظة فوق)
    {"path": "buildings/village_house", "prompt": "small medieval stone cottage, low poly game asset, isolated on white background"},
    {"path": "buildings/blacksmith_shop", "prompt": "medieval blacksmith workshop building exterior, low poly game asset, isolated on white background"},
    {"path": "buildings/trader_stall", "prompt": "medieval market trader stall with cloth awning, low poly game asset, isolated on white background"},
    {"path": "buildings/abandoned_house", "prompt": "ruined abandoned medieval house, low poly game asset, isolated on white background"},

    # عناصر وموارد
    {"path": "resources/iron_ore", "prompt": "raw iron ore rock chunk, isolated on white background, game asset"},
    {"path": "resources/wood_log", "prompt": "cut wood log, isolated on white background, game asset"},
    {"path": "resources/herb", "prompt": "small medicinal herb plant, isolated on white background, game asset"},
    {"path": "resources/berry_bush", "prompt": "small bush with red berries, isolated on white background, game asset"},
    {"path": "resources/gold_coins_pile", "prompt": "small pile of gold coins, isolated on white background, game asset"},

    # عناصر (Items)
    {"path": "items/wooden_chest", "prompt": "closed wooden treasure chest, isolated on white background, game asset"},
    {"path": "items/clay_pot", "prompt": "simple clay pot, isolated on white background, game asset"},
    {"path": "items/torch", "prompt": "medieval wall torch with flame, isolated on white background, game asset"},
    {"path": "items/bread_loaf", "prompt": "half loaf of bread, isolated on white background, game asset"},
    {"path": "items/water_flask", "prompt": "leather water flask, isolated on white background, game asset"},
    {"path": "items/health_potion", "prompt": "small red health potion bottle, isolated on white background, game asset"},

    # أشجار إضافية (متنوعة عن اللي عندك في Drive بالفعل)
    {"path": "environment/pine_tree", "prompt": "low poly pine tree, isolated on white background, game asset"},
    {"path": "environment/broadleaf_tree", "prompt": "low poly broad-leaf forest tree, isolated on white background, game asset"},
    {"path": "environment/dead_tree", "prompt": "low poly dead bare tree branches, isolated on white background, game asset"},
]

# ── 1) المؤثرات الضوئية (VFX) — تكسجرز شفافة لتأثيرات بصرية ──
VFX_LIST = [
    {"path": "vfx/fire_particle", "prompt": "magic fire particle effect, glowing orange flame, transparent background, game VFX sprite sheet style"},
    {"path": "vfx/magic_sparkle", "prompt": "glowing blue magic sparkle particle effect, transparent background, fantasy game VFX"},
    {"path": "vfx/torch_glow", "prompt": "warm torch light glow, radial gradient, transparent background, game lighting effect"},
    {"path": "vfx/heal_glow", "prompt": "green healing glow particle effect, soft radial light, transparent background, game VFX"},
    {"path": "vfx/level_up_burst", "prompt": "golden light burst radial effect, transparent background, RPG level up VFX"},
    {"path": "vfx/dark_curse_smoke", "prompt": "dark purple curse smoke effect, wispy, transparent background, dark fantasy VFX"},
    {"path": "vfx/slash_effect", "prompt": "white sword slash motion trail effect, transparent background, game VFX"},
    {"path": "vfx/moonlight_ambient", "prompt": "soft blue moonlight ambient glow overlay, transparent background, night lighting effect"},
    # زوّد براحتك
]

# ── 2) أصوات NPCs ──
VOICE_LINES = [
    {"path": "voices/elara_greeting", "text": "Welcome, traveler. The forest ahead hides more than trees.", "voice_preset": "v2/en_speaker_9"},
    {"path": "voices/aldrik_shop_open", "text": "Looking to trade? I have the finest goods this side of the village.", "voice_preset": "v2/en_speaker_6"},
    {"path": "voices/bern_shop_open", "text": "Bring me iron, I'll bring you steel.", "voice_preset": "v2/en_speaker_2"},
    {"path": "voices/goblin_boss_taunt", "text": "You dare enter my domain? You will regret this.", "voice_preset": "v2/en_speaker_0"},
    {"path": "voices/night_guard_warning", "text": "Careful out there. There are goblins in the cave, and worse at night.", "voice_preset": "v2/en_speaker_3"},
]

# ── 3) الموسيقى (MusicGen) — مقاطع خلفية قصيرة قابلة للتكرار ──
MUSIC_LIST = [
    {"path": "music/village_theme", "prompt": "calm medieval fantasy village ambient music, lute and flute, peaceful loop", "duration": 20},
    {"path": "music/forest_theme", "prompt": "mysterious dark fantasy forest ambient music, low strings, tense atmosphere", "duration": 20},
    {"path": "music/dungeon_theme", "prompt": "dark ominous dungeon background music, deep drones, distant drums", "duration": 20},
    {"path": "music/boss_battle_theme", "prompt": "intense dark fantasy boss battle music, epic drums and choir, high energy", "duration": 20},
]

# ── 4) المؤثرات الصوتية (SFX) ──
SFX_LIST = [
    {"path": "sfx/sword_clash", "prompt": "metal sword clashing against another sword, sharp clang", "duration": 3},
    {"path": "sfx/slime_hit", "prompt": "wet squishy slime creature being hit, splat sound", "duration": 2},
    {"path": "sfx/footsteps_grass", "prompt": "footsteps walking on grass, single step", "duration": 1.5},
    {"path": "sfx/chest_open", "prompt": "wooden treasure chest creaking open", "duration": 2.5},
    {"path": "sfx/coin_pickup", "prompt": "coins jingling, picking up gold coins", "duration": 1.5},
    {"path": "sfx/level_up", "prompt": "magical sparkling chime, character leveling up in a fantasy game", "duration": 2.5},
    {"path": "sfx/torch_ignite", "prompt": "torch igniting with a whoosh of fire", "duration": 1.5},
    {"path": "sfx/wolf_growl", "prompt": "wolf growling menacingly", "duration": 2},
]

# ══════════════════════════════════════════════════════════
# أدوات مشتركة (استئناف + رفع)
# ══════════════════════════════════════════════════════════

def setup_repo(hf_token):
    api = HfApi(token=hf_token)
    create_repo(HF_REPO_ID, repo_type="dataset", token=hf_token, exist_ok=True)
    print(f"✅ الريبو جاهز: https://huggingface.co/datasets/{HF_REPO_ID}")
    return api


def get_pending(api, all_items, ext=".wav"):
    try:
        existing = set(api.list_repo_files(HF_REPO_ID, repo_type="dataset"))
    except Exception as e:
        print(f"⚠️ {e}")
        existing = set()
    pending = [i for i in all_items if f"{i['path']}{ext}" not in existing]
    print(f"📊 {len(all_items) - len(pending)}/{len(all_items)} خلصوا. باقي {len(pending)}.")
    return pending


def upload_now(api, local_path, remote_path, hf_token):
    try:
        api.upload_file(path_or_fileobj=str(local_path), path_in_repo=remote_path,
                         repo_id=HF_REPO_ID, repo_type="dataset", token=hf_token)
        print(f"   ⬆️  اترفع: {remote_path}")
    except Exception as e:
        print(f"   ❌ فشل رفع {remote_path}: {e}")


def time_left(start_time):
    return (time.time() - start_time) / 3600 < MAX_RUNTIME_HOURS


# ══════════════════════════════════════════════════════════
# GPU 0: المؤثرات الضوئية (SDXL) + أصوات NPCs (Bark)
# ══════════════════════════════════════════════════════════

def worker_gpu0(vfx_items, voice_items, hf_token, start_time):
    api = HfApi(token=hf_token)
    device = "cuda:0"
    out_dir = OUTPUT_DIR_BASE / "gpu0"
    out_dir.mkdir(parents=True, exist_ok=True)

    if vfx_items:
        from diffusers import StableDiffusionXLPipeline
        print("[GPU0] 📥 تحميل SDXL للمؤثرات الضوئية...")
        img_pipe = StableDiffusionXLPipeline.from_pretrained(
            "stabilityai/stable-diffusion-xl-base-1.0", torch_dtype=torch.float16, variant="fp16"
        ).to(device)

        for item in vfx_items:
            if not time_left(start_time):
                print("[GPU0] ⏰ وقف بأمان"); break
            try:
                print(f"[GPU0] ✨ VFX: {item['path']}")
                image = img_pipe(
                    prompt=item["prompt"] + ", plain black background, high contrast, centered",
                    negative_prompt="blurry, low quality, watermark, text",
                    num_inference_steps=30, guidance_scale=7.5,
                ).images[0]
                local_path = out_dir / f"{item['path'].replace('/', '_')}.png"
                image.save(local_path)
                upload_now(api, local_path, f"{item['path']}.png", hf_token)
            except Exception as e:
                print(f"[GPU0] ❌ {item['path']}: {e}")
        del img_pipe
        torch.cuda.empty_cache()

    if voice_items:
        from transformers import AutoProcessor, BarkModel
        print("[GPU0] 📥 تحميل Bark للأصوات...")
        processor = AutoProcessor.from_pretrained("suno/bark")
        bark_model = BarkModel.from_pretrained("suno/bark", torch_dtype=torch.float16).to(device)

        for item in voice_items:
            if not time_left(start_time):
                print("[GPU0] ⏰ وقف بأمان"); break
            try:
                print(f"[GPU0] 🗣️  صوت: {item['path']}")
                inputs = processor(item["text"], voice_preset=item["voice_preset"]).to(device)
                audio = bark_model.generate(**inputs).cpu().numpy().squeeze()
                local_path = out_dir / f"{item['path'].replace('/', '_')}.wav"
                scipy.io.wavfile.write(str(local_path), rate=bark_model.generation_config.sample_rate, data=audio)
                upload_now(api, local_path, f"{item['path']}.wav", hf_token)
            except Exception as e:
                print(f"[GPU0] ❌ {item['path']}: {e}")
        del bark_model
        torch.cuda.empty_cache()


# ══════════════════════════════════════════════════════════
# GPU 1: الموسيقى (MusicGen) + المؤثرات الصوتية (AudioLDM2)
# ══════════════════════════════════════════════════════════

def worker_gpu1(music_items, sfx_items, hf_token, start_time):
    api = HfApi(token=hf_token)
    device = "cuda:1"
    out_dir = OUTPUT_DIR_BASE / "gpu1"
    out_dir.mkdir(parents=True, exist_ok=True)

    if music_items:
        from transformers import MusicgenForConditionalGeneration, AutoProcessor as MGProcessor
        print("[GPU1] 📥 تحميل MusicGen للموسيقى...")
        mg_processor = MGProcessor.from_pretrained("facebook/musicgen-small")
        mg_model = MusicgenForConditionalGeneration.from_pretrained("facebook/musicgen-small").to(device)

        for item in music_items:
            if not time_left(start_time):
                print("[GPU1] ⏰ وقف بأمان"); break
            try:
                print(f"[GPU1] 🎵 موسيقى: {item['path']}")
                inputs = mg_processor(text=[item["prompt"]], padding=True, return_tensors="pt").to(device)
                tokens = int(item.get("duration", 20) * 50)  # ~50 توكن/ثانية تقريبي
                audio = mg_model.generate(**inputs, max_new_tokens=tokens)[0, 0].cpu().numpy()
                local_path = out_dir / f"{item['path'].replace('/', '_')}.wav"
                scipy.io.wavfile.write(str(local_path), rate=mg_model.config.audio_encoder.sampling_rate, data=audio)
                upload_now(api, local_path, f"{item['path']}.wav", hf_token)
            except Exception as e:
                print(f"[GPU1] ❌ {item['path']}: {e}")
        del mg_model
        torch.cuda.empty_cache()

    if sfx_items:
        from diffusers import AudioLDM2Pipeline
        print("[GPU1] 📥 تحميل AudioLDM2 للمؤثرات الصوتية...")
        sfx_pipe = AudioLDM2Pipeline.from_pretrained("cvssp/audioldm2", torch_dtype=torch.float16).to(device)

        for item in sfx_items:
            if not time_left(start_time):
                print("[GPU1] ⏰ وقف بأمان"); break
            try:
                print(f"[GPU1] 🔊 SFX: {item['path']}")
                audio = sfx_pipe(prompt=item["prompt"], num_inference_steps=50,
                                  audio_length_in_s=item.get("duration", 2.0)).audios[0]
                local_path = out_dir / f"{item['path'].replace('/', '_')}.wav"
                scipy.io.wavfile.write(str(local_path), rate=16000, data=audio)
                upload_now(api, local_path, f"{item['path']}.wav", hf_token)
            except Exception as e:
                print(f"[GPU1] ❌ {item['path']}: {e}")
        del sfx_pipe
        torch.cuda.empty_cache()


# ══════════════════════════════════════════════════════════
# توليد الأدوات ثلاثية الأبعاد (أسلحة/مباني/عناصر/موارد/أشجار)
# ══════════════════════════════════════════════════════════

def worker_props3d(items, hf_token, start_time):
    if not items:
        return
    api = HfApi(token=hf_token)
    device = "cuda:0" if torch.cuda.is_available() else "cpu"
    out_dir = OUTPUT_DIR_BASE / "props3d"
    out_dir.mkdir(parents=True, exist_ok=True)

    from diffusers import StableDiffusionXLPipeline
    from rembg import remove
    from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline

    print("[Props3D] 📥 تحميل SDXL...")
    image_pipe = StableDiffusionXLPipeline.from_pretrained(
        "stabilityai/stable-diffusion-xl-base-1.0", torch_dtype=torch.float16, variant="fp16"
    ).to(device)

    print("[Props3D] 📥 تحميل Hunyuan3D-2mini...")
    shape_pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
        "tencent/Hunyuan3D-2mini", subfolder="hunyuan3d-dit-v2-mini", use_safetensors=True, device=device
    )

    for item in items:
        if not time_left(start_time):
            print("[Props3D] ⏰ وقف بأمان — شغّل تاني وهيكمل"); break
        try:
            print(f"[Props3D] 🎨 صورة: {item['path']}")
            image = image_pipe(
                prompt=item["prompt"] + ", plain white background, product photography style",
                negative_prompt="blurry, low quality, watermark, cluttered background",
                num_inference_steps=30, guidance_scale=7.5,
            ).images[0]
            image_no_bg = remove(image).convert("RGB")

            print(f"[Props3D] 🧊 مجسم 3D: {item['path']}")
            mesh = shape_pipe(image=image_no_bg, num_inference_steps=30, octree_resolution=380,
                               num_chunks=20000, output_type="trimesh")[0]

            local_path = out_dir / f"{item['path'].replace('/', '_')}.glb"
            mesh.export(str(local_path))
            upload_now(api, local_path, f"{item['path']}.glb", hf_token)
            print(f"[Props3D] ✅ خلص: {item['path']}")
        except Exception as e:
            print(f"[Props3D] ❌ {item['path']}: {e}")
            continue

    del image_pipe, shape_pipe
    torch.cuda.empty_cache()


# ══════════════════════════════════════════════════════════
# التشغيل
# ══════════════════════════════════════════════════════════

if __name__ == "__main__":
    hf_token = os.environ.get("HF_TOKEN") or __import__("kaggle_secrets").UserSecretsClient().get_secret("HF_TOKEN")
    start_time = time.time()
    num_gpus = torch.cuda.device_count()
    print(f"✅ عدد الـ GPU: {num_gpus}")

    api = setup_repo(hf_token)

    pending_props = get_pending(api, PROPS_3D_LIST, ext=".glb")
    pending_vfx = get_pending(api, VFX_LIST, ext=".png")
    pending_voices = get_pending(api, VOICE_LINES, ext=".wav")
    pending_music = get_pending(api, MUSIC_LIST, ext=".wav")
    pending_sfx = get_pending(api, SFX_LIST, ext=".wav")

    total_pending = len(pending_props) + len(pending_vfx) + len(pending_voices) + len(pending_music) + len(pending_sfx)

    if total_pending == 0:
        print("🎉 كل حاجة خلصت بالفعل!")
    else:
        # كل قسم بيشتغل بعد التاني بالترتيب — آمن جوه بيئة Kaggle Notebook
        # (مفيش multiprocessing عشان مشكلة "spawn" اللي قابلناها قبل كده)
        print("▶️  1) الأدوات ثلاثية الأبعاد (أسلحة/مباني/عناصر/موارد/أشجار)...")
        worker_props3d(pending_props, hf_token, start_time)
        print("▶️  2) المؤثرات الضوئية + أصوات NPCs...")
        worker_gpu0(pending_vfx, pending_voices, hf_token, start_time)
        print("▶️  3) الموسيقى + المؤثرات الصوتية...")
        worker_gpu1(pending_music, pending_sfx, hf_token, start_time)

    remaining = (
        len(get_pending(api, PROPS_3D_LIST, ".glb")) + len(get_pending(api, VFX_LIST, ".png")) +
        len(get_pending(api, VOICE_LINES, ".wav")) + len(get_pending(api, MUSIC_LIST, ".wav")) +
        len(get_pending(api, SFX_LIST, ".wav"))
    )
    if remaining:
        print(f"\n⏳ باقي {remaining} عنصر. شغّل تاني (منك أو من صاحبك بنفس الريبو) وهيكمل تلقائي.")
    else:
        print(f"\n🎉 كل حاجة خلصت! على: https://huggingface.co/datasets/{HF_REPO_ID}")
        print("قولي 'خلص' وهقولك تحمّل إيه بالظبط وتحطه فين.")
