import type { Locale } from "./ui";

/**
 * Her sayfanın başlık ve açıklaması. Arama sonucunda görünen iki satır
 * bunlar; yayındaki sitede hiçbiri yoktu (tek bir genel başlık vardı),
 * bu yüzden sayfa başına elle yazıldı.
 *
 * Başlıklar ~60, açıklamalar ~155 karakterin altında tutuldu — Google
 * bu sınırların üstünü kırpıyor.
 */
export interface PageMeta {
  title: string;
  description: string;
}

type PageKey = "index" | "destek" | "gizlilik-politikasi";

export const meta: Record<Locale, Record<PageKey, PageMeta>> = {
  en: {
    index: {
      title: "GlassDo — A calmer command center for your Mac",
      description:
        "Tasks, notes, the Edge Rail panel and system status in one calm macOS app. Everything stays on your Mac — no account, no sync. Free for macOS 26.",
    },
    destek: {
      title: "Support — GlassDo",
      description:
        "Questions, bug reports and feature requests for GlassDo, the calm macOS command center. Get in touch and we will get back to you.",
    },
    "gizlilik-politikasi": {
      title: "Privacy Policy — GlassDo",
      description:
        "GlassDo keeps your tasks and notes on your own Mac. Read exactly what is stored, what is never collected, and what leaves your device.",
    },
  },
  tr: {
    index: {
      title: "GlassDo — Mac'in için daha sakin bir kontrol merkezi",
      description:
        "Görevler, notlar, Edge Rail paneli ve sistem durumu tek bir sakin macOS uygulamasında. Her şey Mac'inde kalır — hesap yok, senkron yok. macOS 26 için ücretsiz.",
    },
    destek: {
      title: "Destek — GlassDo",
      description:
        "GlassDo hakkında sorular, hata bildirimleri ve özellik istekleri. Bize yaz, en kısa sürede dönüş yapalım.",
    },
    "gizlilik-politikasi": {
      title: "Gizlilik Politikası — GlassDo",
      description:
        "GlassDo görevlerini ve notlarını kendi Mac'inde tutar. Nelerin saklandığını, nelerin hiç toplanmadığını ve cihazdan ne çıktığını buradan oku.",
    },
  },
  ru: {
    index: {
      title: "GlassDo — спокойный центр управления для Mac",
      description:
        "Задачи, заметки, панель Edge Rail и состояние системы в одном спокойном приложении для macOS. Всё остаётся на твоём Mac — без аккаунта и синхронизации.",
    },
    destek: {
      title: "Поддержка — GlassDo",
      description:
        "Вопросы, сообщения об ошибках и пожелания по GlassDo — спокойному центру управления для macOS. Напиши нам, мы ответим.",
    },
    "gizlilik-politikasi": {
      title: "Политика конфиденциальности — GlassDo",
      description:
        "GlassDo хранит задачи и заметки на твоём Mac. Здесь описано, что сохраняется, что никогда не собирается и что покидает устройство.",
    },
  },
};
