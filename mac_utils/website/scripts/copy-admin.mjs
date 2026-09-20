/**
 * Yönetim panelini site çıktısının içine kopyalar.
 *
 * Panel ve tanıtım sitesi tek bir Firebase Hosting sitesinde yaşıyor
 * (`/admin` yolu panelin). Depoyu ayırırken panel kendi klasörüne
 * taşındı ama hosting kaynağı yalnızca `website/dist`i gösteriyor —
 * yani derleyip dağıtırsan canlıdaki `/admin` silinirdi. Bu betik
 * derlemeden sonra paneli çıktının içine koyuyor.
 *
 * Panelin kaynağı yok, elde yalnızca Firebase'den geri indirilen
 * derlenmiş çıktı var; o yüzden burada iş "derlemek" değil "kopyalamak".
 */
import { cp, access, readdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const source = join(here, "..", "..", "admin", "out");
const target = join(here, "..", "dist");

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

if (!(await exists(source))) {
  console.error(`admin cikti klasoru yok: ${source}`);
  process.exit(1);
}

/*
 * Site ve panel aynı yazı tiplerini kullanıyor. `force: false` ile
 * sitenin kendi dosyaları korunuyor; panel yalnızca kendi klasörlerini
 * (admin.html, admin/, _next/) ekliyor.
 */
for (const entry of await readdir(source)) {
  await cp(join(source, entry), join(target, entry), {
    recursive: true,
    force: entry !== "fonts",
    errorOnExist: false,
  });
}

console.log("yonetim paneli dist/ icine kopyalandi");
