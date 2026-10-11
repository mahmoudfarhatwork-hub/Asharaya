class_name NPCLexicon
extends RefCounted
# NPCLexicon.gd — بيانات فقط (قواميس لغة + مهن + أسماء + أصناف). مفيش منطق ذكاء هنا.
# أي كلمة تضيفها بتتطبّع تلقائيًا (همزات/تاء مربوطة/تشكيل) فاكتبها زي ما هي.
# وتقدر تزوّد كلمات من غير ما تلمس الكود: res://data/npc_lexicon_extra.json

# ───────── كلمات النوايا (كلمة واحدة، وزنها 1.0) ─────────
const INTENT_WORDS := {
	"greet": ["اهلا", "مرحبا", "سلام", "السلام", "هلا", "هاي", "صباح", "مساء", "ازيك", "ازيكم", "هلو", "اهلين", "hello", "hi", "hey", "salam", "ahlan"],
	"farewell": ["وداعا", "باي", "سلامتك", "تصبح", "همشي", "استاذنك", "bye", "goodbye"],
	"thanks": ["شكرا", "شكر", "تسلم", "ممنون", "متشكر", "يسلمو", "thanks", "thx", "thank"],
	"apologize": ["اسف", "عذرا", "معذره", "سامحني", "اعتذر", "اسفين", "sorry"],
	"ask_price": ["بكام", "سعر", "ثمن", "كام", "تكلفه", "بكم", "اسعار", "price", "cost"],
	"buy": ["اشتري", "اشتريه", "شراء", "هات", "اديني", "عندك", "بتبيع", "تبيع", "للبيع", "buy"],
	"sell": ["sell"],
	"haggle": ["غالي", "خصم", "تخفيض", "ارخص", "ارخصها", "تنزل", "نزل", "فصال", "رخيص", "discount", "expensive", "cheap"],
	"ask_quest": ["مهمه", "مهام", "تكليف", "وظيفه", "شغل", "شغله", "quest", "task", "mission"],
	"ask_direction": ["فين", "اين", "مكان", "طريق", "اروح", "اوصل", "توصلني", "دلني", "تدلني", "موقع", "where", "location"],
	"ask_identity": ["اسمك", "who"],
	"ask_job": ["مهنتك", "تشتغل", "بتشتغل", "وظيفتك", "شغلتك"],
	"ask_how": ["اخبارك", "حالك", "عامل", "how"],
	"ask_rumor": ["اخبار", "شايعات", "شائعه", "اشاعه", "اشاعات", "سمعت", "حكايه", "news", "rumor", "gossip"],
	"ask_lore": ["ملك", "ملوك", "اوريليوس", "سيلفوس", "خزجار", "مالاشار", "فيرالاك", "رماد", "نبوءه", "اسطوره", "تاريخ", "تنين", "تنانين", "lore", "history", "kings", "prophecy"],
	"ask_danger": ["خطر", "خطير", "وحش", "وحوش", "امان", "امن", "امنه", "مخيف", "ذئاب", "غوبلن", "سلايم", "monster", "danger", "safe"],
	"ask_advice": ["نصيحه", "انصحني", "ساعدني", "مساعده", "ارشدني", "help", "advice"],
	"svc_heal": ["علاج", "عالجني", "داويني", "اشفيني", "جريح", "مصاب", "heal", "healing"],
	"svc_bless": ["بركه", "باركني", "بارك", "دعاء", "ادعيلي", "bless", "blessing"],
	"svc_craft": ["اصنع", "اصنعلي", "اصلح", "اصلحلي", "تصليح", "اصلاح", "طور", "تطوير", "اشحذ", "صناعه", "craft", "repair", "upgrade"],
	"compliment": ["جميل", "رائع", "ممتاز", "عبقري", "شاطر", "بطل", "عظيم", "تحفه", "محترم", "كريم", "awesome", "great", "amazing"],
	"insult": ["غبي", "حمار", "كلب", "قذر", "وسخ", "زباله", "حقير", "فاشل", "احمق", "اخرس", "اسكت", "انقلع", "غور", "تافه", "حيوان", "كذاب", "نصاب", "حرامي", "سارق", "stupid", "idiot"],
	"threat": ["اقتلك", "هقتلك", "اذبحك", "هذبحك", "احرقك", "هحرقك", "اموتك", "هموتك", "اكسرك", "هكسرك", "هندمك", "هتندم", "ادمرك", "kill"],
	"smalltalk": ["طقس", "جو", "حر", "برد", "مطر", "امطار", "ثلج", "ضباب", "شمس", "weather"],
}

# ───────── عبارات (أكتر من كلمة، وزنها 2.2) ─────────
const INTENT_PHRASES := {
	"greet": ["السلام عليكم", "صباح الخير", "مساء الخير", "نهارك سعيد", "يا هلا", "اهلا وسهلا", "هلا والله", "good morning", "good evening"],
	"farewell": ["مع السلامه", "في امان الله", "الى اللقاء", "يلا سلام", "اشوفك بعدين", "اراك لاحقا", "see you", "good bye"],
	"thanks": ["شكرا لك", "يعطيك العافيه", "جزاك الله", "الله يخليك", "تسلم ايدك", "thank you"],
	"apologize": ["انا اسف", "معلش", "سامحني", "اعتذر لك"],
	"ask_price": ["بكام ده", "السعر كام", "كم السعر", "how much"],
	"buy": ["عايز اشتري", "عاوز اشتري", "اريد شراء", "اريد ان اشتري", "ممكن اشتري", "عندك ايه", "بتبيع ايه", "ايه اللي عندك", "وريني بضاعتك", "what do you sell", "i want to buy"],
	"sell": ["عايز ابيع", "عاوز ابيع", "اريد ان ابيع", "اقدر ابيع", "بتشتري", "تشتري مني", "i want to sell"],
	"haggle": ["غالي قوي", "غالي اوي", "نزل شويه", "نزلي السعر", "اخر سعر", "قلل السعر", "خصم شويه", "اقل شويه", "بلاش كده", "too expensive", "lower the price"],
	"ask_quest": ["فيه شغل", "عندك مهمه", "محتاج حد", "اي مهمه", "عايز مهمه", "عاوز مهمه", "اريد مهمه", "عندك شغل", "اشتغل عندك", "اساعدك في ايه", "any quest", "got a quest"],
	"ask_direction": ["ازاي اوصل", "فين اجد", "فين القي", "اين اجد", "اين يقع", "اروح فين", "دلني على", "where is", "how do i get"],
	"ask_identity": ["انت مين", "مين انت", "من انت", "اسمك ايه", "ما اسمك", "عرفني بنفسك", "who are you", "your name"],
	"ask_job": ["بتشتغل ايه", "شغلتك ايه", "وظيفتك ايه", "مهنتك ايه", "ما مهنتك", "انت بتعمل ايه", "what do you do"],
	"ask_how": ["عامل ايه", "عامل اي", "اخبارك ايه", "كيف حالك", "how are you", "ايه الاخبار"],
	"ask_rumor": ["في ايه جديد", "ايه الجديد", "اي اخبار", "سمعت ايه", "قولي حكايه", "احكيلي", "what's new", "any rumors", "اخر اخبار"],
	"ask_lore": ["مين الملوك", "احكيلي عن الملوك", "عن التاريخ", "حكايه الرماد", "عن النبوءه", "tell me about kings"],
	"ask_danger": ["المنطقه امنه", "هنا امان", "فيه خطر", "في وحوش", "is it safe", "any danger", "الطريق امن"],
	"ask_advice": ["انصحني", "محتاج نصيحه", "اعمل ايه", "اتصرف ازاي", "محتاج مساعده", "help me", "ابدا منين", "اتعلم ايه"],
	"svc_heal": ["عايز علاج", "محتاج علاج", "اريد علاج", "heal me", "انا مجروح", "انا تعبان"],
	"svc_bless": ["باركلي", "عايز بركه", "اريد بركه", "bless me"],
	"svc_craft": ["اصلح سيفي", "عايز اصنع", "عايز اصلح", "can you craft", "can you repair", "اشحذلي"],
	"compliment": ["انت شاطر", "انت عظيم", "انت رائع", "برافو عليك", "good job", "well done", "you are great"],
	"insult": ["انت غبي", "يا غبي", "يا حمار", "يا كلب", "ابن الكلب", "shut up", "انت زباله", "ملكش لازمه"],
	"threat": ["هقتلك", "هاقتلك", "هدبحك", "هموتك", "هكسر راسك", "i will kill", "you will die", "هخلص عليك", "هضربك"],
	"smalltalk": ["الجو حلو", "الجو وحش", "الجو حر", "الجو برد", "النهارده حلو", "ايه الطقس"],
}

# ───────── مجموعات كلمات للنبرة والتراكيب ─────────
const WORD_SETS := {
	"polite": ["فضلك", "سمحت", "ارجوك", "ممكن", "حضرتك", "سيدي", "فندم", "please", "pls", "تكرم", "استاذ", "معلم", "رجاء", "بالله", "ياريت", "اذنك"],
	"rude": ["اخرس", "اسكت", "انقلع", "غور", "ياض", "زهقتني", "غبي", "حمار", "كلب", "قذر", "وسخ", "زباله", "حقير", "فاشل", "احمق", "تافه", "stupid", "idiot", "shut", "حيوان", "كذاب", "نصاب", "حرامي", "سارق"],
	"aggressive": ["اقتلك", "هقتلك", "اذبحك", "هذبحك", "احرقك", "هحرقك", "اموتك", "هموتك", "اكسرك", "هكسرك", "هندمك", "هتندم", "هضربك", "اضربك", "ادمرك", "kill", "die", "destroy", "ويلك"],
	"warm": ["شكرا", "تسلم", "ممنون", "متشكر", "حبيبي", "صديقي", "صاحبي", "عزيزي", "غالي", "جميل", "رائع", "عظيم", "تحفه", "احبك", "thanks", "love", "friend", "مبسوط", "سعيد", "يسلمو"],
	"fear": ["خايف", "خائف", "ينجدني", "انقذني", "اهرب", "مطارد", "afraid", "scared", "run", "نجده"],
	"urgent": ["بسرعه", "حالا", "فورا", "مستعجل", "ضروري", "عاجل", "urgent", "now", "quick"],
	"formal": ["سيدي", "سيدتي", "حضرتك", "مولاي", "عظمتك", "يشرفني", "تكرم", "اود", "ارجو", "لقد", "اني", "انني", "ايها", "ايتها"],
	"slang": ["ياض", "يابا", "يسطا", "ياعم", "يلا", "ايوه", "مفيش", "عايز", "عاوز", "دلوقتي", "النهارده", "كده", "بقى"],
	"intensifier": ["جدا", "اوي", "قوي", "خالص", "كتير", "فعلا", "بشده", "تماما", "very", "so", "really", "جامد"],
	"negation": ["مش", "لا", "ما", "لم", "لن", "مو", "مفيش", "غير"],
	"positive": ["حلو", "جميل", "رائع", "ممتاز", "عظيم", "كويس", "طيب", "تمام", "جيد", "مبسوط", "سعيد", "good", "nice", "great", "cool", "happy"],
	"negative": ["وحش", "سيء", "زفت", "حزين", "تعبان", "زهقان", "مخنوق", "bad", "sad", "angry", "غضبان", "زعلان"],
	"yes": ["ايوه", "ايوا", "اجل", "نعم", "موافق", "تمام", "ماشي", "اوكي", "اكيد", "طبعا", "yes", "ok", "okay", "yep", "اقبل", "قبلت", "اه", "حاضر", "بالتاكيد"],
	"no": ["لا", "رفض", "مستحيل", "no", "nope", "ابدا", "مرفوض", "بلاش"],
	"question": ["ايه", "مين", "فين", "ازاي", "كام", "بكام", "ليه", "امتي", "امتى", "هل", "كيف", "ماذا", "اين", "متي", "لماذا", "كم", "what", "where", "how", "who", "when", "why"],
}

# كلمة -> id الصنف (الـ ids مطابقة لأصناف TraderNPC عشان الشراء يتوافق)
const ITEM_WORDS := {
	"خبز": "bread", "عيش": "bread", "رغيف": "bread", "اكل": "bread", "طعام": "bread",
	"ماء": "water_flask", "ميه": "water_flask", "مياه": "water_flask", "قارورة": "water_flask", "قاروره": "water_flask",
	"جرعه": "small_health_potion", "بوشن": "small_health_potion", "دواء": "small_health_potion", "اكسير": "small_health_potion", "potion": "small_health_potion",
	"طاقه": "stamina_potion",
	"سيف": "iron_sword", "سيوف": "iron_sword", "sword": "iron_sword",
	"درع": "leather_armor", "دروع": "leather_armor", "armor": "leather_armor",
	"خنجر": "dagger", "فاس": "axe", "عصا": "staff", "مطرقه": "hammer", "منجل": "sickle",
	"بذور": "seeds", "قمح": "wheat", "خريطه": "map", "سوط": "whip", "تميمه": "amulet", "بلوره": "crystal", "قوس": "bow",
}

# السعر بالحديدية (نفس أسعار TraderNPC للأصناف المشتركة)
const ITEM_INFO := {
	"bread": {"ar": "رغيف خبز", "iron": 2, "type": "consumable", "sellers": ["farmer", "trader"]},
	"water_flask": {"ar": "قارورة ماء", "iron": 3, "type": "consumable", "sellers": ["trader", "farmer"]},
	"small_health_potion": {"ar": "جرعة شفاء صغيرة", "iron": 5, "type": "consumable", "sellers": ["healer", "trader"]},
	"stamina_potion": {"ar": "جرعة طاقة", "iron": 4, "type": "consumable", "sellers": ["trader", "healer"]},
	"iron_sword": {"ar": "سيف حديدي", "iron": 20, "type": "weapon", "sellers": ["blacksmith", "trader"]},
	"leather_armor": {"ar": "درع جلدي صلب", "iron": 35, "type": "armor", "sellers": ["blacksmith", "trader"]},
	"dagger": {"ar": "خنجر", "iron": 12, "type": "weapon", "sellers": ["blacksmith"]},
	"axe": {"ar": "فأس", "iron": 18, "type": "weapon", "sellers": ["blacksmith"]},
	"hammer": {"ar": "مطرقة", "iron": 15, "type": "weapon", "sellers": ["blacksmith"]},
	"sickle": {"ar": "منجل", "iron": 6, "type": "weapon", "sellers": ["farmer"]},
	"seeds": {"ar": "بذور", "iron": 2, "type": "consumable", "sellers": ["farmer"]},
	"wheat": {"ar": "قمح", "iron": 2, "type": "consumable", "sellers": ["farmer"]},
	"staff": {"ar": "عصا خشبية", "iron": 25, "type": "weapon", "sellers": ["mage", "trader"]},
	"map": {"ar": "خريطة", "iron": 60, "type": "consumable", "sellers": ["trader"]},
	"whip": {"ar": "سوط ترويض", "iron": 22, "type": "weapon", "sellers": ["beast_tamer"]},
	"amulet": {"ar": "تميمة", "iron": 45, "type": "consumable", "sellers": ["priest"]},
	"crystal": {"ar": "بلورة شفاء", "iron": 40, "type": "consumable", "sellers": ["healer"]},
	"bow": {"ar": "قوس", "iron": 28, "type": "weapon", "sellers": ["warrior", "blacksmith"]},
}

# كلمة مكان -> id (المهن لها أكشاك فعلية، والباقي أماكن عامة)
const PLACE_WORDS := {
	"حداد": "blacksmith", "حدادين": "blacksmith", "ورشه": "blacksmith",
	"سوق": "trader", "تجار": "trader", "تاجر": "trader",
	"معبد": "priest", "كهنه": "priest", "كاهن": "priest",
	"معالج": "healer", "معالجين": "healer",
	"ساحر": "mage", "سحره": "mage", "برج": "mage",
	"مشعوذ": "sorcerer", "مشعوذين": "sorcerer", "كوخ": "sorcerer",
	"محارب": "warrior", "محاربين": "warrior", "نقابه": "warrior",
	"مزارع": "farmer", "مزرعه": "farmer", "مزارعين": "farmer",
	"مروض": "beast_tamer", "مروضين": "beast_tamer",
	"غابه": "forest", "كهف": "cave", "بوابه": "gate", "ساحه": "square",
}

# ───────── المهن (نفس ترتيب أكشاك TownBuilder) ─────────
const STALL_ORDER := ["warrior", "mage", "sorcerer", "priest", "healer", "blacksmith", "trader", "farmer", "beast_tamer"]

const STALL_RACE := {
	"warrior": "human", "mage": "elf", "sorcerer": "human", "priest": "human", "healer": "elf",
	"blacksmith": "dwarf", "trader": "human", "farmer": "human", "beast_tamer": "beast",
}

# schedule = ساعات الشغل (24=منتصف الليل)، age = عمر بشري مكافئ [أدنى، أقصى]
const JOBS := {
	"warrior": {"ar": "محارب", "workplace": "نقابة المحاربين", "rank": "fighter", "schedule": [6, 18], "age": [22, 45]},
	"mage": {"ar": "ساحر", "workplace": "برج السحرة", "rank": "mage_priest", "schedule": [9, 22], "age": [35, 70]},
	"sorcerer": {"ar": "مشعوذ", "workplace": "كوخ المشعوذين", "rank": "mage_priest", "schedule": [17, 24], "age": [30, 65]},
	"priest": {"ar": "كاهن", "workplace": "معبد الكهنة", "rank": "mage_priest", "schedule": [5, 20], "age": [45, 75]},
	"healer": {"ar": "معالج", "workplace": "دار المعالجين", "rank": "craftsman", "schedule": [6, 20], "age": [25, 60]},
	"blacksmith": {"ar": "حداد", "workplace": "ورشة الحدادين", "rank": "craftsman", "schedule": [7, 19], "age": [35, 62]},
	"trader": {"ar": "تاجر", "workplace": "سوق التجار", "rank": "big_trader", "schedule": [8, 20], "age": [30, 60]},
	"farmer": {"ar": "مزارع", "workplace": "حظيرة المزارعين", "rank": "worker", "schedule": [5, 17], "age": [25, 65]},
	"beast_tamer": {"ar": "مروض وحوش", "workplace": "حظيرة مروضي الوحوش", "rank": "fighter", "schedule": [6, 18], "age": [22, 50]},
	"king": {"ar": "ملك", "workplace": "القصر", "rank": "king", "schedule": [9, 18], "age": [40, 70]},
	"leader": {"ar": "قائد", "workplace": "الثكنة", "rank": "king", "schedule": [6, 20], "age": [35, 60]},
	"guard": {"ar": "حارس", "workplace": "البوابة", "rank": "fighter", "schedule": [0, 24], "age": [20, 45]},
	"villager": {"ar": "من أهل المدينة", "workplace": "بيته", "rank": "worker", "schedule": [7, 17], "age": [18, 65]},
	"crowd": {"ar": "عابر سبيل", "workplace": "الطريق", "rank": "crowd", "schedule": [8, 20], "age": [15, 70]},
}

# جدول الذكاء من وثيقتك (حسب الرتبة)
const INTEL_RANGE := {
	"king": [0.95, 1.0], "mage_priest": [0.85, 0.95], "big_trader": [0.80, 0.90],
	"craftsman": [0.70, 0.80], "fighter": [0.60, 0.70], "worker": [0.40, 0.60], "crowd": [0.20, 0.40],
}

const JOB_ALIASES := {
	"محارب": "warrior", "ساحر": "mage", "مشعوذ": "sorcerer", "كاهن": "priest", "معالج": "healer",
	"حداد": "blacksmith", "تاجر": "trader", "مزارع": "farmer", "مروض وحوش": "beast_tamer", "مروض": "beast_tamer",
	"ملك": "king", "قائد": "leader", "حارس": "guard", "قروي": "villager", "عابر": "crowd",
}

const RACE_ALIASES := {
	"البشر": "human", "بشر": "human", "الإلف": "elf", "الالف": "elf", "الإلفز": "elf", "إلف": "elf",
	"الأقزام": "dwarf", "الاقزام": "dwarf", "قزم": "dwarf", "الشياطين": "demon", "شيطان": "demon",
	"الوحوش": "beast", "وحش": "beast", "التنانين": "dragon", "تنين": "dragon",
}

const RACE_PHRASE := {
	"human": "من البشر", "elf": "من الإلف", "dwarf": "من الأقزام", "demon": "من الشياطين",
	"beast": "من قبائل الوحوش", "dragon": "من التنانين",
}

# كام سنة بشرية = سنة عند العرق ده (الإلف بيعيشوا أطول، إلخ)
const LIFESPAN := {"human": 1.0, "elf": 4.0, "dwarf": 2.5, "demon": 3.0, "beast": 0.8, "dragon": 8.0}

# انحياز الشخصية حسب المهنة والعرق (بيتجمع على قيمة عشوائية ثابتة لكل NPC)
const JOB_TRAIT_BIAS := {
	"blacksmith": {"pride": 0.15, "patience": -0.10, "warmth": -0.05, "diligence": 0.25},
	"healer": {"warmth": 0.30, "patience": 0.20, "honesty": 0.15},
	"trader": {"greed": 0.30, "talkativeness": 0.20, "humor": 0.10},
	"priest": {"formality": 0.30, "patience": 0.15, "honesty": 0.20},
	"warrior": {"bravery": 0.30, "patience": -0.10, "pride": 0.10},
	"mage": {"curiosity": 0.30, "pride": 0.10, "formality": 0.10},
	"sorcerer": {"honesty": -0.25, "curiosity": 0.20, "warmth": -0.15},
	"farmer": {"patience": 0.20, "warmth": 0.10, "formality": -0.20, "diligence": 0.25},
	"beast_tamer": {"bravery": 0.20, "patience": 0.15, "formality": -0.10},
	"king": {"pride": 0.30, "formality": 0.40, "patience": -0.10, "bravery": 0.20},
	"leader": {"pride": 0.20, "formality": 0.20, "bravery": 0.30},
	"guard": {"bravery": 0.25, "formality": 0.10, "humor": -0.10},
}

const RACE_TRAIT_BIAS := {
	"dwarf": {"pride": 0.10, "greed": 0.10, "formality": -0.10},
	"elf": {"formality": 0.15, "pride": 0.15, "curiosity": 0.10},
	"demon": {"warmth": -0.25, "bravery": 0.20, "honesty": -0.10},
	"beast": {"formality": -0.30, "talkativeness": -0.20},
	"dragon": {"pride": 0.40, "formality": 0.20, "greed": 0.20},
}

# نكهة العرق في الكلام (بادئات/لواحق بتتضاف أحيانًا)
const RACE_FLAVOR := {
	"human": {"pre": [], "suf": []},
	"elf": {"pre": ["يا ابن الأوراق،", "بحق الأغصان،"], "suf": ["وليكن الظل رفيقك."]},
	"dwarf": {"pre": ["بحق السندان!", "هممم،", "بلحية جدي،"], "suf": ["هاه!", "ولا كلمة زيادة."]},
	"demon": {"pre": ["هه...", "يا فانٍ،"], "suf": ["لا تختبر صبري."]},
	"beast": {"pre": ["غررر...", "همم،"], "suf": []},
	"dragon": {"pre": ["أيها الصغير،"], "suf": ["فاعرف قدرك."]},
}

const NAMES := {
	"human": {"male": ["هاشم", "سالم", "ثابت", "رياض", "مراد", "عاصم", "يزن", "عامر"], "female": ["ليلى", "نورا", "سلمى", "هدى", "ريما", "جنى", "مريم"]},
	"elf": {"male": ["سيلاندور", "أيريون", "ثالاس", "لوريان"], "female": ["إيلارا", "ليريل", "نيريا", "أنوريل"]},
	"dwarf": {"male": ["بورين", "غراندل", "دورين", "خازبل", "ثورغان"], "female": ["بروما", "هيلدا", "غونا"]},
	"demon": {"male": ["مالكور", "زاريث", "كراثوس", "فيرزاك"], "female": ["نيكسا", "ليليث", "مورغا"]},
	"beast": {"male": ["غرور", "ناب", "فرو", "حدّاد الغاب"], "female": ["زنب", "عوا", "حدّة"]},
	"dragon": {"male": ["إغنيس", "فاليرون", "أورثان"], "female": ["سكاثا", "إيمبرا"]},
}

# نصيحة لكل مهنة (بتتغلف في الرد)
const JOB_TIPS := {
	"warrior": ["اتعلم تصد قبل ما تضرب", "متقاتلش أكتر من وحشين مع بعض وانت مبتدئ", "السلاح الحاد مش بيعوّض عن الصبر"],
	"mage": ["الطاقة بتخلص بسرعة، وزّعها", "ابعد عن الوحش وانت بتجهّز التعويذة", "الكتب بتعلّم أكتر من أي معركة"],
	"sorcerer": ["اللعنة بتحتاج صبر، مش استعجال", "السم بيشتغل بالتدريج، اختار هدفك صح", "متثقش في حد بسهولة"],
	"priest": ["الراحة بتشفي أكتر مما تتخيل", "البركة بتفيد اللي بيستحقها", "خد بالك من جوعك وعطشك"],
	"healer": ["أي جرح صغير مهمل بيكبر", "الأعشاب بتتجمع بالصبح أحسن", "اشرب ميه كفاية وانت بتتعالج"],
	"blacksmith": ["السلاح المكسور مش بيتصلح بالدعاء، تعالى لي", "الخامة الكويسة أهم من اليد", "الدرع التقيل بيبطّئك، اختار صح"],
	"trader": ["اشتري بالرخيص وبيع بالصح", "الأسعار بتتغير مع الموسم", "متصرفش فلوسك كلها مرة واحدة"],
	"farmer": ["الأرض مابتكدبش، اللي تزرعه تحصده", "الجو بيحكم كل حاجة، راقبه", "الأكل الطازة بيوفر عليك العلاج"],
	"beast_tamer": ["الحيوان بيحس بخوفك", "متقربش من وحش جعان", "الصبر بيروّض أشرس مخلوق"],
	"generic": ["اختار معاركك، مش كل معركة تستاهل", "اتعرّف على الحرفيين، دول كنزك", "الصبر بيكسب في الآخر"],
}

# حكايات العالم حسب العمق (بيعرف منها ناس أكتر أو أقل حسب ذكائه وعمره)
const LORE := {
	1: ["بيقولوا إن الدنيا اتولدت من الرماد.", "زمان كان في ممالك كتير، دلوقتي اتفرقت.", "الناس نسيت أسماء كتير من الزمن القديم."],
	2: ["خمس ملوك حكموا العصر الدهبي: أوريليوس وسيلفوس وخزجار ومالاشار وفيرالاك.", "الملوك اختفوا بعد ما البشر بدأوا يعبدوهم، وبعدها جه الرماد الثاني.", "كل ملك كان ليه قوته: الضوء، والنمو، والمعادن، والظلام، والبرية."],
	3: ["النبوءة بتقول: حين يعود الرماد إلى الرماد، وحين ينسى البشر أسماءهم، سيستيقظ الخمسة من نومهم.", "وبتقول إن واحد هيقف بينهم، لا ملك ولا عبد، واحد اختار إنه يبقى حاجة.", "ملك الشياطين قاعد في الأرض المحروقة، وماحدش قدر عليه لحد دلوقتي."],
}

# ───────── مساعدات ثابتة ─────────
static func job_id(text: String) -> String:
	var t := text.strip_edges()
	if JOBS.has(t):
		return t
	if JOB_ALIASES.has(t):
		return JOB_ALIASES[t]
	return "villager"


static func race_id(text: String) -> String:
	var t := text.strip_edges()
	if RACE_PHRASE.has(t):
		return t
	if RACE_ALIASES.has(t):
		return RACE_ALIASES[t]
	return "human"


static func random_name(race: String, gender: String, r: RandomNumberGenerator) -> String:
	var by_race: Dictionary = NAMES.get(race, NAMES["human"])
	var arr: Array = by_race.get(gender, by_race["male"])
	return str(arr[r.randi() % arr.size()])


# تحويل قيمة بالحديدية لنص عملات (أكبر عملتين فقط) — نفس نسب CurrencySystem
static func format_iron(amount: int) -> String:
	var names := ["حديدية", "نحاسية", "برونزية", "فضية", "ذهبية", "ذهبية ملكية", "ماسية"]
	var values := [1, 10, 100, 1000, 10000, 1000000, 300000000]
	if amount <= 0:
		return "0 حديدية"
	var parts: Array = []
	var left: int = amount
	var i: int = values.size() - 1
	while i >= 0 and parts.size() < 2:
		var q: int = left / values[i]
		if q > 0:
			parts.append("%d %s" % [q, names[i]])
			left -= q * values[i]
		i -= 1
	return " و".join(parts)
