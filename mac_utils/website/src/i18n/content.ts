import en from "../content/en.json";
import tr from "../content/tr.json";
import ru from "../content/ru.json";
import type { Locale } from "./ui";

/**
 * Sayfa içeriği.
 *
 * Sitenin kaynağı kaybolmuştu; bu üç dosya, Firebase'e dağıtılmış
 * derlemenin içindeki sunucu yükünden (`out/<dil>.txt`) çıkarıldı.
 * Yani metinler yeniden çevrilmedi — kullanıcının yazdığı hâlleriyle
 * duruyor, üstelik eski HTML'de hiç basılmayan SSS cevapları da dahil.
 */
export type SiteContent = typeof en;

export const content: Record<Locale, SiteContent> = {
  en,
  tr: tr as unknown as SiteContent,
  ru: ru as unknown as SiteContent,
};
