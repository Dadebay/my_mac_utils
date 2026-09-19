/**
 * Dil listesi, adresler ve içerik dosyalarında yeri olmayan birkaç
 * arayüz dizgisi. Sayfa metinlerinin tamamı `src/content/*.json` içinde.
 */
export const locales = ["en", "tr", "ru"] as const;
export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = "en";

/** `<html lang>` ve `hreflang` için dil etiketleri. */
export const htmlLang: Record<Locale, string> = { en: "en", tr: "tr", ru: "ru" };

export const localeName: Record<Locale, string> = { en: "EN", tr: "TR", ru: "RU" };

/** Dil seçicinin erişilebilirlik etiketi — içerikte karşılığı yok. */
export const ui = {
  en: { changeLanguage: "Change language" },
  tr: { changeLanguage: "Dili değiştir" },
  ru: { changeLanguage: "Сменить язык" },
} as const satisfies Record<Locale, unknown>;

/** Bölüm çapaları üç dilde de aynı — yayındaki adresler korunuyor. */
export const anchors = {
  features: "ozellikler",
  privacy: "gizlilik",
  faq: "sss",
  download: "indir",
} as const;

/** Dışarıya giden adresler tek yerde. */
export const repoUrl = "https://github.com/Dadebay/my_mac_utils";
export const releasesUrl = `${repoUrl}/releases`;
export const latestReleaseUrl = `${repoUrl}/releases/latest`;
export const issuesUrl = `${repoUrl}/issues`;
export const authorUrl = "https://github.com/Dadebay";
