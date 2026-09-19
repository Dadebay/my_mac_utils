import { verify as argon2Verify } from "@node-rs/argon2";
import type { Response } from "express";
import { SESSION_COOKIE_NAME, createSessionToken } from "../lib/adminSession.js";
import { checkRateLimit } from "../lib/rateLimit.js";
import type { AdminRequest } from "./middleware.js";

const LOGIN_MAX_ATTEMPTS = 5;
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const SESSION_TTL_SECONDS = 8 * 60 * 60;

export function makeLoginHandler(deps: { passwordHash: string; sessionSigningKey: string }) {
  return async (req: AdminRequest, res: Response) => {
    const ip = req.ip ?? "unknown";
    const rateLimit = await checkRateLimit({
      key: `admin-login:${ip}`,
      maxAttempts: LOGIN_MAX_ATTEMPTS,
      windowMs: LOGIN_WINDOW_MS,
    });
    if (!rateLimit.allowed) {
      res.status(429).json({ error: "too_many_attempts" });
      return;
    }

    const password = typeof req.body?.password === "string" ? req.body.password : "";
    if (!password) {
      res.status(400).json({ error: "missing_password" });
      return;
    }

    // Başarı/başarısızlıkta parolayı, hash'i ya da doğrulama ayrıntısını
    // hiçbir zaman loglama — yalnızca genel bir true/false.
    const isValid = await argon2Verify(deps.passwordHash, password).catch(() => false);
    if (!isValid) {
      res.status(401).json({ error: "invalid_password" });
      return;
    }

    const { token, csrfToken } = createSessionToken(deps.sessionSigningKey);
    res.cookie(SESSION_COOKIE_NAME, token, {
      httpOnly: true,
      secure: true,
      sameSite: "strict",
      path: "/",
      maxAge: SESSION_TTL_SECONDS * 1000,
    });
    res.status(200).json({ csrfToken });
  };
}

export function logoutHandler(_req: AdminRequest, res: Response) {
  res.clearCookie(SESSION_COOKIE_NAME, { path: "/" });
  res.status(200).json({ ok: true });
}

/**
 * Sayfa yenilendiğinde (F5) istemcinin JS belleğindeki csrf token kaybolur
 * ama `HttpOnly` çerez hâlâ geçerli olabilir — JS o çerezi okuyamadığı için
 * tekrar parola istemek yerine, geçerli bir oturumu olan istemcinin csrf
 * token'ını buradan yeniden alması sağlanıyor. `requireAdminSession`
 * zaten `req.adminCsrfToken`'ı doğrulayıp iliştirdi.
 */
export function resumeSessionHandler(req: AdminRequest, res: Response) {
  res.status(200).json({ csrfToken: req.adminCsrfToken });
}
