/**
 * Nav bar'ın arkasına giren yazıyı kum tanelerine ayırır.
 *
 * Maskeyle "silmek" yerine harfin kendi şeklini kullanıyor: harf nav
 * çizgisine geldiğinde glifi küçük bir tuvale çizilip piksellerine
 * bakılıyor, dolu her noktadan bir tane doğuyor. Yani dağılan şey harfin
 * gerçek biçimi — "A" ile "o" farklı dağılıyor.
 *
 * Bütçe: harflere ancak nav çizgisini kestikleri karede dokunuluyor.
 * Tamamen altta kalan blok atlanıyor, tamamen üstte kalan blok bir kere
 * gizlenip listeden düşüyor; yani kare başına ölçülen harf sayısı
 * çizgiyi kesen bir iki satırla sınırlı.
 */

/** Nav bar'ın alt hizası: üst boşluk + yüksekliği. */
const NAV_BOTTOM = 88;

/**
 * Harflerin dağıldığı çizgi: nav'ın biraz altı.
 *
 * Tam nav hizasında patlatmak geç kalıyordu — satır önce nav'ın altına
 * girip soluyor, sonra dağılıyordu. Biraz aşağıda patlayınca harf nav'a
 * hiç değmeden taneye dönüşüyor.
 */
const SHATTER_LINE = NAV_BOTTOM + 28;

/** Bir tanenin ömrü (ms). */
const LIFE = 700;

/** Aynı anda yaşayabilecek en çok tane — hızlı kaydırmada tavan. */
const MAX_PARTICLES = 7000;

interface Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  size: number;
  born: number;
  color: string;
}

interface CharSpan {
  el: HTMLElement;
  gone: boolean;
}

interface Block {
  el: HTMLElement;
  chars: CharSpan[] | null;
  done: boolean;
}

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

function isTextBlock(el: Element): boolean {
  for (const node of el.childNodes) {
    if (node.nodeType === Node.TEXT_NODE && node.textContent && node.textContent.trim()) return true;
  }
  return false;
}

/**
 * Metni harf harf `<span>`'lere böler.
 *
 * Boşluklar düz metin düğümü olarak kalıyor: satır sonları yalnızca
 * boşluklarda oluştuğu için sarmalama yerleşimi hiç değiştirmiyor.
 * Span'ler `display: inline` — kutu modeli de aynı kalıyor.
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
      chars.push({ el: span, gone: false });
    }

    flush();
    text.replaceWith(fragment);
  }

  return chars;
}

const canvas = document.createElement("canvas");
canvas.className = "sand-canvas";
canvas.setAttribute("aria-hidden", "true");
const ctx = canvas.getContext("2d", { alpha: true })!;

let dpr = 1;
function resizeCanvas() {
  dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.floor(innerWidth * dpr);
  canvas.height = Math.floor(innerHeight * dpr);
  canvas.style.width = innerWidth + "px";
  canvas.style.height = innerHeight + "px";
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}

/** Glif okumak için tek bir küçük tuval yeniden kullanılıyor. */
const glyphCanvas = document.createElement("canvas");
const glyphCtx = glyphCanvas.getContext("2d", { willReadFrequently: true })!;

const particles: Particle[] = [];

/**
 * Harfin glifini çizip dolu piksellerinden tane üretir.
 *
 * Örnekleme adımı yazı boyuyla büyüyor: büyük başlıklar da küçük
 * satırlar da kabaca aynı sayıda taneye ayrılıyor, yani maliyet punto
 * arttıkça patlamıyor.
 */
function emit(span: HTMLElement, now: number) {
  const rect = span.getBoundingClientRect();
  if (rect.width < 0.5 || rect.height < 0.5) return;

  const style = getComputedStyle(span);
  const fontSize = parseFloat(style.fontSize) || 16;
  const font = `${style.fontStyle} ${style.fontWeight} ${fontSize}px ${style.fontFamily}`;
  const color = style.color;

  glyphCtx.font = font;
  glyphCtx.textBaseline = "alphabetic";
  const metrics = glyphCtx.measureText(span.textContent || "");
  const ascent = metrics.actualBoundingBoxAscent;
  const descent = metrics.actualBoundingBoxDescent;
  const left = metrics.actualBoundingBoxLeft;
  const right = metrics.actualBoundingBoxRight;

  const width = Math.ceil(right + left) || Math.ceil(rect.width);
  const height = Math.ceil(ascent + descent);
  if (width <= 0 || height <= 0) return;

  glyphCanvas.width = width;
  glyphCanvas.height = height;
  // Tuval boyutu değişince bağlam sıfırlanıyor; yazı tipi yeniden veriliyor.
  glyphCtx.font = font;
  glyphCtx.textBaseline = "alphabetic";
  glyphCtx.fillStyle = "#fff";
  glyphCtx.fillText(span.textContent || "", left, ascent);

  const data = glyphCtx.getImageData(0, 0, width, height).data;

  /* Glifin sol üstünün ekrandaki yeri: taban çizgisi span kutusunun
     içinde, yazı tipinin kendi yükseliş ölçüsü kadar aşağıda. */
  const fontAscent = metrics.fontBoundingBoxAscent || ascent;
  const fontDescent = metrics.fontBoundingBoxDescent || descent;
  const baseline = rect.top + (rect.height - (fontAscent + fontDescent)) / 2 + fontAscent;
  const originX = rect.left - left;
  const originY = baseline - ascent;

  /* Tane boyu punto ile büyüyor ama yavaş: büyük başlık iri bloklara
     değil, daha çok sayıda ince taneye ayrılıyor. */
  const step = Math.max(1, Math.round(fontSize / 24));
  const size = step;

  for (let y = 0; y < height; y += step) {
    for (let x = 0; x < width; x += step) {
      if (data[(y * width + x) * 4 + 3] < 110) continue;
      if (particles.length >= MAX_PARTICLES) return;

      particles.push({
        x: originX + x,
        y: originY + y,
        /* Yukarı ve yanlara doğru dağılıyor; küçük bir rastgelelik
           taneleri tek kütle hâlinde uçmaktan kurtarıyor. */
        vx: (Math.random() - 0.5) * 0.14,
        vy: -0.015 - Math.random() * 0.09,
        size,
        born: now + Math.random() * 90,
        color,
      });
    }
  }
}

const blocks: Block[] = [];
let lastScrollY = window.scrollY;
let running = false;
let pendingScan = true;

function collectBlocks() {
  blocks.length = 0;
  for (const root of document.querySelectorAll<HTMLElement>("[data-dissolve-root]")) {
    for (const el of root.querySelectorAll<HTMLElement>("*")) {
      if (isTextBlock(el)) blocks.push({ el, chars: null, done: false });
    }
  }
}

function frame(now: number) {
  const scrollDelta = window.scrollY - lastScrollY;
  lastScrollY = window.scrollY;

  /*
   * Sayfa durduysa ve havada tane kalmadıysa döngü kapanıyor; bir sonraki
   * kaydırma onu geri açıyor. Boşta dönen bir rAF döngüsü, hiçbir şey
   * değişmese bile her karede düzen ölçümü yaptırırdı.
   */
  if (scrollDelta === 0 && particles.length === 0 && !pendingScan) {
    running = false;
    return;
  }
  pendingScan = false;

  for (const block of blocks) {
    if (block.done) continue;

    const rect = block.el.getBoundingClientRect();

    // Tamamen çizginin altında: hiçbir harfine bakmaya gerek yok.
    if (rect.top > SHATTER_LINE) {
      if (block.chars) {
        for (const c of block.chars) {
          if (!c.gone) continue;
          c.gone = false;
          c.el.style.visibility = "";
        }
      }
      continue;
    }

    // Tamamen çizginin üstünde: bir kere gizle, listeden düş.
    if (rect.bottom < SHATTER_LINE - 4) {
      if (block.chars) {
        for (const c of block.chars) {
          if (c.gone) continue;
          c.gone = true;
          emit(c.el, now);
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
        emit(c.el, now);
        c.el.style.visibility = "hidden";
      } else if (c.gone && r.top > SHATTER_LINE + 6) {
        // Geri kaydırıldığında harf yerine dönüyor.
        c.gone = false;
        c.el.style.visibility = "";
      }
    }
  }

  ctx.clearRect(0, 0, innerWidth, innerHeight);

  let color = "";
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    const age = now - p.born;

    if (age > LIFE) {
      particles.splice(i, 1);
      continue;
    }
    if (age < 0) continue;

    /* Sayfa kaydıkça taneler de kayıyor: içerikten koparak havada
       asılı kalmıyorlar, kaydırmaya tutunup öyle sönüyorlar. */
    p.y -= scrollDelta;
    p.x += p.vx * 16;
    p.y += p.vy * 16;
    p.vy -= 0.0009;

    const fade = 1 - age / LIFE;
    if (p.color !== color) {
      color = p.color;
      ctx.fillStyle = color;
    }
    ctx.globalAlpha = fade * fade;
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
  collectBlocks();
  wake();

  addEventListener("scroll", wake, { passive: true });
  addEventListener("resize", () => {
    resizeCanvas();
    wake();
  });
}

start();
