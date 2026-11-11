import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

initializeApp();

type UserRole = "superuser" | "owner" | "staff" | "receptionist";
type UserStatus = "active" | "suspended";

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

    await auth.setCustomUserClaims(uid, {
      role,
      tenant_id: tenant_id ?? null,
      branch_id: branch_id ?? null,
    });

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
    const auth = getAuth();
    const permissions = Object.fromEntries(
      ["dashboard", "branches", "members", "scanner", "memberships", "billing", "reports"]
        .map(module => [module, role === "staff" && ["dashboard", "scanner"].includes(module)])
    );

    // Crear usuario en Firebase Auth — el email link para establecer contraseña
    // lo envía Firebase Auth automáticamente con sendEmailVerification si se
    // configura la plantilla en la consola. Aquí usamos contraseña temporal aleatoria.
    const tempPassword = Math.random().toString(36).slice(-12) + "A1!";
    const userRecord = await auth.createUser({ email, displayName: name, password: tempPassword });

    await db.collection("users").doc(userRecord.uid).set({
      name,
      email,
      role,
      permissions,
      tenant_id: tenantId,
      branch_id: branchId,
      status: "active",
      created_at: new Date(),
    });

    // El trigger onUserWritten asigna los claims automáticamente

    // Enviar email para que el usuario establezca su contraseña
    const resetLink = await auth.generatePasswordResetLink(email);
    logger.info("staff user created", { uid: userRecord.uid, role, tenantId, resetLink });

    return { uid: userRecord.uid };
  }
);
