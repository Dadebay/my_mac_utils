import type { NextFunction, Request, Response } from "express";
import { SESSION_COOKIE_NAME, verifySessionToken } from "../lib/adminSession.js";
import { constantTimeEqual } from "../lib/crypto.js";

export interface AdminRequest extends Request {
  adminCsrfToken?: string;
}

/**
 * Tüm `/admin-api/*` rotalarına (login hariç) uygulanır. Cookie'nin
 * imzasını ve süresini doğrular; geçersizse 401. Bulduğu `csrf` claim'ini
 * sonraki middleware'in (requireCsrf) kullanabilmesi için isteğe iliştirir.
 */
export function requireAdminSession(signingKey: string) {
  return (req: AdminRequest, res: Response, next: NextFunction) => {
    const token = req.cookies?.[SESSION_COOKIE_NAME] as string | undefined;
    const payload = verifySessionToken(signingKey, token);
    if (!payload) {
      res.status(401).json({ error: "unauthorized" });
      return;
    }
    req.adminCsrfToken = payload.csrf;
    next();
  };
}

/**
 * Yalnızca durum değiştiren isteklerde (`POST`/`DELETE`) kullanılır.
 * Cookie'deki imzalı `csrf` claim'i, istemcinin ayrı bir header'da
 * (`X-CSRF-Token`) gönderdiği değerle eşleşmeli — tarayıcı otomatik
 * eklenen cookie'yi tek başına gönderemez, header'ı yalnızca aynı
 * origin'deki gerçek sayfa JS'i ekleyebilir.
 */
export function requireCsrf(req: AdminRequest, res: Response, next: NextFunction) {
  const header = req.get("X-CSRF-Token");
  if (!req.adminCsrfToken || !header || !constantTimeEqual(header, req.adminCsrfToken)) {
    res.status(403).json({ error: "csrf_mismatch" });
    return;
  }
  next();
}

/**
 * Hosting rewrite sayesinde admin panel ve Functions aynı origin'de
 * yaşıyor — bu yüzden state değiştiren isteklerde `Origin`in bu origin'le
 * eşleşmesi ekstra bir CSRF katmanı. Doğrudan Functions URL'sine (Hosting
 * dışından) gelen isteklerde `Origin` genelde hiç ayarlanmaz ya da farklı
 * olur; ikisinde de reddediyoruz.
 */
export function requireSameOrigin(expectedOrigin: string) {
  return (req: Request, res: Response, next: NextFunction) => {
    const origin = req.get("Origin");
    if (origin !== expectedOrigin) {
      res.status(403).json({ error: "origin_mismatch" });
      return;
    }
    next();
  };
}
