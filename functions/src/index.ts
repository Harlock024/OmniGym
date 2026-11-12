import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

initializeApp();

type UserRole = "superuser" | "owner" | "staff" | "receptionist";
type UserStatus = "active" | "suspended" | "pending";

interface UserDoc {
  role: UserRole;
  tenant_id: string | null;
  branch_id: string | null;
  status: UserStatus;
}

interface CreateStaffRequest {
  name: string;
  email: string;
  role: "staff" | "receptionist";
  tenantId: string;
  branchId?: string | null;
}

// ─── Trigger: sincroniza custom claims cuando se escribe en /users/{uid} ─────

export const onUserWritten = onDocumentWritten(
  "users/{uid}",
  async (event) => {
    const uid = event.params.uid;
    const auth = getAuth();

    // Documento eliminado: limpiar claims para revocar permisos inmediatamente
    if (!event.data?.after.exists) {
      await auth.setCustomUserClaims(uid, {});
      logger.info("claims cleared for deleted user", { uid });
      return;
    }

    const data = event.data.after.data() as UserDoc;
    const { role, tenant_id, branch_id, status } = data;
    await auth.setCustomUserClaims(uid, status === "active" ? {
      role,
      tenant_id: tenant_id ?? null,
      branch_id: branch_id ?? null,
    } : {});

    logger.info("claims updated", { uid, role, tenant_id, branch_id });

    // Revocar refresh tokens al suspender para invalidar sesiones activas en < 1 min.
    // Sin esto, el JWT suspendido sigue siendo válido hasta su expiración (1 hora).
    if (status === "suspended") {
      await auth.revokeRefreshTokens(uid);
      logger.info("refresh tokens revoked for suspended user", { uid });
    }
  }
);

// ─── Callable: crea un operador en Auth + Firestore ──────────────────────────
// El cliente no puede crear usuarios de Auth — solo el Admin SDK puede hacerlo.

export const createStaffUser = onCall<CreateStaffRequest>(
  { enforceAppCheck: false },
  async (request) => {
    const caller = request.auth;
    if (!caller) throw new HttpsError("unauthenticated", "Login required.");

    const db = getFirestore();
    const callerProfile = (await db.collection("users").doc(caller.uid).get()).data();
    const { name, email, role, tenantId, branchId = null } = request.data;
    if (!["staff", "receptionist"].includes(role)) {
      throw new HttpsError("invalid-argument", "Only Staff or Receptionist can be invited.");
    }
    const managesTenant = callerProfile?.tenant_id === tenantId &&
      (callerProfile?.role === "owner" || (callerProfile?.role === "staff" && role === "receptionist"));
    if (callerProfile?.status !== "active" || !(callerProfile.role === "superuser" || managesTenant)) {
      throw new HttpsError("permission-denied", "Insufficient permissions.");
    }
    if (!branchId || !(await db.collection("tenants").doc(tenantId).collection("branches").doc(branchId).get()).exists) {
      throw new HttpsError("invalid-argument", "Select a branch belonging to this gym.");
    }
    // Keep this legacy callable as an adapter: all account creation and email
    // delivery must follow the same pending-invitation flow as the web app.
    const authorization = request.rawRequest.get("authorization");
    if (!authorization?.startsWith("Bearer ")) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    const response = await fetch(`${process.env.WORKER_BASE_URL ?? "https://omni-gym.hadith024.workers.dev"}/staff-accounts`, {
      method: "POST",
      headers: { Authorization: authorization, "Content-Type": "application/json" },
      body: JSON.stringify({ name, email, role, tenant_id: tenantId, branch_id: branchId }),
    });
    const result = await response.json() as { error?: string; uid?: string; username?: string; email_sent?: boolean };
    if (!response.ok) {
      throw new HttpsError(response.status === 409 ? "already-exists" : "failed-precondition", result.error ?? "Account creation failed.");
    }
    return result;
  }
);
