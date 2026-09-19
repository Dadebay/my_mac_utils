import type { Request, Response } from "express";
import { Timestamp } from "firebase-admin/firestore";
import { db } from "../lib/firebaseAdmin.js";
import { constantTimeEqual } from "../lib/crypto.js";
import { getCustomer, type RevenueCatConfig } from "../lib/revenueCat.js";
import { upsertCustomerSummary } from "../lib/customerSummary.js";

/**
 * ⚠️ DEPLOY ÖNCESİ DOĞRULA (bkz. `revenueCat.ts` başındaki aynı uyarı):
 * RevenueCat'in webhook doğrulaması resmi dokümana göre bir HMAC imzası
 * değil, dashboard'da webhook kurulurken girilen sabit bir metnin
 * `Authorization` header'ında geri gönderilip birebir karşılaştırılması
 * şeklinde çalışır (bkz.
 * https://www.revenuecat.com/docs/integrations/webhooks). Bu yüzden burada
 * `PROMO_CODE_PEPPER` gibi bir HMAC hesaplamıyoruz — gelen `Authorization`
 * header'ı, dashboard'a girilenle aynı olan `REVENUECAT_WEBHOOK_SIGNING_SECRET`
 * ile sabit-zamanlı karşılaştırılıyor. Deploy'dan önce güncel dokümanla
 * teyit et; RevenueCat gerçek bir HMAC imza şeması sunuyorsa burası ona
 * göre güncellenmeli.
 *
 * Bu yüzden `express.json()`'ın ham gövdeyi tükettiği sorunu burada hiç
 * yaşanmıyor — imza kontrolü header üzerinden, gövde üzerinden değil.
 * Yine de bu route admin Express app'inin İÇİNE konmuyor: bağımsız bir
 * `onRequest` olarak kalması, admin app'in `same-origin`/session/CSRF
 * middleware zincirinin bu genel-erişimli endpoint'e hiç uygulanmamasını
 * garantiliyor.
 */
const STORE_PURCHASE_EVENT_TYPES = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "NON_RENEWING_PURCHASE",
  "PRODUCT_CHANGE",
]);

interface RevenueCatWebhookEvent {
  id: string;
  type: string;
  app_user_id: string;
  product_id?: string | null;
  store?: string | null;
  environment?: string | null;
  purchased_at_ms?: number | null;
  event_timestamp_ms?: number | null;
  entitlement_ids?: string[] | null;
}

export function makeRevenueCatWebhookHandler(deps: { signingSecret: string; revenueCat: RevenueCatConfig }) {
  return async (req: Request, res: Response): Promise<void> => {
    if (req.method !== "POST") {
      res.status(405).end();
      return;
    }

    const authorization = req.get("Authorization") ?? "";
    if (!constantTimeEqual(authorization, `Bearer ${deps.signingSecret}`)) {
      // İmza geçersizse hiçbir Firestore yazısı yapılmadan reddedilir.
      res.status(401).json({ error: "invalid_signature" });
      return;
    }

    const payload = req.body as { event?: RevenueCatWebhookEvent } | undefined;
    const event = payload?.event;
    if (!event?.id || !event.app_user_id || !event.type) {
      res.status(400).json({ error: "invalid_payload" });
      return;
    }

    const eventRef = db.collection("revenueCatEvents").doc(event.id);
    const alreadyProcessed = (await eventRef.get()).exists;
    if (alreadyProcessed) {
      // Idempotency: aynı event tekrar gelirse 200 dön, tekrar işleme.
      res.status(200).json({ ok: true, duplicate: true });
      return;
    }

    // RevenueCat `app_user_id`, macOS tarafında `Purchases.logIn(auth.uid)`
    // ile ayarlandığı için Firebase uid'yle birebir aynı (plandaki kimlik
    // kararı).
    const uid = event.app_user_id;
    const eventAt = event.event_timestamp_ms ? new Date(event.event_timestamp_ms) : new Date();

    let customer;
    try {
      // Tek bir event payload'ından nihai erişim durumunu tahmin etmek
      // yerine güncel müşteri durumu doğrudan RevenueCat'ten çekiliyor
      // (plan gereksinimi).
      customer = await getCustomer(deps.revenueCat, uid);
    } catch {
      // RevenueCat'e ulaşılamıyorsa event'i "işlendi" diye işaretlemeden
      // 5xx dön — RevenueCat'in kendi retry mekanizması tekrar dener.
      res.status(502).json({ error: "revenuecat_unreachable" });
      return;
    }

    await Promise.all([
      eventRef.set({
        eventID: event.id,
        type: event.type,
        uid,
        appUserID: event.app_user_id,
        productID: event.product_id ?? null,
        entitlementIDs: event.entitlement_ids ?? [],
        eventTimestamp: Timestamp.fromDate(eventAt),
        environment: event.environment ?? null,
        receivedAt: Timestamp.now(),
      }),
      upsertCustomerSummary({
        uid,
        customer,
        eventAt,
        sawStorePurchaseEvent: STORE_PURCHASE_EVENT_TYPES.has(event.type),
        productID: event.product_id ?? null,
        store: event.store ?? null,
        environment: event.environment ?? null,
        firstPurchaseAt:
          event.type === "INITIAL_PURCHASE" && event.purchased_at_ms
            ? new Date(event.purchased_at_ms)
            : undefined,
      }),
    ]);

    res.status(200).json({ ok: true });
  };
}
