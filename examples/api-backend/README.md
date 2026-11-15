# LIR vs Zig: Kapsamlı REST API Backend Karşılaştırması

Bu çalışmada, gerçek dünya gereksinimlerine sahip kurumsal bir RESTful mikroservis backend'i (**LirStore REST API**) hem **LIR** (Low-level Intermediate Representation / Systems Language) hem de **Zig** (0.13.0) dillerinde sıfırdan geliştirilmiş, aynı iş mantığı ve uç noktalar birebir uygulanarak mimari, ergonomi ve performans açısından karşılaştırılmıştır.

---

## 1. Mimarisi ve Uç Noktalar (Endpoints)

Her iki backend de Linux çekirdek soket seviyesinde (sıfır harici C bağımlılığı) çalışan, in-memory veri tabanına ve oturum/yetkilendirme kontrolüne sahip HTTP/1.1 JSON mikroservisleridir:

| Metot | Uç Nokta (Route) | Açıklama | Yetki / Başlık | Durum Kodu |
|:---|:---|:---|:---|:---|
| `GET` | `/api/v1/health` | Sistem sağlık durumu, çalışma süresi ve istek sayacı | Herkese Açık | `200 OK` |
| `GET` | `/api/v1/stats` | Aktif kullanıcı sayısı, toplam bakiye ve hacim | Herkese Açık | `200 OK` |
| `GET` | `/api/v1/users` | Tüm kullanıcıların JSON listesi | Herkese Açık | `200 OK` |
| `GET` | `/api/v1/users/:id` | Tekil kullanıcı detayı sorgulama | Herkese Açık | `200 OK` / `404 Not Found` |
| `POST` | `/api/v1/users` | Yeni kullanıcı kaydı oluşturma | `Bearer lir-secret-token-2026` | `201 Created` / `401 Unauthorized` |
| `DELETE` | `/api/v1/users/:id` | Kullanıcı kaydını silme (soft-delete) | `Bearer lir-secret-token-2026` | `200 OK` / `401 Unauthorized` |
| `OPTIONS` | `*` | CORS Preflight desteği | Herkese Açık | `204 No Content` |

---

## 2. Karşılaştırma Sonuçları ve Benchmark Tablosu

Aynı Linux x86_64 ortamında `examples/api-backend/bench.py` ile 3 tur derleme ve her uç noktaya 1.000 istek gönderilerek ölçülen veriler:

| Metrik | LIR Backend | Zig Backend | Fark / Avantaj |
|:---|:---:|:---:|:---|
| **Derleme Süresi (Build Time)** | **9.2 ms** | 5,675.5 ms (5.6 sn) | **LIR 616x daha hızlı derleniyor** (anlık) |
| **İkili Dosya Boyutu (Binary Size)** | **38.6 KB** (39,522 bayt) | 1,729.8 KB (1.77 MB) | **LIR 45x daha kompakt** |
| **Bellek Tüketimi (Resident RSS)** | **4 KB** | 4 KB | Eşit (sıfır GC, minimal bellek) |
| **GET /api/v1/health RPS** | 41,464 req/s | **46,029 req/s** | Zig %10 daha yüksek throughput |
| **GET /api/v1/health p50 Latency** | 0.022 ms (22 µs) | **0.019 ms (19 µs)** | Her ikisi de aşırı düşük gecikme |
| **GET /api/v1/health p99 Latency** | 0.048 ms (48 µs) | **0.045 ms (45 µs)** | Mikro-saniye seviyesinde deterministik |
| **GET /api/v1/users RPS** | 30,302 req/s | **45,706 req/s** | Zig SIMD optimizasyonları |
| **POST /api/v1/users (Auth) RPS** | 1,740 req/s | **2,750 req/s** | Her ikisi de anlık yanıt |
| **Harici Bağımlılık (Dependencies)** | **Sıfır** (Doğrudan Syscall) | Standart Kütüphane | Tam bağımsız |

---

## 3. Kod Ergonomisi ve Sözdizimi Karşılaştırması

### A. Erken Çıkış ve Doğrulama: `guard` vs `if`

#### LIR:
```lir
proc parseUserId(req: *u8, len: i64) -> i64 {
    let prefix = "/api/v1/users/"
    let p = findSubstr(req, len, prefix)
    guard p >= 0 else return -1
    // ...
}
```

#### Zig:
```zig
fn parseUserId(req: []const u8) i64 {
    const prefix = "/api/v1/users/";
    const idx = std.mem.indexOf(u8, req, prefix) orelse return -1;
    // ...
}
```

### B. Ters Koşul Yapısı: `unless`

#### LIR:
```lir
let has_auth = (findSubstr(req_buf, req_len, "Bearer lir-secret-token-2026") >= 0)
unless has_auth {
    sendHttpResponse(client_fd, 401, "Unauthorized", "application/json", unauth.ptr as *u8, unauth.len)
}
```

#### Zig:
```zig
const has_auth = std.mem.indexOf(u8, req, "Bearer lir-secret-token-2026") != null;
if (!has_auth) {
    try sendResponse(connection.stream, 401, "Unauthorized", "application/json", "...");
}
```

### C. Döngü Yapısı: `until`

#### LIR:
```lir
var i = 0
until i >= user_count {
    if user_active[i] == 1 {
        // kullanıcıyı serileştir
    }
    i += 1
}
```

#### Zig:
```zig
for (users[0..user_count]) |u| {
    if (u.active) {
        // kullanıcıyı serileştir
    }
}
```

---

## 4. Temel Çıkarımlar ve Değerlendirme

1. **Geliştirici Döngüsü (Feedback Loop):**
   - **LIR:** 9 milisaniyelik derleme süresi ile neredeyse script dilleri (Python/Node.js) hızında anında kod deneme imkanı sunar, ancak arka planda doğrudan x86-64 makine koduna derlenir.
   - **Zig:** LLVM optimizasyon boru hattı nedeniyle derleme 5-6 saniye sürer. Geliştirme esnasında iterasyon hızı LIR'ın gerisindedir.

2. **Dağıtım ve Container Boyutu (Cloud Footprint):**
   - **LIR:** 38.6 KB boyutundaki tek bir statik ikili dosya, Docker/scratch konteynerlarında neredeyse hiç yer kaplamadan saniyede 40.000+ istek işleyebilir.
   - **Zig:** 1.7 MB boyutuyla yine modern standartlara göre küçüktür (Go veya Java'ya kıyasla çok avantajlı), ancak LIR'a kıyasla 45 kat daha büyüktür.

3. **Veri Modeli ve Tip Güvenliği:**
   - **Zig:** Zengin struct, union, optional (`?T`) ve hata kümeleri (`!void`) desteğiyle kurumsal büyük projelerde tip güvenliği ve hata yönetimi konusunda daha gelişmiştir.
   - **LIR:** Düşük seviyeli bellek düzeni, pointer aritmetiği ve donanıma yakın doğrudan çağrılar (`@syscall`) ile azami kontrol sağlar.
