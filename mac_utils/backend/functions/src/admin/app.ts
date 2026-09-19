import cookieParser from "cookie-parser";
import express from "express";
import { disablePromoCodeHandler, listPromoCodesHandler, makeCreatePromoCodeHandler, makeRevokeRedemptionHandler } from "./promoCodes.js";
import { getAdminDashboardHandler, getCustomerDetailHandler, listCustomersHandler } from "./dashboard.js";
import { logoutHandler, makeLoginHandler, resumeSessionHandler } from "./session.js";
import { requireAdminSession, requireCsrf, requireSameOrigin } from "./middleware.js";
import type { RevenueCatConfig } from "../lib/revenueCat.js";

export interface AdminAppSecrets {
  adminPanelPasswordHash: string;
  adminSessionSigningKey: string;
  promoCodePepper: string;
  allowedOrigin: string;
  revenueCat: RevenueCatConfig;
}

/**
 * Tek bir Express app, Hosting rewrite ile `/admin-api/**`e bağlanır —
 * bkz. `firebase.json`. Böylece admin panel ve API aynı origin'de yaşar,
 * üçüncü taraf cookie/CORS sorunu hiç oluşmaz.
 */
export function createAdminApp(secrets: AdminAppSecrets) {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "16kb" }));
  app.use(cookieParser());

  const sameOrigin = requireSameOrigin(secrets.allowedOrigin);
  const session = requireAdminSession(secrets.adminSessionSigningKey);

  // Login: parola kontrolü kendi rate-limit'ini taşıyor, session
  // gerektirmiyor (henüz session yok) ama yine same-origin zorunlu.
  app.post("/admin-api/session", sameOrigin, makeLoginHandler({
    passwordHash: secrets.adminPanelPasswordHash,
    sessionSigningKey: secrets.adminSessionSigningKey,
  }));
  app.delete("/admin-api/session", sameOrigin, session, requireCsrf, logoutHandler);
  // Sayfa yenilendiğinde csrf token'ı yeniden almak için — durum
  // değiştirmiyor (`GET`), bu yüzden CSRF denetimi gerekmiyor, yalnızca
  // geçerli bir oturum.
  app.get("/admin-api/session", session, resumeSessionHandler);

  app.get("/admin-api/dashboard", session, getAdminDashboardHandler);
  app.get("/admin-api/customers", session, listCustomersHandler);
  app.get("/admin-api/customers/:uid", session, getCustomerDetailHandler);

  app.get("/admin-api/promocodes", session, listPromoCodesHandler);
  app.post(
    "/admin-api/promocodes",
    sameOrigin,
    session,
    requireCsrf,
    makeCreatePromoCodeHandler({ pepper: secrets.promoCodePepper })
  );
  app.post("/admin-api/promocodes/:id/disable", sameOrigin, session, requireCsrf, disablePromoCodeHandler);
  app.post(
    "/admin-api/redemptions/:id/revoke",
    sameOrigin,
    session,
    requireCsrf,
    makeRevokeRedemptionHandler({ revenueCat: secrets.revenueCat })
  );

  return app;
}
