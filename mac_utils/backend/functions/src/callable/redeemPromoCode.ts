import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db } from "../lib/firebaseAdmin.js";
import { checkRateLimit } from "../lib/rateLimit.js";
import { hashPromoCode, normalizePromoCode } from "../lib/promoCode.js";
import { grantPromotionalEntitlement, getCustomer, type RevenueCatConfig } from "../lib/revenueCat.js";
import { upsertCustomerSummary } from "../lib/customerSummary.js";

const ENTITLEMENT_ID = "pro";
const RATE_LIMIT_MAX_ATTEMPTS = 10;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;

interface RedeemInput {
  code?: unknown;
}

interface RedeemResult {
  success: true;
  /** macOS tarafı bunu görürse "kod zaten kullanılmıştı, Pro zaten açık"
   *  diye ayrı bir metin gösterebilir — plan md'sindeki idempotency
   *  gereksinimi (yeniden grant üretmeden önceki başarı dönsün). */
  alreadyRedeemed: boolean;
}

type TxOutcome =
  | { kind: "alreadyGranted" }
  | { kind: "reserved"; grantKind: "lifetime" | "untilDate"; grantExpiresAtMs: number | null };

/**
 * `POST` gövdesi yalnız `{ code }`. `request.auth` zorunlu — imzasız
 * çağrı reddedilir.
 *
 * Tek seferlik kullanım, sorgu-sonra-karar yerine **deterministik doküman
 * id**'siyle sağlanıyor: `redemptions/{uid}_{promoId}`. Aynı kullanıcı aynı
 * kodu eşzamanlı iki kez gönderse bile ikinci transaction'ın `tx.create()`'i
 * ilkiyle çakışıp Firestore'un kendi optimistic-concurrency mekanizmasıyla
 * başarısız olur — sorgu tabanlı "var mı" kontrolüne göre yarış koşullarına
 * çok daha dayanıklı.
 *
 * RevenueCat'e giden gerçek HTTP çağrısı transaction'ın **dışında**: Firestore
 * transaction'ları çakışma olursa callback'i sessizce yeniden çalıştırabilir,
 * içeride bir dış API çağrısı olsaydı aynı kullanıcıya iki kez grant
 * verilebilirdi. Bunun yerine transaction yalnızca atomik "rezervasyon"
 * yapıyor; RevenueCat çağrısı başarısız olursa rezervasyon ayrı bir
 * transaction'la geri alınıyor (kullanım hakkı boşa harcanmasın diye).
 */
export function makeRedeemPromoCodeHandler(deps: { pepper: string; revenueCat: RevenueCatConfig }) {
  return async (request: CallableRequest<RedeemInput>): Promise<RedeemResult> => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "sign_in_required");

    const rawCode = request.data?.code;
    if (typeof rawCode !== "string" || !rawCode.trim()) {
      throw new HttpsError("invalid-argument", "missing_code");
    }

    const rateLimit = await checkRateLimit({
      key: `redeem:${uid}`,
      maxAttempts: RATE_LIMIT_MAX_ATTEMPTS,
      windowMs: RATE_LIMIT_WINDOW_MS,
    });
    if (!rateLimit.allowed) {
      throw new HttpsError("resource-exhausted", "rate_limited");
    }

    // Ham kod hiçbir yere loglanmıyor — yalnızca normalize + hash.
    const normalized = normalizePromoCode(rawCode);
    const codeHash = hashPromoCode(deps.pepper, normalized);

    const promoQuery = await db.collection("promoCodes").where("codeHash", "==", codeHash).limit(1).get();
    const promoDoc = promoQuery.docs[0];
    if (!promoDoc) {
      throw new HttpsError("not-found", "invalid_code");
    }
    const promoId = promoDoc.id;
    const promoRef = promoDoc.ref;
    const redemptionRef = db.collection("redemptions").doc(`${uid}_${promoId}`);

    const outcome = await db.runTransaction<TxOutcome>(async (tx) => {
      const [promoSnap, redemptionSnap] = await Promise.all([tx.get(promoRef), tx.get(redemptionRef)]);
      const promo = promoSnap.data();
      if (!promo) throw new HttpsError("not-found", "invalid_code");

      const existing = redemptionSnap.data();
      if (existing?.status === "granted") {
        return { kind: "alreadyGranted" };
      }

      if (promo.status !== "active") {
        throw new HttpsError(
          "failed-precondition",
          promo.status === "expired" ? "code_expired" : promo.status === "exhausted" ? "code_exhausted" : "code_disabled"
        );
      }
      const expiresAt = promo.expiresAt as Timestamp | null;
      if (expiresAt && expiresAt.toMillis() <= Date.now()) {
        throw new HttpsError("failed-precondition", "code_expired");
      }

      if (existing?.status === "reserving") {
        // Aynı redemption dokümanı hâlâ "reserving"de — ya eşzamanlı bir
        // istek ya da RevenueCat çağrısı sırasında kesilmiş önceki bir
        // deneme. Burada üstüne yazmak iki eşzamanlı grant'e yol açabilir;
        // güvenlisi kullanıcıya kısa süre sonra tekrar denetmesini söylemek.
        throw new HttpsError("aborted", "redeem_in_progress");
      }

      const maxRedemptions = promo.maxRedemptions as number;
      const redemptionCount = (promo.redemptionCount as number) ?? 0;
      // Yeni bir slot yalnızca daha önce hiç redemption yoksa tüketiliyor;
      // önceki deneme "failed" ise aynı slot (zaten sayılmış) yeniden
      // kullanılıyor, sayaç ikinci kez artmıyor.
      if (!existing && redemptionCount >= maxRedemptions) {
        throw new HttpsError("resource-exhausted", "code_exhausted");
      }

      const grantKind = promo.grantKind as "lifetime" | "untilDate";
      const grantExpiresAt = (promo.grantExpiresAt as Timestamp | null) ?? null;

      const redemptionData = {
        promoId,
        promoPrefix: promo.prefix as string,
        uid,
        revenueCatCustomerID: uid,
        redeemedAt: FieldValue.serverTimestamp(),
        grantKind,
        grantExpiresAt,
        status: "reserving",
        revenueCatGrantReference: null,
        revokedAt: null,
        revokedByUID: null,
      };

      if (existing) {
        tx.update(redemptionRef, redemptionData);
      } else {
        tx.create(redemptionRef, redemptionData);
        const newCount = redemptionCount + 1;
        tx.update(promoRef, {
          redemptionCount: FieldValue.increment(1),
          status: newCount >= maxRedemptions ? "exhausted" : "active",
        });
      }

      return { kind: "reserved", grantKind, grantExpiresAtMs: grantExpiresAt ? grantExpiresAt.toMillis() : null };
    });

    if (outcome.kind === "alreadyGranted") {
      return { success: true, alreadyRedeemed: true };
    }

    try {
      const { revenueCatGrantReference } = await grantPromotionalEntitlement(deps.revenueCat, {
        appUserId: uid,
        entitlementId: ENTITLEMENT_ID,
        grantKind: outcome.grantKind,
        expiresAtMs: outcome.grantExpiresAtMs,
      });

      await redemptionRef.update({ status: "granted", revenueCatGrantReference });

      // Özet güncellemesi en iyi çaba: RevenueCat'ten okunamazsa bile
      // grant zaten verildi, kullanıcıyı hataya düşürmenin anlamı yok —
      // webhook zaten aynı özeti bir sonraki olayda tazeleyecek.
      const customer = await getCustomer(deps.revenueCat, uid).catch(() => null);
      if (customer) {
        await upsertCustomerSummary({ uid, customer, eventAt: new Date() });
      }

      return { success: true, alreadyRedeemed: false };
    } catch {
      // Rezervasyonu geri al — hem redemption'ı "failed" yap hem promo
      // sayacını düşür (plan madde 6: kullanım hakkı boşa harcanmasın).
      // Bir sonraki deneme bu redemption dokümanını "failed" bulup
      // üstüne yeniden rezervasyon yapabilir.
      await db.runTransaction(async (tx) => {
        tx.update(redemptionRef, { status: "failed" });
        tx.update(promoRef, { redemptionCount: FieldValue.increment(-1), status: "active" });
      });
      throw new HttpsError("unavailable", "revenuecat_error");
    }
  };
}
