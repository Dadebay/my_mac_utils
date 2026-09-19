/**
 * Nav bar'ın altına giren her şeyi kum tanelerine ayırır.
 *
 * Maskeyle "silmek" yerine öğenin kendi görüntüsü kullanılıyor: bir şey
 * dağılma çizgisine değdiğinde küçük bir tuvale çizilip pikselleri
 * okunuyor ve dolu her noktadan bir tane doğuyor. Dağılan şey gerçekten
 * o şeyin biçimi — "A" ile "o", yuvarlak bir buton ile ince bir ikon
 * farklı dağılıyor.
 *
 * Dört tür çiziliyor:
 *   harf   — glif, sayfadaki yazı tipiyle
 *   görsel — <img>, olduğu gibi
 *   ikon   — satır içi <svg>, data URI'ye çevrilip rasterleştirilerek
 *   kutu   — arka planı ya da kenarlığı olan her öğe; köşe yarıçapı,
 *            dolgu ve kenarlık rengiyle yeniden çizilerek
 *
 * Harfler küçük olduğu için bir bütün hâlinde patlıyor. Kutular
 * yüksek olabildiğinden şerit şerit: her karede çizgiyi yeni geçen
 * bant taneye dönüşüyor, kalan kısım `clip-path` ile tam o hizadan
 * kesiliyor. Kesik kenarı, hemen üstündeki tane bulutu örtüyor — bu
 * yüzden ortada görünür bir çizgi kalmıyor.
 */

/** Nav bar'ın alt hizası: üst boşluk + yüksekliği. */
const NAV_BOTTOM = 88;

/**
 * Dağılmanın olduğu çizgi: nav'ın biraz altı. Tam nav hizasında
 * patlatmak geç kalıyor — öğe önce nav'ın altına girip görünmez oluyor,
 * sonra dağılıyordu. Biraz aşağıda patlayınca nav'a hiç değmiyor.
 */
const SHATTER_LINE = NAV_BOTTOM + 28;

/** Dağılan bir tanenin ömrü (ms). */
const LIFE = 700;

/** Toplanan bir tanenin yerine oturma süresi (ms). */
const LIFE_IN = 420;

/** Toplanan tanelerin doğuşu kaç ms'ye yayılıyor. */
const GATHER_STAGGER = 100;

/**
 * Toplanma kaç piksel önceden başlıyor.
 *
 * Geri kaydırırken harf çizginin üstünden aşağı doğru geliyor. Toplanmayı
 * ancak çizgiyi geçtikten sonra başlatmak, harfin çizginin altında bir
 * süre yok görünmesine ve sonra birden belirmesine yol açıyordu. Şimdi
 * taneler harf daha yukarıdayken toplanmaya başlıyor ve harf tam çizgiyi
 * geçerken yerine oturmuş oluyor.
 */
const GATHER_LEAD = 110;

/**
 * Tek karede en çok kaç öğe rasterleştirilsin.
 *
 * Bir blok tümüyle çizgiyi geçtiğinde yüzlerce harf aynı anda taneye
 * dönmek istiyor; her biri tuval boyutlandırma + `getImageData`
 * demek. Bütçe dolunca kalanlar tane üretmeden, doğrudan gizlenip
 * gösteriliyor — kaydırma takılmıyor.
 */
const RASTER_BUDGET = 48;

/** Aynı anda yaşayabilecek en çok tane — hızlı kaydırmada tavan. */
const MAX_PARTICLES = 9000;

/** Tek karede bir kutudan kopabilecek en yüksek şerit (px). */
const MAX_STRIP = 240;

/**
 * Kaydırma hızına göre ayrıntı.
 *
 * Yavaş kaydırırken animasyon bütün ayrıntısıyla oynuyor. Hızlı
 * kaydırırken kimse taneleri seyretmiyor; orada istenen şey içeriğin
 * gecikmeden geçmesi. Bu yüzden hız arttıkça taneler seyreliyor ve
 * ömürleri kısalıyor, belli bir hızın üstünde ise hiç üretilmiyor.
 */
const CALM_SPEED = 25;
const SKIP_SPEED = 120;

/**
 * Tane iki yönde de çalışıyor.
 *
 * `out` — aşağı kaydırırken: öğeden kopup savruluyor ve sönüyor.
 * `in`  — geri yukarı kaydırırken: dağınık bir noktadan doğup öğenin
 *         üzerindeki kendi yerine oturuyor, sonra öğe geri görünüyor.
 */
interface Particle {
  x: number;
  y: number;
  /** `out` için hız; `in` için kullanılmıyor. */
  vx: number;
  vy: number;
  /** `in` için: nereden başladı ve nereye oturacak. */
  sx: number;
  sy: number;
  tx: number;
  ty: number;
  inward: boolean;
  size: number;
  born: number;
  life: number;
  color: string;
}

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

/* ------------------------------------------------------------------ */
/* Tuvaller                                                            */
/* ------------------------------------------------------------------ */

const canvas = document.createElement("canvas");
canvas.className = "sand-canvas";
canvas.setAttribute("aria-hidden", "true");
const ctx = canvas.getContext("2d", { alpha: true })!;

function resizeCanvas() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.floor(innerWidth * dpr);
  canvas.height = Math.floor(innerHeight * dpr);
  canvas.style.width = innerWidth + "px";
  canvas.style.height = innerHeight + "px";
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}

/** Örnekleme için tek bir küçük tuval yeniden kullanılıyor. */
const scratch = document.createElement("canvas");
const sctx = scratch.getContext("2d", { willReadFrequently: true })!;

const particles: Particle[] = [];

/** Saydam yüzeyleri üstüne bindirmek için sayfanın zemin rengi. */
const pageBackground = getComputedStyle(document.body).backgroundColor || "#0a0b0f";

/** `rgb(r, g, b)` dizgileri tekrar tekrar üretilmesin. */
const colorCache = new Map<number, string>();
function colorOf(r: number, g: number, b: number): string {
  r |= 0;
  g |= 0;
  b |= 0;
  const key = (r << 16) | (g << 8) | b;
  let value = colorCache.get(key);
  if (!value) {
    value = `rgb(${r},${g},${b})`;
    colorCache.set(key, value);
  }
  return value;
}

/**
 * Hazırlanmış tuvalin piksellerinden tane doğurur.
 *
 * `originX/originY` çizimin ekrandaki sol üst köşesi; `step` tane
 * sıklığı. Saydam pikseller atlanıyor, yani dağılan şey öğenin dolu
 * kısmı — dikdörtgen bir blok değil.
 */
function scatter(
  width: number,
  height: number,
  originX: number,
  originY: number,
  step: number,
  now: number,
  inward = false,
  boost = 1,
) {
  if (width <= 0 || height <= 0) return;
  // Çok hızlı kaydırmada tane üretilmiyor: içerik beklemeden geçsin.
  if (scrollSpeed > SKIP_SPEED) return;

  /* Hız arttıkça taneler seyreliyor, ama bir yere kadar: iri bloklar
     kum gibi değil moloz gibi duruyor. Toplanma tarafında hiç
     seyrelmiyor — asıl seyredilen an orası. */
  step = Math.min(5, Math.max(1, Math.round(step / (inward ? 1 : detail))));

  const data = sctx.getImageData(0, 0, width, height).data;
  const size = Math.max(1, step);
  const life = (inward ? LIFE_IN : LIFE) * detail;

  for (let y = 0; y < height; y += step) {
    for (let x = 0; x < width; x += step) {
      const i = (y * width + x) * 4;
      if (data[i + 3] < 110) continue;
      if (particles.length >= MAX_PARTICLES) return;

      /* Örnekleme ızgarası olduğu gibi kullanılınca taneler satır satır
         dizilmiş görünüyor; yarım tanelik kaydırma bunu bozuyor. */
      const px = originX + x + (Math.random() - 0.5) * step;
      const py = originY + y + (Math.random() - 0.5) * step;
      /* Toplanırken taneler yukarıdan ve dağınık gelsin — dağılmanın
         tersi bir yol izliyorlar. */
      const sx = inward ? px + (Math.random() - 0.5) * 120 : px;
      const sy = inward ? py - 40 - Math.random() * 120 : py;

      particles.push({
        x: sx,
        y: sy,
        /* Yukarı ve yanlara savruluyor; küçük bir rastgelelik taneleri
           tek kütle hâlinde uçmaktan kurtarıyor. */
        vx: (Math.random() - 0.5) * 0.14,
        vy: -0.015 - Math.random() * 0.09,
        sx,
        sy,
        tx: px,
        ty: py,
        inward,
        size,
        born: now + Math.random() * (inward ? GATHER_STAGGER : 90) * detail,
        life,
        color: colorOf(
          Math.min(255, data[i] * boost),
          Math.min(255, data[i + 1] * boost),
          Math.min(255, data[i + 2] * boost),
        ),
      });
    }
  }
}

function prepare(width: number, height: number) {
  scratch.width = width;
  scratch.height = height;
  sctx.clearRect(0, 0, width, height);
}

/* ------------------------------------------------------------------ */
/* Harfler                                                             */
/* ------------------------------------------------------------------ */

interface CharSpan {
  el: HTMLElement;
  gone: boolean;
  /** Toplanma bittiğinde harfin geri görüneceği an; 0 ise toplanmıyor. */
  returnAt: number;
}

interface TextBlock {
  el: HTMLElement;
  chars: CharSpan[] | null;
}

function hasOwnText(el: Element): boolean {
  for (const node of el.childNodes) {
    if (node.nodeType === Node.TEXT_NODE && node.textContent && node.textContent.trim()) return true;
  }
  return false;
}

/**
 * Metni harf harf `<span>`'lere böler.
 *
 * Boşluklar düz metin düğümü olarak kalıyor: satır sonları yalnızca
 * boşluklarda oluştuğu için sarmalama yerleşimi değiştirmiyor. Span'ler
 * `display: inline`, yani kutu modeli de aynı.
 */
function wrapChars(block: HTMLElement): CharSpan[] {
  const chars: CharSpan[] = [];
  const texts: Text[] = [];

  for (const node of block.childNodes) {
    if (node.nodeType === Node.TEXT_NODE && node.textContent && node.textContent.trim()) {
      texts.push(node as Text);
    }
  }

  for (const text of texts) {
    const fragment = document.createDocumentFragment();
    let buffer = "";

    const flush = () => {
      if (!buffer) return;
      fragment.appendChild(document.createTextNode(buffer));
      buffer = "";
    };

    for (const ch of text.data) {
      if (ch.trim() === "") {
        buffer += ch;
        continue;
      }
      flush();
      const span = document.createElement("span");
      span.className = "sand-char";
      span.textContent = ch;
      fragment.appendChild(span);
      chars.push({ el: span, gone: false, returnAt: 0 });
    }

    flush();
    text.replaceWith(fragment);
  }

  return chars;
}

/**
 * Harfi geri getirir: önce taneler yerine oturuyor, oturma bitince harf
 * görünür oluyor. Bekleyen bir toplanma varken tekrar çağrılmıyor, yoksa
 * her karede yeni tane doğar.
 */
function showChar(c: CharSpan) {
  c.gone = false;
  c.returnAt = 0;
  c.el.style.visibility = "";
  /* Harf birden yapışmasın: taneler inerken kendisi de beliriyor, ikisi
     üst üste gelince "parçalar birleşti" hissi tamamlanıyor. */
  c.el.style.animation = `sand-return ${Math.round(LIFE_IN * detail)}ms linear`;
}

/**
 * Harfi geri getirir.
 *
 * `crossed` — harf çizginin altına inmiş demek: orada artık görünür
 * olmak zorunda, yoksa çizginin altında bir süre boşluk kalıyor. O yüzden
 * toplanma bitmemiş olsa bile gösteriliyor; taneler zaten yola çıkmış
 * olduğu için geçiş yine de dolu görünüyor.
 */
function restoreChar(c: CharSpan, now: number, crossed: boolean) {
  if (!c.gone) return;

  /* Taneler bir kez yola çıkıyor: `returnAt` dolu olduğu sürece yeniden
     üretilmiyor, yoksa her karede yeni bir avuç doğardı. */
  if (!c.returnAt) {
    shatterChar(c.el, now, true);
    c.returnAt = now + (LIFE_IN + GATHER_STAGGER) * detail;
  }

  /* Görünür olmanın tek koşulu çizgiyi geçmiş olmak. Toplanma bitmiş
     olsa bile çizginin üstünde gösterilmiyor — orada her şeyin dağılmış
     olması gerekiyor. */
  if (crossed) showChar(c);
}

function canRaster(): boolean {
  if (scrollSpeed > SKIP_SPEED) return false;
  if (rasterBudget <= 0) return false;
  rasterBudget--;
  return true;
}

function shatterChar(span: HTMLElement, now: number, inward = false) {
  if (!canRaster()) return;

  const rect = span.getBoundingClientRect();
  if (rect.width < 0.5 || rect.height < 0.5) return;

  const style = getComputedStyle(span);
  const fontSize = parseFloat(style.fontSize) || 16;
  const font = `${style.fontStyle} ${style.fontWeight} ${fontSize}px ${style.fontFamily}`;
  const text = span.textContent || "";

  sctx.font = font;
  sctx.textBaseline = "alphabetic";
  const metrics = sctx.measureText(text);
  const ascent = metrics.actualBoundingBoxAscent;
  const descent = metrics.actualBoundingBoxDescent;
  const left = metrics.actualBoundingBoxLeft;
  const right = metrics.actualBoundingBoxRight;

  const width = Math.ceil(right + left) || Math.ceil(rect.width);
  const height = Math.ceil(ascent + descent);
  if (width <= 0 || height <= 0) return;

  prepare(width, height);
  // Tuval boyutu değişince bağlam sıfırlanıyor; ayarlar yeniden veriliyor.
  sctx.font = font;
  sctx.textBaseline = "alphabetic";
  sctx.fillStyle = style.color;
  sctx.fillText(text, left, ascent);

  /* Glifin ekrandaki yeri: taban çizgisi span kutusunun içinde, yazı
     tipinin kendi yükseliş ölçüsü kadar aşağıda. */
  const fontAscent = metrics.fontBoundingBoxAscent || ascent;
  const fontDescent = metrics.fontBoundingBoxDescent || descent;
  const baseline = rect.top + (rect.height - (fontAscent + fontDescent)) / 2 + fontAscent;

  scatter(width, height, rect.left - left, baseline - ascent, Math.max(1, Math.round(fontSize / 24)), now, inward);
}

/* ------------------------------------------------------------------ */
/* Kutular, görseller, ikonlar                                          */
/* ------------------------------------------------------------------ */

interface Box {
  el: HTMLElement;
  /** Üstten kaç piksel dağıldı. */
  cut: number;
}

function alphaOf(color: string): number {
  if (!color || color === "transparent") return 0;
  const match = color.match(/rgba?\(([^)]+)\)/);
  if (!match) return 1;
  const parts = match[1].split(",");
  return parts.length > 3 ? parseFloat(parts[3]) : 1;
}

/** Bulanıklık uygulanmış süsler (ışık halkaları) taneye çevrilmiyor. */
function isPaintedBox(el: Element, style: CSSStyleDeclaration): boolean {
  if (el.tagName === "IMG" || el.tagName === "svg") return true;
  if (style.filter !== "none") return false;
  if (alphaOf(style.backgroundColor) > 0.03) return true;

  const widths = [style.borderTopWidth, style.borderRightWidth, style.borderBottomWidth, style.borderLeftWidth];
  const colors = [style.borderTopColor, style.borderRightColor, style.borderBottomColor, style.borderLeftColor];
  for (let i = 0; i < 4; i++) {
    if (parseFloat(widths[i]) > 0 && alphaOf(colors[i]) > 0.03) return true;
  }
  return false;
}

/** Rasterleştirilmiş satır içi SVG'ler — ikon başına bir kez. */
const svgBitmaps = new WeakMap<Element, HTMLImageElement>();

function rasterizeSvg(el: SVGElement) {
  if (svgBitmaps.has(el)) return;

  const rect = el.getBoundingClientRect();
  if (rect.width < 1 || rect.height < 1) return;

  const clone = el.cloneNode(true) as SVGElement;
  clone.setAttribute("width", String(Math.ceil(rect.width)));
  clone.setAttribute("height", String(Math.ceil(rect.height)));
  /* İkonlar `currentColor` kullanıyor; tek başına bir dosyada bunun
     karşılığı olmadığı için hesaplanan renk yazılıyor. */
  clone.setAttribute("stroke", getComputedStyle(el).color);

  const markup = new XMLSerializer().serializeToString(clone);
  const image = new Image();
  image.decoding = "sync";
  image.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(markup);
  svgBitmaps.set(el, image);
}

function roundedRectPath(target: CanvasRenderingContext2D, w: number, h: number, r: number) {
  const radius = Math.min(r, w / 2, h / 2);
  target.beginPath();
  target.moveTo(radius, 0);
  target.arcTo(w, 0, w, h, radius);
  target.arcTo(w, h, 0, h, radius);
  target.arcTo(0, h, 0, 0, radius);
  target.arcTo(0, 0, w, 0, radius);
  target.closePath();
}

/**
 * Kutunun çizgiyi yeni geçen şeridini taneye çevirir.
 *
 * Öğenin tamamı değil yalnızca `from`–`to` aralığı çiziliyor; tuval o
 * kadar yüksek ve içerik yukarı kaydırılarak konuluyor.
 */
function shatterStrip(el: HTMLElement, from: number, to: number, now: number, inward = false, denseStep = 0) {
  if (!canRaster()) return;

  const rect = el.getBoundingClientRect();
  const width = Math.ceil(rect.width);
  const height = Math.ceil(to - from);
  if (width <= 0 || height <= 0) return;

  prepare(width, height);
  sctx.translate(0, -from);

  const style = getComputedStyle(el);
  let isFlatBox = false;

  if (el.tagName === "IMG") {
    const img = el as HTMLImageElement;
    if (img.complete && img.naturalWidth > 0) {
      sctx.drawImage(img, 0, 0, rect.width, rect.height);
    }
  } else if (el.tagName === "svg") {
    const bitmap = svgBitmaps.get(el);
    if (bitmap && bitmap.complete && bitmap.naturalWidth > 0) {
      sctx.drawImage(bitmap, 0, 0, rect.width, rect.height);
    }
  } else {
    /*
     * Cam yüzeylerin dolgusu %5 saydam; doğrudan boş tuvale çizilince
     * piksellerin saydamlığı eşiğin altında kalıyor ve kutu hiç
     * örneklenmiyordu. Önce sayfa zemini basılıp üstüne kutu çiziliyor:
     * artık her piksel opak ve rengi kutunun ekranda göründüğü renk.
     * Şekli korumak için çizim kutunun kendi yoluna kırpılıyor.
     */
    const radius = parseFloat(style.borderTopLeftRadius) || 0;

    sctx.save();
    roundedRectPath(sctx, rect.width, rect.height, radius);
    sctx.clip();

    sctx.fillStyle = pageBackground;
    sctx.fillRect(0, 0, rect.width, rect.height);

    if (alphaOf(style.backgroundColor) > 0.03) {
      sctx.fillStyle = style.backgroundColor;
      sctx.fillRect(0, 0, rect.width, rect.height);
    }

    const borderWidth = parseFloat(style.borderTopWidth) || 0;
    if (borderWidth > 0 && alphaOf(style.borderTopColor) > 0.03) {
      roundedRectPath(sctx, rect.width, rect.height, radius);
      sctx.lineWidth = Math.max(1, borderWidth) * 2;
      sctx.strokeStyle = style.borderTopColor;
      sctx.stroke();
    }

    sctx.restore();
    isFlatBox = true;
  }

  sctx.setTransform(1, 0, 0, 1, 0, 0);

  /* Tane sıklığı kutunun genişliğiyle biraz açılıyor: kocaman bir kart
     da ince bir buton da benzer yoğunlukta dağılıyor. */
  const step = denseStep || Math.max(2, Math.round(Math.min(rect.width, 600) / 220));
  /* Zeminin üstüne bindirilen kutular neredeyse zemin rengi çıkıyor;
     taneler görünsün diye biraz aydınlatılıyor. Görsel ve ikonlar kendi
     renkleriyle kalıyor. */
  scatter(width, height, rect.left, rect.top + from, step, now, inward, isFlatBox ? 1.9 : 1);
}

/* ------------------------------------------------------------------ */
/* Döngü                                                               */
/* ------------------------------------------------------------------ */

const textBlocks: TextBlock[] = [];
const boxes: Box[] = [];

function collect() {
  textBlocks.length = 0;
  boxes.length = 0;

  for (const root of document.querySelectorAll<HTMLElement>("[data-dissolve-root]")) {
    for (const el of root.querySelectorAll<HTMLElement>("*")) {
      if (hasOwnText(el)) textBlocks.push({ el, chars: null });

      const style = getComputedStyle(el);
      if (isPaintedBox(el, style)) {
        boxes.push({ el, cut: 0 });
        if (el.tagName === "svg") rasterizeSvg(el as unknown as SVGElement);
      }
    }
  }
}

let lastScrollY = window.scrollY;
let running = false;
let pendingScan = true;

/** Kare başına kaydırma (px), yumuşatılmış. */
let scrollSpeed = 0;
/** 1 = tam ayrıntı, 0'a yaklaştıkça seyrek ve kısa ömürlü. */
let detail = 1;
/** Bu karede kalan rasterleştirme hakkı. */
let rasterBudget = RASTER_BUDGET;

function frame(now: number) {
  const scrollDelta = window.scrollY - lastScrollY;
  lastScrollY = window.scrollY;

  /*
   * Sayfa durduysa ve havada tane kalmadıysa döngü kapanıyor; bir
   * sonraki kaydırma geri açıyor. Boşta dönen bir rAF döngüsü, hiçbir
   * şey değişmese bile her karede düzen ölçümü yaptırırdı.
   */
  if (scrollDelta === 0 && particles.length === 0 && !pendingScan) {
    running = false;
    return;
  }
  pendingScan = false;

  scrollSpeed = scrollSpeed * 0.6 + Math.abs(scrollDelta) * 0.4;
  detail = scrollSpeed <= CALM_SPEED ? 1 : Math.max(0.3, CALM_SPEED / scrollSpeed);
  rasterBudget = RASTER_BUDGET;

  for (const block of textBlocks) {
    const rect = block.el.getBoundingClientRect();

    // Tamamen çizginin altında ve öncü bölgenin de dışında: bitti.
    if (rect.top > SHATTER_LINE + 4) {
      if (block.chars) {
        for (const c of block.chars) restoreChar(c, now, true);
      }
      continue;
    }

    // Tamamen çizginin üstünde: hepsini bir kerede patlat.
    if (rect.bottom < SHATTER_LINE - GATHER_LEAD) {
      /* Hızlı kaydırmada bir blok, harfleri hiç sarmalanmadan çizgiyi
         tamamen geçebiliyor; o hâlde önce sarmalanıyor, yoksa metin
         nav'ın üstünde öylece duruyordu. */
      if (!block.chars) block.chars = wrapChars(block.el);
      {
        for (const c of block.chars) {
          if (c.gone) continue;
          c.gone = true;
          c.returnAt = 0;
          c.el.style.animation = "";
          shatterChar(c.el, now);
          c.el.style.visibility = "hidden";
        }
      }
      continue;
    }

    if (!block.chars) block.chars = wrapChars(block.el);

    for (const c of block.chars) {
      const r = c.el.getBoundingClientRect();

      /* Harfin *üstü* çizgiye değdiği anda patlıyor: yarım harf
         görünmüyor, hepsi birden taneye dönüşüyor. */
      if (!c.gone && r.top <= SHATTER_LINE) {
        c.gone = true;
        c.returnAt = 0;
        c.el.style.animation = "";
        shatterChar(c.el, now);
        c.el.style.visibility = "hidden";
      } else if (c.gone && r.top > SHATTER_LINE) {
        restoreChar(c, now, true);
      } else if (c.gone && r.top > SHATTER_LINE - GATHER_LEAD) {
        /* Öncü bölge: harf hâlâ çizginin üstünde ama aşağı doğru
           geliyor. Taneler şimdiden toplanmaya başlıyor ki harf
           çizgiye vardığında bütün hâline gelmiş olsun. */
        restoreChar(c, now, false);
      }
    }
  }

  for (const box of boxes) {
    const rect = box.el.getBoundingClientRect();
    const wanted = Math.min(Math.max(0, SHATTER_LINE - rect.top), rect.height);

    if (wanted === box.cut) continue;

    if (wanted > box.cut) {
      // Yeni geçen şerit taneye dönüşüyor.
      const from = box.cut;
      const to = Math.min(wanted, from + MAX_STRIP);
      shatterStrip(box.el, from, to, now);
      /* Kesim kenarına ayrıca sık bir bant: yavaş kaydırmada bile
         kenarda görünür bir tane kalabalığı oluşuyor, kesik göze
         çizgi olarak görünmüyor. */
      shatterStrip(box.el, Math.max(0, to - 10), to, now, false, 2);
    } else {
      /* Geri kaydırma: açılan şeridin taneleri yerine toplanıyor.

         Yavaş kaydırırken bu şerit karede bir iki piksel kalıyor ve
         neredeyse hiç tane çıkmıyordu; bu yüzden açılan kenarın hemen
         altındaki bant da, henüz görünür olacak alanın malzemesi
         olarak, sık bir şekilde örnekleniyor. */
      const to = box.cut;
      const from = Math.max(wanted, to - MAX_STRIP);
      shatterStrip(box.el, from, to, now, true);
      shatterStrip(box.el, wanted, Math.min(rect.height, wanted + 26), now, true, 3);
    }

    box.cut = wanted;

    if (wanted <= 0) {
      box.el.removeAttribute("data-sand-cut");
      box.el.style.removeProperty("--sand-cut");
      box.el.style.visibility = "";
    } else if (wanted >= rect.height) {
      box.el.style.visibility = "hidden";
    } else {
      box.el.style.visibility = "";
      box.el.setAttribute("data-sand-cut", "");
      box.el.style.setProperty("--sand-cut", wanted + "px");
    }
  }

  ctx.clearRect(0, 0, innerWidth, innerHeight);

  let color = "";
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    const age = now - p.born;

    if (age > p.life) {
      particles.splice(i, 1);
      continue;
    }
    if (age < 0) continue;

    /* Sayfa kaydıkça taneler de kayıyor: içerikten koparak havada asılı
       kalmıyorlar, kaydırmaya tutunup öyle gidip geliyorlar. */
    let fade: number;

    if (p.inward) {
      p.sy -= scrollDelta;
      p.ty -= scrollDelta;

      // Sona doğru yavaşlayarak yerine oturuyor.
      const t = age / p.life;
      const ease = 1 - (1 - t) * (1 - t) * (1 - t);
      p.x = p.sx + (p.tx - p.sx) * ease;
      p.y = p.sy + (p.ty - p.sy) * ease;
      /* Yolun başında beliriyor ve sonuna kadar parlak kalıyor: tane
         tam yerine oturduğu anda kayboluyor, öğe de o anda görünür
         oluyor. Önceden inişte sönüyordu ve toplanma bir bulanıklık
         gibi okunuyordu. */
      fade = Math.min(1, t * 3);
    } else {
      p.y -= scrollDelta;
      p.x += p.vx * 16;
      p.y += p.vy * 16;
      p.vy -= 0.0009;
      fade = 1 - age / p.life;
      fade *= fade;
    }

    if (p.color !== color) {
      color = p.color;
      ctx.fillStyle = color;
    }
    ctx.globalAlpha = fade;
    ctx.fillRect(p.x, p.y, p.size, p.size);
  }
  ctx.globalAlpha = 1;

  requestAnimationFrame(frame);
}

function wake() {
  pendingScan = true;
  if (running) return;
  running = true;
  lastScrollY = window.scrollY;
  requestAnimationFrame(frame);
}

function start() {
  if (reduceMotion.matches) return;

  document.body.appendChild(canvas);
  resizeCanvas();
  collect();
  wake();

  addEventListener("scroll", wake, { passive: true });
  addEventListener("resize", () => {
    resizeCanvas();
    wake();
  });
}

start();
