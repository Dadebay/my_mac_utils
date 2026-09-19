import { FieldValue, Timestamp } from "firebase-admin/firestore";
import type { Request, Response } from "express";
import { db } from "../lib/firebaseAdmin.js";
import { generatePromoCode, hashPromoCode, promoCodePrefix } from "../lib/promoCode.js";
import { writeAdminAuditLog } from "../lib/auditLog.js";
import { revokePromotionalEntitlement, type RevenueCatConfig } from "../lib/revenueCat.js";

const ENTITLEMENT_ID = "pro";

interface CreatePromoBody {
  label: string;
  maxRedemptions: number;
  grantKind: "lifetime" | "untilDate";
  grantExpiresAtMs?: number | null;
  codeExpiresAtMs?: number | null;
}

export function makeCreatePromoCodeHandler(deps: { pepper: string }) {
  return async (req: Request, res: Response) => {
    const body = req.body as Partial<CreatePromoBody>;

    const label = typeof body.label === "string" ? body.label.trim().slice(0, 200) : "";
    const maxRedemptions = Number(body.maxRedemptions);
    const grantKind = body.grantKind === "lifetime" || body.grantKind === "untilDate" ? body.grantKind : null;

    if (!label || !grantKind || !Number.isInteger(maxRedemptions) || maxRedemptions < 1 || maxRedemptions > 10_000) {
      res.status(400).json({ error: "invalid_input" });
      return;
    }
    if (grantKind === "untilDate" && !body.grantExpiresAtMs) {
      res.status(400).json({ error: "missing_grant_expiry" });
      return;
    }

    const rawCode = generatePromoCode();
    const normalized = rawCode; // generatePromoCode zaten normalize biçimde üretiyor
    const codeHash = hashPromoCode(deps.pepper, normalized);

    const docRef = db.collection("promoCodes").doc();
    await docRef.set({
      codeHash,
      prefix: promoCodePrefix(rawCode),
      label,
      entitlementID: ENTITLEMENT_ID,
      grantKind,
      grantExpiresAt: body.grantExpiresAtMs ? Timestamp.fromMillis(body.grantExpiresAtMs) : null,
      expiresAt: body.codeExpiresAtMs ? Timestamp.fromMillis(body.codeExpiresAtMs) : null,
      maxRedemptions,
      redemptionCount: 0,
      status: "active",
      createdAt: FieldValue.serverTimestamp(),
      createdByUID: "owner",
      disabledAt: null,
    });

    await writeAdminAuditLog({ action: "promoCode.create", targetId: docRef.id, metadata: { label } });

    // Düz kod yalnızca bu cevapta, bir kez gösterilir.
    res.status(201).json({ id: docRef.id, code: rawCode });
  };
}

export async function listPromoCodesHandler(req: Request, res: Response) {
  const status = typeof req.query.status === "string" ? req.query.status : undefined;
  const cursor = typeof req.query.cursor === "string" ? req.query.cursor : undefined;
  const pageSize = Math.min(Number(req.query.limit) || 25, 100);

  let query = db.collection("promoCodes").orderBy("createdAt", "desc").limit(pageSize);
  if (status) query = query.where("status", "==", status);
  if (cursor) {
    const cursorDoc = await db.collection("promoCodes").doc(cursor).get();
    if (cursorDoc.exists) query = query.startAfter(cursorDoc);
  }

  const snapshot = await query.get();
  const items = snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      prefix: data.prefix,
      label: data.label,
      status: data.status,
      redemptionCount: data.redemptionCount,
      maxRedemptions: data.maxRedemptions,
      grantKind: data.grantKind,
      expiresAt: data.expiresAt?.toMillis?.() ?? null,
      createdAt: data.createdAt?.toMillis?.() ?? null,
      createdByUID: data.createdByUID,
    };
  });

  res.status(200).json({
    items,
    nextCursor: snapshot.docs.length === pageSize ? snapshot.docs[snapshot.docs.length - 1]?.id : null,
  });
}

export async function disablePromoCodeHandler(req: Request, res: Response) {
  const promoId = req.params.id;
  if (!promoId) {
    res.status(400).json({ error: "missing_id" });
    return;
  }

  const ref = db.collection("promoCodes").doc(promoId);
  const snap = await ref.get();
  if (!snap.exists) {
    res.status(404).json({ error: "not_found" });
    return;
  }

  await ref.update({ status: "disabled", disabledAt: FieldValue.serverTimestamp() });
  await writeAdminAuditLog({ action: "promoCode.disable", targetId: promoId });

  res.status(200).json({ ok: true });
}

/**
 * Bir promo koduna değil, tek bir redemption'a (kullanıcının aldığı
 * promotional entitlement'a) uygulanır. Kullanıcının App Store/Web'den
 * yaptığı gerçek satın almaya asla dokunmaz — yalnızca RevenueCat'teki
 * promotional grant'i geri alır.
 */
export function makeRevokeRedemptionHandler(deps: { revenueCat: RevenueCatConfig }) {
  return async (req: Request, res: Response) => {
    const redemptionId = req.params.id;
    if (!redemptionId) {
      res.status(400).json({ error: "missing_id" });
      return;
    }

    const ref = db.collection("redemptions").doc(redemptionId);
    const snap = await ref.get();
    if (!snap.exists) {
      res.status(404).json({ error: "not_found" });
      return;
    }

    const data = snap.data();
    if (!data) {
      res.status(404).json({ error: "not_found" });
      return;
    }
    if (data.status !== "granted") {
      res.status(409).json({ error: "not_revocable", status: data.status });
      return;
    }

    try {
      await revokePromotionalEntitlement(deps.revenueCat, {
        appUserId: data.revenueCatCustomerID as string,
        entitlementId: ENTITLEMENT_ID,
      });
    } catch (error) {
      res.status(502).json({ error: "revenuecat_error", detail: (error as Error).message });
      return;
    }

    await ref.update({
      status: "revoked",
      revokedAt: FieldValue.serverTimestamp(),
      revokedByUID: "owner",
    });
    await writeAdminAuditLog({ action: "redemption.revoke", targetId: redemptionId });

    res.status(200).json({ ok: true });
  };
}
