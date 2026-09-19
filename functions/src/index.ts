import { onCall, onRequest } from "firebase-functions/v2/https";
import type { Request, Response } from "express";
import {
  REGION,
  revenueCatSecretApiKey,
  revenueCatProjectId,
  revenueCatWebhookSigningSecret,
  promoCodePepper,
  adminPanelPasswordHash,
  adminSessionSigningKey,
  adminAllowedOrigin,
} from "./lib/env.js";
import { createAdminApp, type AdminAppSecrets } from "./admin/app.js";
import { makeRedeemPromoCodeHandler } from "./callable/redeemPromoCode.js";
import { makeRevenueCatWebhookHandler } from "./webhooks/revenueCat.js";

/**
 * `firebase-functions/params` secret'ları (`.value()`) yalnızca bir
 * fonksiyon **çağrısı işlenirken** gerçek değeri döndürür — modül ilk
 * yüklenirken (soğuk başlangıçta, herhangi bir `export const ... = onX(...)`
 * çağrısının kendi gövdesi dışında) okunursa boş/placeholder gelir. Bu
 * yüzden aşağıdaki üç export'ta `.value()` çağrıları hep `onCall`/`onRequest`'e
 * verilen handler'ın İÇİNDE, istek geldiğinde çalışıyor — asla üst seviyede,
 * `export const` satırının kendisinde değil.
 */

let cachedAdminApp: ReturnType<typeof createAdminApp> | undefined;

function readAdminSecrets(): AdminAppSecrets {
  return {
    adminPanelPasswordHash: adminPanelPasswordHash.value(),
    adminSessionSigningKey: adminSessionSigningKey.value(),
    promoCodePepper: promoCodePepper.value(),
    allowedOrigin: adminAllowedOrigin.value(),
    revenueCat: { secretApiKey: revenueCatSecretApiKey.value(), projectId: revenueCatProjectId.value() },
  };
}

export const adminApi = onRequest(
  {
    region: REGION,
    secrets: [adminPanelPasswordHash, adminSessionSigningKey, promoCodePepper, revenueCatSecretApiKey, revenueCatProjectId],
  },
  (req: Request, res: Response) => {
    // Express app'i yalnızca bir kez (konteynerin ilk isteğinde) kuruluyor;
    // secret'lar o an hazır olduğu için güvenli, sonraki sıcak
    // çağrılarda tekrar route kaydı yapılmıyor.
    cachedAdminApp ??= createAdminApp(readAdminSecrets());
    cachedAdminApp(req, res);
  }
);

export const redeemPromoCode = onCall(
  { region: REGION, secrets: [promoCodePepper, revenueCatSecretApiKey, revenueCatProjectId] },
  (request) =>
    makeRedeemPromoCodeHandler({
      pepper: promoCodePepper.value(),
      revenueCat: { secretApiKey: revenueCatSecretApiKey.value(), projectId: revenueCatProjectId.value() },
    })(request)
);

export const revenueCatWebhook = onRequest(
  {
    region: REGION,
    secrets: [revenueCatWebhookSigningSecret, revenueCatSecretApiKey, revenueCatProjectId],
  },
  (req: Request, res: Response) =>
    makeRevenueCatWebhookHandler({
      signingSecret: revenueCatWebhookSigningSecret.value(),
      revenueCat: { secretApiKey: revenueCatSecretApiKey.value(), projectId: revenueCatProjectId.value() },
    })(req, res)
);
