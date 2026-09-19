// @ts-check
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import tailwindcss from "@tailwindcss/vite";

/**
 * Site tamamen statik: tanıtım sayfasında sunucu tarafı bir iş yok ve
 * statik çıktı Firebase Hosting'e olduğu gibi yükleniyor.
 *
 * `site` zorunlu — canonical adresler ve sitemap bu adrese göre üretiliyor.
 */
export default defineConfig({
  site: "https://mac-utils.web.app",
  trailingSlash: "never",
  build: {
    // Firebase `cleanUrls: true` ile sunuyor: /en -> en.html. Astro'nun
    // varsayılanı /en/index.html üretmek; bu ikisi birlikte /en/ adresine
    // yönlendirme doğurup canonical'ı bölerdi.
    format: "file",
  },
  i18n: {
    locales: ["en", "tr", "ru"],
    defaultLocale: "en",
    routing: {
      // Varsayılan dil de öneki taşıyor (/en). Yayındaki yapı böyleydi ve
      // üç dilin de simetrik olması hreflang'i basitleştiriyor.
      prefixDefaultLocale: true,
    },
  },
  integrations: [
    sitemap({
      // Kök adres yalnızca /en'e yönlendiriyor; sitemap'e girmemeli.
      filter: (page) => page !== "https://mac-utils.web.app/",
      // Her kaydın altına diğer dillerin `xhtml:link` karşılıkları
      // ekleniyor: sayfadaki hreflang ile aynı bilgi, arama motorunun
      // sayfayı hiç indirmeden görebileceği yerde.
      i18n: {
        defaultLocale: "en",
        locales: { en: "en", tr: "tr", ru: "ru" },
      },
    }),
  ],
  vite: { plugins: [tailwindcss()] },
});
