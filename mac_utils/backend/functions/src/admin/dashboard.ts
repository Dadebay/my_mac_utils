import type { Request, Response } from "express";
import { Timestamp } from "firebase-admin/firestore";
import { db } from "../lib/firebaseAdmin.js";

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

/** Kabaca ama hızlı: koleksiyon toplamları için `count()` aggregation
 *  sorgusu kullanılıyor — tüm dokümanları çekmeden sayım. */
export async function getAdminDashboardHandler(_req: Request, res: Response) {
  const now = Date.now();
  const since7d = Timestamp.fromMillis(now - SEVEN_DAYS_MS);
  const since30d = Timestamp.fromMillis(now - THIRTY_DAYS_MS);

  const [
    totalProCount,
    storeProCount,
    promoProCount,
    redemptions7d,
    redemptions30d,
    lastWebhookEvent,
  ] = await Promise.all([
    db.collection("customerSummaries").where("accessSource", "in", ["store", "promo", "mixed"]).count().get(),
    db.collection("customerSummaries").where("accessSource", "==", "store").count().get(),
    db.collection("customerSummaries").where("accessSource", "==", "promo").count().get(),
    db.collection("redemptions").where("status", "==", "granted").where("redeemedAt", ">=", since7d).count().get(),
    db.collection("redemptions").where("status", "==", "granted").where("redeemedAt", ">=", since30d).count().get(),
    db.collection("revenueCatEvents").orderBy("receivedAt", "desc").limit(1).get(),
  ]);

  const lastEvent = lastWebhookEvent.docs[0]?.data();

  res.status(200).json({
    totalProUsers: totalProCount.data().count,
    storeProUsers: storeProCount.data().count,
    promoProUsers: promoProCount.data().count,
    redemptionsLast7Days: redemptions7d.data().count,
    redemptionsLast30Days: redemptions30d.data().count,
    lastWebhookReceivedAt: lastEvent?.receivedAt?.toMillis?.() ?? null,
    lastWebhookEnvironment: lastEvent?.environment ?? null,
  });
}

export async function listCustomersHandler(req: Request, res: Response) {
  const cursor = typeof req.query.cursor === "string" ? req.query.cursor : undefined;
  const pageSize = Math.min(Number(req.query.limit) || 25, 100);

  let query = db.collection("customerSummaries").orderBy("lastEventAt", "desc").limit(pageSize);
  if (cursor) {
    const cursorDoc = await db.collection("customerSummaries").doc(cursor).get();
    if (cursorDoc.exists) query = query.startAfter(cursorDoc);
  }

  const snapshot = await query.get();
  const items = snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      uid: doc.id,
      email: data.email ?? null,
      displayName: data.displayName ?? null,
      activeEntitlements: data.activeEntitlements ?? [],
      accessSource: data.accessSource ?? "none",
      productID: data.productID ?? null,
      store: data.store ?? null,
      firstPurchaseAt: data.firstPurchaseAt?.toMillis?.() ?? null,
      lastEventAt: data.lastEventAt?.toMillis?.() ?? null,
      environment: data.environment ?? null,
    };
  });

  res.status(200).json({
    items,
    nextCursor: snapshot.docs.length === pageSize ? snapshot.docs[snapshot.docs.length - 1]?.id : null,
  });
}

export async function getCustomerDetailHandler(req: Request, res: Response) {
  const uid = req.params.uid;
  if (!uid) {
    res.status(400).json({ error: "missing_uid" });
    return;
  }

  const [summarySnap, redemptionsSnap] = await Promise.all([
    db.collection("customerSummaries").doc(uid).get(),
    db.collection("redemptions").where("uid", "==", uid).orderBy("redeemedAt", "desc").limit(20).get(),
  ]);

  if (!summarySnap.exists) {
    res.status(404).json({ error: "not_found" });
    return;
  }

  const summary = summarySnap.data()!;
  const redemptions = redemptionsSnap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      promoPrefix: data.promoPrefix,
      redeemedAt: data.redeemedAt?.toMillis?.() ?? null,
      grantKind: data.grantKind,
      grantExpiresAt: data.grantExpiresAt?.toMillis?.() ?? null,
      status: data.status,
    };
  });

  res.status(200).json({
    uid,
    email: summary.email ?? null,
    displayName: summary.displayName ?? null,
    revenueCatCustomerID: summary.revenueCatCustomerID,
    activeEntitlements: summary.activeEntitlements ?? [],
    accessSource: summary.accessSource ?? "none",
    productID: summary.productID ?? null,
    store: summary.store ?? null,
    firstPurchaseAt: summary.firstPurchaseAt?.toMillis?.() ?? null,
    lastEventAt: summary.lastEventAt?.toMillis?.() ?? null,
    environment: summary.environment ?? null,
    redemptions,
  });
}
