# LIR / ZigLIR — Kapsamlı Repo İncelemesi: 6 Kritik Sorun

**İnceleme tarihi:** 2026-11-26
**Branch:** `arena/ca2f152c-ziglir` (base `1154b10`, merge PR #1)
**Kapsam:** `src/bootstrap/` (~56.058 satır Zig), `src/lir/`, `apps/noema-chat/`, `ai/noema_v3/`, `tests/`, `docs/`, `build.zig`, CI
**Yöntem:** Statik kod okuması + çapraz referans (README/STATUS/ROADMAP iddiaları ↔ gerçek kod). Sandbox'ta Zig toolchain yok (`zig: command not found`), bu yüzden **hiçbir derleme/test çalıştırılamadı**; tüm bulgular kaynak okumasına dayanır.

---

## Özet tablo

| # | Sorun | Kategori | Şiddet | Konum |
|---|-------|----------|--------|-------|
| 1 | `LIR_TRAP_CEIL` ortam değişkeni üretilen binary'de heap sınır denetimini tamamen kaldırıyor | Güvenlik / derleyici | **Kritik** | `ir_codegen.zig:6984-7006` |
| 2 | `-O2` bounds-hoisting: guard yalnızca *taban* işaretçiyi doğruluyor, sonra tüm erişimler `unchecked_access=true` | Doğruluk / bellek güvenliği | **Kritik** | `ir_opt.zig:4616-4860`, `ir_codegen.zig:6732`, `c_backend.zig` |
| 3 | Native canary + heap secret `rdtsc` ile tohumlanıyor; README "CSPRNG (getrandom)" iddia ediyor | Güvenlik / dokümantasyon ihlali | **Yüksek-Kritik** | `ir_codegen.zig:2210-2320`, `ir_codegen.zig:7310` |
| 4 | IR VM'de adım (step) limiti yok: `steps` sayılıyor ama hiç karşılaştırılmıyor → sonsuz döngü asılı kalıyor | Kullanılabilirlik / DoS | **Yüksek-Kritik** | `ir_vm.zig:43,130,554,1590` |
| 5 | vreg sayacı `u16` ve `allocVreg` taşmayı kontrol etmiyor; codegen `min(vreg_count+2, MAX_VREGS)` ile sessizce kırpıyor | Doğruluk / sessiz bozuk derleme | **Yüksek** | `ir.zig:412`, `ir_gen.zig:54,148-155`, `ir_codegen.zig:38,2670-2730` |
| 6 | IR verifier def-before-use / dominance / phi-predecessor kontrolü yapmıyor — optimizasyon yanlış-cevap sınıfının kök nedeni | Doğruluk / mimari | **Yüksek** | `ir_verify.zig` (143 satır), `docs/STATUS.md:84-88` |

---

## 1. `LIR_TRAP_CEIL`: tek bir ortam değişkeni üretilen binary'nin bellek güvenliğini kapatıyor

**Ne oluyor:**

```zig
// src/bootstrap/ir_codegen.zig:6984
/// Measurement-only switch: LIR_TRAP_CEIL=1 compiles away the heap-range
/// screen and the verifier call, i.e. an unsound but maximally fast build.
fn trapCeil(self: *IRCodegen) bool {
    return self.opt_trap_ceil orelse blk: {
        const v = std.posix.getenv("LIR_TRAP_CEIL") != null;
        ...
    };
}

fn emitPtrTrapN(self: *IRCodegen, reg: u8, access_bytes: u8) void {
    if (self.trapCeil() and access_bytes <= 8) {
        self.emitCmpRegImm32(reg, 4096);   // yalnızca NULL-page ekranı
        self.emit8(0x73); self.emit8(0x02);
        self.emit8(0x0F); self.emit8(0x0B); // ud2
        return;                             // heap-range ekranı + chk_heapN çağrısı YOK
    }
```

`emitPtrTrapN` en sıcak erişim opkodlarında (`ir_codegen.zig:3672-3714`, `4648-4658`) çağrılıyor — yani **load/store/index/map/slice erişimlerinin büyük kısmı**. Bu yol atlandığında üretilen ELF'te:

- `heap_min`/`heap_max` aralık kontrolü yok,
- `__lir_chk_heap{1,4,8}` doğrulayıcı çağrısı yok,
- canary/zero-on-free denetimi bypass ediliyor,
- kalan tek koruma `ptr < 4096 → ud2`.

**Neden kritik:**
1. **Kalıcı ve görünmez.** Bayrak derleme anında okunuyor; sonuçta üretilen binary'de hiçbir iz bırakmıyor. CI kabuğunda, bir Docker imajında, bir `Makefile`'da veya bir saldırganın kontrol ettiği build ortamında `LIR_TRAP_CEIL` tanımlıysa, "güvenli" olduğu iddia edilen artifact sessizce savunmasız derlenir. Üstelik değer önemli değil — `!= null` kontrolü, `LIR_TRAP_CEIL=0` için bile **denetimleri kapatır**.
2. **Repo'nun kendi tehdit modeliyle çelişiyor.** `findZigExe`/`findHostCC` (`c_backend.zig:1490-1540`) de `LIR_ZIG`/`CC` ortam değişkenlerini doğrulamadan `Child.run` argv[0]'ına koyuyor; yani ortam değişkenleri zaten güven sınırının dışında tutulmuyor.
3. **"Measurement-only" yorumu bir güvenlik kontrolü değil.** Uyarı yok, log yok, binary'e işaret yok, `--no-unsafe` gibi bir override yok.

**Öneri:**
- Ölçüm bayrağını üretim codegen yolundan çıkarın: ayrı bir `bench`/`debug` build hedefine taşıyın.
- Kalmalıysa: (a) yalnızca `=1` için etkinleştirin, (b) derleme çıktısına ve ELF'e kalıcı bir `UNSAFE_TRAP_CEIL` bölümü/notu yazın, (c) her derlemede stderr'e kırmızı uyarı basın, (d) `lir build` ile `ReleaseSafe`/varsayılan modda **reddedin**.
- Ek olarak: `LIR_ZIG`/`CC` için executable-bit + mutlak yol doğrulaması ekleyin; PATH taramasında `access(F_OK)` yerine `access(X_OK)` kullanın.

---

## 2. `-O2` bounds-hoisting ses geçirmez değil: base-in-heap ≠ access-in-bounds

**Ne oluyor:**

`hoistBoundsChecks` (`ir_opt.zig:4616`) doğal döngü + tek preheader + `loopHasOnlyBulkSideEffects` (`ir_opt.zig:4566`: döngüde call yok ya da memory-pure, bulk dışı store yok) koşullarında bir `bounds_hoist_guard` üretiyor (`ir_opt.zig:4831`). Guard'ın yaptığı kontrol:

| Backend | Guard içeriği |
|---------|---------------|
| native x86-64 | `ir_codegen.zig:6732`: `ptr >= heap_min && ptr < heap_max` |
| C | `lir_chk_ptr_n(v, 1u)` — **1 bayt** için chunk geçerliliği |
| WASM | eşdeğer heap-range ekranı |

Guard'dan sonra döngü gövdesindeki tüm bulk erişimler işaretleniyor:

```zig
// src/bootstrap/ir_opt.zig:4849
blk.insts[ii2].unchecked_access = true;
```

**Ses geçirmezlik açığı:** guard, *taban işaretçinin* heap içinde olduğunu kanıtlıyor. Döngü içinde erişilen gerçek adres `base + i*stride + offset`. Optimizasyon şu hiçbirini kanıtlamıyor:

- `i`'nin üst sınırı (döngü trip count'ı ile buffer boyutu ilişkisi),
- `stride` (eleman boyutu) × trip count ≤ chunk boyu,
- `offset`'in chunk içinde kaldığı,
- indeksin döngü içinde monoton/artan olduğu (wrap yok).

Sonuç: **heap içinde ama chunk dışında** bir adrese yapılan erişim, guard'ı geçer ve `unchecked_access=true` olduğu için trap üretmez. Bu tam olarak "sessiz OOB okuma/yazma" sınıfı — LIR'in README'de vaat ettiği "her erişimde sınır denetimi" garantisinin -O2'de ihlali.

**Neden kritik:**
- Sadece `-O2`'de tetikleniyor; `-O0/-O1`'de aynı program güvenli. Bu, "release build'de ortaya çıkan, debug'da tekrarlanamayan" bellek hatası üretir — teşhisi en pahalı hata sınıfı.
- ROADMAP Phase 3 zaten 9 adet optimizasyon kaynaklı yanlış-cevap bug'ı belgeliyor (`unrollCountedLoops` induction advance, `coalesceCopiesPostSSA` dst overwrite, `rotateLoops` phi/SIGILL, magic-divisor `rcx`/`r10` clobber, `mem2reg` phi placement, `simplifyTrivialPhis` dominance'sız rewrite, `globalCopyPropagate` phi operand rewrite). Bounds-hoisting aynı desenin hâlâ açık bir örneği.
- Heap secret/canary mekanizması bu erişimi yakalamaz, çünkü adres geçerli bir heap bölgesinde.

**Öneri:**
- Guard'ı *erişim aralığı* kanıtına yükseltin: `base`, `limit = chunk_end - access_size`, ve döngü boyunca hesaplanan efektif adres için `addr <= limit` çıkarımı; trip count × stride + offset ≤ chunk_len aritmetik kanıtı (SCEV benzeri basit induction-value aralığı) üretilemiyorsa hoist **yapılmasın**.
- Kanıt üretilemeyen durumlarda güvenli fallback: döngü başına **tek** guard değil, her erişimde `chk_ptr_n(ptr, size)` bırakın (zaten deferred-cold-path ile maliyet düşük).
- `unchecked_access=true` atayan her yol için regresyon testi ekleyin: `tests/backend_test.py` içinde "base heap içinde, offset buffer dışında" fixture'ı ile native/C/VM/WASM dördünde de trap beklendiğini doğrulayın.
- Issue #6'daki dominance verifier'ı olmadan bu sınıfı kapatmak mümkün değil — ikisi birlikte ele alınmalı.

---

## 3. Native stack canary ve heap secret `rdtsc` ile tohumlanıyor; README CSPRNG iddia ediyor

**Ne oluyor:**

README, güvenlik bölümünde stack & heap canary'lerinin CSPRNG (`getrandom`) ile üretildiğini söylüyor. Gerçekte native başlangıç kodu:

```
// src/bootstrap/ir_codegen.zig:2210-2320
0x0F 0x31          // rdtsc -> edx:eax
xor  rsp           // karıştırma
rol / shl          // karıştırma
-> [DATA_VADDR+0x70] = heap_secret
-> [DATA_VADDR+0x78] = stack_canary
```

ve heap doğrulayıcısı sabit bir tuz kullanıyor:

```zig
// src/bootstrap/ir_codegen.zig:7310
const CANARY_SALT: u64 = 0xA5A5_5A5A_1234_5678;
```

Karşılaştırma — diğer yollar **doğru**:
- `@random_u64` / `@random_bytes` native: `SYS_getrandom` (318), EINTR retry, başarısızlıkta `ud2` (`ir_codegen.zig:6340-6430`) ✔
- WASM: `random_get` ile tohumlama ✔
- C backend: `lir_heap_secret` `main` içinde `lir_random_u64() | 1` ile yeniden tohumlanıyor; `getrandom`/`arc4random_buf`/`rand_s`/`__wasi_random_get`/`/dev/urandom` zinciri ✔

**Neden kritik:**
1. **`rdtsc` tahmin edilebilir.** Düşük 32 bit, çekirdek frekansı ve süreç başlatma zamanından türetilir. Aynı makinede tekrar tekrar çalışan bir süreçte entropi birkaç yüz bite değil, pratikte ~10-20 bite düşer. Yerel bir saldırgan (aynı host'ta süreç çalıştıran, ya da fork sonrası child'ı hedef alan) canary'yi brute-force/öngörebilir.
2. **Sabit `CANARY_SALT`** bu zayıflığı büyütür: canary = f(rdtsc, sabit tuz). Tuz herkese açık, tek bilinmeyen zayıf zamanlama.
3. **Doğrulanmış bir güvenlik iddiasinin ihlali.** Bu, "güvenli dil" konumlandırmasının çekirdeği; README'ye güvenen kullanıcı yanlış varsayımla kod yazar.
4. VM tarafında da canary `CANARY_COOKIE ^ size` — süreç başına secret değil (`ir_vm.zig`), yani orada da aynı sınıf.

**Öneri:**
- Native `_start`'ta canary/heap_secret tohumlamasını `SYS_getrandom`'a taşıyın (zaten `@random_u64` için çalışan kod yolu var — aynı helper'ı başlangıçta çağırın). `getrandom` başarısız olursa **`ud2` ile açılışı durdurun** (sessiz `rdtsc` fallback'i olmayacak).
- `rdtsc` fallback'i yalnızca açıkça opt-in bir ölçüm bayrağı olsun ve Issue #1'deki gibi artifact'e işaretlensin.
- `CANARY_SALT`'ı süreç başına rastgele `heap_secret` ile birleştirin (`salt ^ heap_secret`), sabit kalmasın.
- VM canary'sini de süreç başına secret ile key'leyin.
- README'deki iddiayı backend bazında test eden bir denetim ekleyin: `tests/backend_test.py` içine "canary iki çalıştırmada farklı mı + `getrandom` syscall'i izleniyor mu (strace)" kontrolü.

---

## 4. IR VM'de adım limiti yok: `steps` sayılıyor ama hiçbir zaman karşılaştırılmıyor

**Ne oluyor:**

```zig
// src/bootstrap/ir_vm.zig
 43:    steps: u64 = 0,
130:    steps: u64 = 0,
554:                self.steps += 1;     // tek artış noktası
1590:    result.steps = vm.steps;        // yalnızca raporlama
```

`grep -n "steps" src/bootstrap/ir_vm.zig` çıktısında **tek bir karşılaştırma yok**. `MAX_CALL_DEPTH = 2048` (`ir_vm.zig:27`) yalnızca özyineleme derinliğini sınırlıyor; `callFn`'in ana `while (true)` döngüsünde step budget kontrolü yok. Yani:

```lir
while true { }     // VM backend: süreç asılı kalır, CPU %100
```

native backend'de sema compile-time spin-loop tespiti yapıyor (`sema.zig:2177`), ama VM runtime'ında eşdeğer bir guard yok.

**Neden kritik — bu repo için somut bir saldırı yüzeyi var:**

`apps/noema-chat/server.mjs` VM'yi **fallback** olarak kullanıyor:

```js
// apps/noema-chat/server.mjs:363-366
if (await fileSize(BACKEND_NATIVE)) {
  result = await spawnCapture(BACKEND_NATIVE, [npg, nv3g], { input, timeoutMs: requestTimeoutMs });
} else {
  result = await spawnCapture(lir, ['run', '--backend=vm', BACKEND_LIR, npg, nv3g], { input, timeoutMs: requestTimeoutMs });
}
```

ve eğitim yolunda timeout **varsayılan olarak kapalı**:

```js
// apps/noema-chat/server.mjs:34
const trainingTimeoutMs = Number(process.env.TRAIN_TIMEOUT_MS || 0);
// spawnCapture: const timer = timeoutMs ? setTimeout(...) : null;   → timeoutMs=0 ⇒ zamanlayıcı YOK
```

Yani native binary yoksa (temiz clone, CI, Docker imajı ilk aşaması) `/api/train` + `/api/chat`, kullanıcı girdisiyle beslenen bir VM sürecini **sınırsız süre** çalıştırabilir. Sunucu `0.0.0.0:4173`'e bağlanıyor ve **hiçbir kimlik doğrulama / rate limit yok** → tek istekle kalıcı CPU+memory DoS.

Ek VM sertlik eksikleri aynı madde altında:
- VM heap canary'si secret-keyed değil (Issue #3).
- Thread/chan/mutex yapıları var (`mem_lock`, `VMChan` Mutex+Condition, `VMThread` spawn/join) ama veri yarışı denetimi yok; `deinit` join edilmemiş thread'leri join ediyor — bu yolun race'i doğrulanmadı.
- `lir run --backend=vm` ayrıca `ir_verify.zig`'in kapsamadığı IR'leri çalıştırabilir (Issue #6).

**Öneri:**
- `VMState`'e `max_steps: u64` ekleyin (varsayılan örn. 10^9, `--max-steps` ile ayarlanabilir). `ir_vm.zig:554`'te `self.steps += 1; if (self.steps > self.max_steps) return error.StepLimitExceeded;`. Yeni hata kodunu `ir_vm.zig:1586`'daki trap eşlemesine ekleyin (örn. exit 133).
- Ayrıca bir duvar-saati bütçesi ekleyin (`std.time.milliTimestamp()` başlangıcı + `--timeout-ms`); step limiti sıkı döngüleri yakalar ama syscall'de bloklayan thread'i yakalamaz.
- `server.mjs`'de `TRAIN_TIMEOUT_MS || 0` varsayılanını **sıfır olmayan** bir değere çevirin (örn. 600000) ve `0`'ı yalnızca açık `TRAIN_TIMEOUT_MS=unlimited` ile kabul edin.
- Sunucuya eşzamanlılık sınırı (`activeRuns` zaten sayılıyor, sadece bir tavan ve 429 yanıtı eksik) + temel bir token/rate-limit katmanı ekleyin; `server.listen(port, '0.0.0.0', ...)` yerine varsayılan `127.0.0.1`, `--host` ile açma.
- `/tmp/noema-chat-v3-upload.tr.txt` ve `/tmp/noema-chat-v3-progress.bin` **sabit ve tahmin edilebilir** yollar (`server.mjs:31-32`): çok kullanıcılı host'ta symlink/TOCTOU ve işler arası karışma riski. `fs.mkdtemp` + `O_EXCL` + `O_NOFOLLOW` kullanın.

---

## 5. vreg sayacı `u16`, taşma kontrolsüz, codegen sessizce kırpıyor → yanlış derleme

**Ne oluyor:**

```zig
// src/bootstrap/ir.zig:412
vreg_count: u16,

// src/bootstrap/ir_gen.zig:54
next_vreg: u16,

// src/bootstrap/ir_gen.zig:148-155
fn allocVreg(self: *IRGen) u16 {
    const v = self.next_vreg;
    self.next_vreg += 1;                       // ← taşma kontrolü YOK
    if (self.next_vreg > self.curFn().vreg_count) {
        self.curFn().vreg_count = self.next_vreg;
    }
    return v;
}
```

Codegen tarafında ise kapasite sabit:

```zig
// src/bootstrap/ir_codegen.zig:38
const MAX_VREGS: usize = 8192;
// ir_codegen.zig:2670-2730 → min(vreg_count + 2, MAX_VREGS), ve `dest < MAX_VREGS` guard'ları
```

İki ayrı kırılma modu var:

1. **65535'te sessiz `u16` wrap.** Büyük/inline'lanmış/unroll edilmiş bir fonksiyonda `next_vreg` 65535'i geçerse `allocVreg` **0'a sarar** ve daha önce atanmış vreg'leri yeniden verir. Sonuç: birbirinden bağımsız iki değer aynı sanal register'ı paylaşır → sessiz veri bozulması, yanlış hesaplama. Ne hata, ne uyarı, ne trap.
2. **8192 üstünde sessiz kırpma.** `min(vreg_count+2, MAX_VREGS)` ve `dest < MAX_VREGS` guard'ları, 8192'den büyük vreg'leri **yok sayar**. İlgili load/store/call sonuçları hiçbir register'a yazılmaz; sonra o değeri okuyan kod bayat/çöp register içeriği kullanır.

`ir_verify.zig` bunu yakalamaz: verifier vreg **aralıklarını** (`< vreg_count`) kontrol ediyor, ama `vreg_count > MAX_VREGS` tutarsızlığını ya da aynı vreg'in iki kez tanımlanmasını (Issue #6'daki def-before-use eksikliği) kontrol etmiyor.

**Neden kritik:**
- **Sessiz yanlış cevap.** Trap yok, derleyici hatası yok, "başarılı" bir binary üretiyor. LIR'in iddiası tam da "güvenilir sistem dili" olmak.
- Eşiğe ulaşmak gerçekçi: `unrollCountedLoops`, `expand.zig` (1513 satır), inlining ve `-O2` pipeline'ı IR'ı büyütüyor; ROADMAP Phase 3'te belgeli unroll bug'ları var. `MAX_INSTS_PER_BLOCK=384`, `MAX_BLOCKS_PER_FN=192` → teorik üst sınır ~73.728 talimat/fonksiyon, yani 8192 vreg eşiği bu limitlerden **çok önce** aşılabilir.
- `MAX_VREGS` aşımında ne olacağı hiçbir dokümanda yazmıyor; STATUS.md'de sabit limit tablosunda da yok.

**Öneri:**
- `allocVreg`'i hata döndürecek şekilde değiştirin: `if (self.next_vreg == std.math.maxInt(u16)) return error.VregOverflow;` — ya da daha iyisi, `vreg_count`'u `u32`'e taşıyın (IR layout'unu etkiler; `ir.zig:412`, `ir_gen.zig:54`, verifier ve codegen birlikte).
- `MAX_VREGS` aşımını **derleme hatası** yapın (`error.TooManyVregs`, "fonksiyonu bölün" önerisiyle), sessiz kırpma yerine. `min(...)` ifadesini kaldırın.
- `ir_verify.zig`'e ekleyin: (a) `vreg_count <= MAX_VREGS`, (b) her vreg'in **en fazla bir** tanım noktası olduğu (phi'ler hariç) — bu aynı zamanda Issue #6'yı kısmen kapatır.
- Büyük IR üreten pass'lere (unroll, expand, inline) vreg bütçesi kontrolü koyun; bütçe aşılıyorsa optimizasyonu **geri alın**, yarım uygulamayın.
- Regresyon testi: 8192+ vreg üreten sentetik bir `.lir` dosyası ekleyin; beklenen davranış temiz bir derleyici hatası.

---

## 6. IR verifier def-before-use / dominance / phi-predecessor kontrolü yapmıyor — belgeli yanlış-cevap bug'larının kök nedeni

**Ne oluyor:**

`src/bootstrap/ir_verify.zig` yalnızca 143 satır ve şu **yapısal** kontrolleri yapıyor: string/fn/struct aralıkları, block/inst sayıları, phi'lerin blok başında olması, blok ortasında terminator olmaması, vreg/slot/param aralıkları, branch hedef aralıkları, call arg sayıları, stack frame > 16 MiB.

Repo bunu kendisi itiraf ediyor:

```
docs/STATUS.md:84   branch targets, but not def-before-use ordering or dominance. Six
docs/STATUS.md:87   2026-11 (see ROADMAP Phase 3); a real dominance-checking
```

Yani **2026-11'de 6 adet yanlış-cevap bug'ı elle bulundu ve bunların 4'ü bir dominance verifier ile yakalanabilirdi.** ROADMAP Phase 3 listesi: `unrollCountedLoops` induction advance, `coalesceCopiesPostSSA` dst overwrite, `rotateLoops` phi → SIGILL, magic-divisor `rcx`/`r10` clobber, `mem2reg` phi placement, `simplifyTrivialPhis` dominance'sız rewrite, `globalCopyPropagate` phi operand rewrite.

**Neden kritik:**
1. **Sistematik, tek seferlik değil.** 9 belgeli bug'ın ortak deseni: bir pass, bir değerin *baskın* olmadığı bir yola taşıyor. Bug'lar tek tek yamalanmış; **sınıfı** kapatan bir mekanizma yok. Bir sonraki pass aynı hatayı tekrar üretebilir ve kimse fark etmez.
2. **Savunma katmanı yok.** Dört backend (native x86-64, C11, WASM, VM) aynı IR'ı tüketiyor. IR bozuksa dördü de bozuk çıktı üretir. Verifier, backend'e giden son kapı — ve o kapı bu sınıfı geçiyor.
3. **Issue #2 ile doğrudan bağlantılı.** Bounds-hoisting'in ses geçirmezliğini *kanıtlamak* için dominance + induction-value aralığı analizi gerekir. Verifier dominance bilmiyorsa, hoist edilmiş bir guard'ın gerçekten tüm erişim yollarına baskın olduğunu hiçbir şey doğrulamaz. Issue #2'nin güvenli çözümü Issue #6'ya bağlı.
4. **Issue #5'i de büyütür.** Def-before-use kontrolü olmadan, `allocVreg` wrap'inden (Issue #5) kaynaklanan "aynı vreg iki kez tanımlı" durumu da yakalanmaz.
5. Teşhis maliyeti: bu bug'lar "SIGILL", "sessiz yanlış sayı", "release'te var debug'da yok" şeklinde ortaya çıkıyor — en pahalı hata sınıfı.

**Öneri:**
- `ir_verify.zig`'e gerçek bir SSA doğrulayıcı ekleyin (143 satırlık dosya bunu kaldıracak kadar basit bir IR'a sahip):
  - **Dominance:** iteratif dominator hesabı (Cooper-Harvey-Kennedy) — fonksiyon başına `MAX_BLOCKS_PER_FN=192` olduğu için maliyet ihmal edilebilir.
  - **Def-before-use:** her vreg tanımı, tüm kullanımlarına dominance yoluyla baskın olmalı.
  - **Phi bütünlüğü:** her phi'nin operand sayısı = predecessor sayısı; phi tanımı ilgili predecessor kenarında baskın; döngü başı phi'lerinde back-edge tanımı reachable.
  - **Tek tanım (Issue #5 ile ortak):** phi dışı bir vreg'in birden fazla tanımı varsa hata.
- Verifier'ı **her optimizasyon pass'inden sonra** çalıştırın (yalnızca pipeline sonunda değil) — `-O1/-O2`'de pass-başı doğrulama, hangi pass'in IR'ı bozduğunu otomatik işaretler. Maliyet sorunsa `LIR_VERIFY_EACH_PASS` ile varsayılan açık, kapatılabilir olsun (ama Issue #1'in tersine, **açık** olan taraf güvenli taraf olmalı).
- CI'a ekleyin: `.github/workflows/ci.yml` ReleaseFast/ReleaseSafe/Debug üç modunda da `zig build test`; ayrıca rastgele IR mutasyonu (fuzz) ile verifier'ın kendisini test eden bir hedef — bozuk IR üreten bir mutasyonun verifier'dan geçmemesi gerekir.
- `docs/STATUS.md:84-88` ve ROADMAP Phase 3'teki "a real dominance-checking verifier" maddesini **blocker** olarak işaretleyin; bounds-hoisting (Issue #2) ve yeni -O2 pass'leri bu kapanana kadar dondurulsun.

---

## İkincil bulgular (6 kritik dışında, rapor bütünlüğü için)

| Bulgu | Konum | Not |
|-------|-------|-----|
| `page_allocator` her yerde; arena/GPA yok, sızıntı denetimi yok | `main.zig`, `driver.zig`, `cmf.zig`, `repl.zig`, `parser.zig`, `util.zig` (21 kullanım) | Kısa ömürlü CLI için kabul edilebilir ama `deinit` yollarının doğruluğu test edilmiyor; LSP/daemon'a geçişte (ROADMAP) bloklayıcı olur |
| REPL sürüm dizgesi eski | `repl.zig:21` → `v2.2.0`; `main.zig:86` ve `build.zig.zon` → `2.3.0` | Sürüm tutarlılığı testi yalnızca `main.zig`/`zon`'u koruyor; `repl.zig` kapsama alınmalı |
| "refuses symlinks" test adıyla uyuşmuyor | `tests.zig:1462-1500`, `util.zig:112-145` | Test symlink senaryosu kurmuyor; POSIX `rename` symlink'in kendisini değiştirir, hedefe yazmaz. TOCTOU/öngörülebilirlik analizi eksik |
| Import döngü tespiti string karşılaştırma | `driver.zig` `containsPath`, `MAX_SOURCES=64` / `SYNTH_SOURCE_ID=63` | Canonical/symlink çözümleme yok; symlink ile döngü bypass edilebilir. `manifest.validRelative`/`project.validName` katı (mutlak yol, `..`, backslash, drive, NUL reddi) — ama driver explicit import'larda mutlak yol ve `../` kabul ediyor |
| `@ptr_add` denetimsiz wrap aritmetiği | `ir_gen.zig:3485` → `call_ptr_add`; VM `ir_vm.zig:815` `%+`, C `c_backend.zig:1360` `+`, native `add` | Kontrol yalnızca deref anında (`resolveSlice`, `emitPtrTrapN`, `lir_chk_ptr_n`). Geçersiz bir işaretçi deref edilmeden saklanıp iletilebilir → Issue #2 ile birleşince tehlikeli |
| Sabit kapasite limitleri kullanıcıya belge gibi verilmiyor | `MAX_AST_NODES=65536`, token 16384, `MAX_PARAMS=8`, `MAX_INSTS_PER_BLOCK=384`, `MAX_BLOCKS_PER_FN=192`, `MAX_FNS=320`, `MAX_STRUCTS=256`, parser recursion 64, sema expr depth 256, `readFileAlloc` 64 MiB | Aşım mesajlarının kalitesi ve "ne yapmalı" rehberi tutarsız; STATUS.md'de tek tablo yok |
| README "32 KiB per-function stack frame budget" iddiası codegen'de zorlanmıyor | `ir_codegen.zig` frame hesabı: `total_slots = total_locals + spills + callee_count + canary`, `aligned_frame = ((total_slots*8)+15) & ~15`, `subRspImm` | Verifier yalnızca > 16 MiB'ı reddediyor; 32 KiB eşiği hiçbir yerde kontrol edilmiyor → iddia/davranış farkı (Issue #3 ile aynı desen) |
| Taşma sessizce sarıyor | `STATUS.md:43`, `SPEC.md:238`; VM `%+ -% *%`, C `uint64_t` düz op, WASM `i64.add/sub/mul` | **Bilinçli tasarım** ve C tarafında UB yok (`uint64_t` wrap + `(int64_t)` cast). `@checked_*` trap'li; `div`/`mod` sıfır ve `INT64_MIN/-1` trap; shift `>=64` trap. Kritik listede değil, ama `-O2` optimizasyonları (magic divisor vb.) wrap varsayımına dayanıyor — bu varsayımın test kapsamı zayıf |
| Tam borrow/lifetime analizi yok | ROADMAP Phase 2 açık; `sema.zig` kısmi kontroller | Sema dangling-ref (return/assign/store/spawn), UAF (`res_state` freed/maybe_freed + alias), double-free (defer dahil), loop-leak, defer-conflict kontrol ediyor; ancak `markExprEscaped` sonrası raw pointer escape'te kontroller zayıflıyor. README'deki "borrow analizi" ifadesi bu kısmi kapsamı olduğundan büyük gösteriyor |
| Web app: `innerHTML` kullanımı | `apps/noema-chat/app.js:233-234, 271-272` | Değerler iç sabit (`'0<small>ms · önbellek</small>'`, `fmtMs` sayısal) — mevcut haliyle XSS değil, ama model çıktısı bu yola hiç girmemeli; `textContent` + `<small>` alt düğümü ile değiştirilmesi güvenli. CSP zaten sıkı (`script-src 'self'`, `style-src 'self'`) |

---

## Doğrulama durumu (dürüstlük notu)

- **Çalıştırılamadı:** `zig build`, `zig build test`, Python test paketleri (`tests/*.py`), NOEMA audit'leri. Sandbox'ta Zig toolchain yok (`which zig` → boş) ve `zig-out/` dizini mevcut değil.
- **Doğrulandı (kaynak okuması ile):** yukarıdaki tüm satır referansları, `grep`/`sed` çıktılarından birebir alınmıştır; `docs/STATUS.md:84-88` ve `docs/ROADMAP.md` Phase 3 alıntıları repo'nun kendi metinleridir.
- **Çıkarım (çalıştırma gerektirir):** Issue #1, #2, #4, #5 için "şu girdiyle şu yanlış davranış" PoC'leri yazılmadı. Her biri için önerilen ilk PoC:
  1. `LIR_TRAP_CEIL=1 lir build tests/fixtures/<heap_oob>.lir -o /tmp/x && /tmp/x` → trap **olmamalı** ama olmuyor; aynı program bayraksız trap ediyor.
  2. `lir build -O2` ile, heap içinde ama chunk dışında kalan bir `base + i*stride` döngüsü → OOB erişimin trap etmediğini ASAN'lı C backend ile karşılaştırarak gösterin.
  3. `lir run --backend=vm` ile `while true {}` → süreç asılı; `MAX_CALL_DEPTH`'in bunu yakalamadığını derin-özyineleme olmayan döngüyle ayırın.
  4. 8200+ yerel/ara değer üreten sentetik fonksiyon → codegen'in sessiz kırpıp kırmadığını `lir build --emit-ir` çıktısıyla karşılaştırın.

## Önerilen sıra

1. **Issue #1** (en ucuz, en yüksek etki: bayrağı üretim yolundan çıkar) → aynı gün.
2. **Issue #3** (native tohumlamayı `getrandom`'a taşı; kod yolu zaten var) → 1-2 gün.
3. **Issue #6** (dominance verifier; diğer iki doğruluk sorununun önkoşulu) → 1 hafta.
4. **Issue #4** (VM step/time budget + `server.mjs` timeout/host/tmp düzeltmeleri) → 2-3 gün.
5. **Issue #2** (bounds-hoist kanıtı; #6 kapandıktan sonra) → 1-2 hafta. Bu süre boyunca `-O2`'de `hoistBoundsChecks`'i **devre dışı bırakmak** en güvenli ara adım.
6. **Issue #5** (vreg overflow → derleme hatası) → 2-3 gün.
