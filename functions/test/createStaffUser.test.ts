jest.mock("firebase-admin/app", () => ({ initializeApp: jest.fn() }));
const mockFetch = jest.fn();
const originalFetch = global.fetch;
let callerProfile = { role: "owner", tenant_id: "gym", status: "active" };
jest.mock("firebase-admin/auth", () => ({ getAuth: jest.fn() }));
jest.mock("firebase-admin/firestore", () => ({
  getFirestore: () => ({
    collection: (name: string) => {
      if (name === "users") {
        return { doc: () => ({ get: async () => ({ data: () => callerProfile }) }) };
      }
      return { doc: () => ({ collection: () => ({ doc: () => ({ get: async () => ({ exists: true }) }) }) }) };
    },
  }),
}));
jest.mock("firebase-functions/v2/firestore", () => ({ onDocumentWritten: jest.fn() }));
jest.mock("firebase-functions/v2/https", () => ({
  onCall: (_: unknown, handler: unknown) => handler,
  HttpsError: class extends Error { constructor(public code: string, message: string) { super(message); } },
}));
jest.mock("firebase-functions/v2", () => ({ logger: { info: jest.fn() } }));

import { createStaffUser } from "../src/index";
const handler = createStaffUser as unknown as (request: object) => Promise<object>;
const request = (role: string) => ({ auth: { uid: "caller", token: { role: "owner", tenant_id: "gym" } },
  rawRequest: { get: () => "Bearer caller-id-token" },
  data: { role, tenantId: "gym", branchId: "b", name: "Test", email: "test@example.test" } });

beforeEach(() => {
  callerProfile = { role: "owner", tenant_id: "gym", status: "active" };
  mockFetch.mockReset().mockResolvedValue({ ok: true, json: async () => ({ uid: "work-user", username: "gym.test.123", email_sent: true }) });
  global.fetch = mockFetch;
});
afterAll(() => { global.fetch = originalFetch; });
test("legacy callable delegates to the pending-account Worker flow without exposing activation links", async () => {
  const result = await handler(request("receptionist"));
  expect(mockFetch).toHaveBeenCalledWith(expect.stringContaining("/staff-accounts"), expect.objectContaining({
    headers: { Authorization: "Bearer caller-id-token", "Content-Type": "application/json" },
    body: JSON.stringify({ name: "Test", email: "test@example.test", role: "receptionist", tenant_id: "gym", branch_id: "b" }),
  }));
  expect(result).toEqual({ uid: "work-user", username: "gym.test.123", email_sent: true });
});
test("Owner cannot invite another Owner", async () => {
  await expect(handler(request("owner"))).rejects.toMatchObject({ code: "invalid-argument" });
  expect(mockFetch).not.toHaveBeenCalled();
});
test("Staff can invite receptionist but cannot invite Staff", async () => {
  callerProfile.role = "staff";
  await handler(request("receptionist"));
  await expect(handler(request("staff"))).rejects.toMatchObject({ code: "permission-denied" });
});
test("stale Owner claims do not override a suspended current profile", async () => {
  callerProfile.status = "suspended";
  await expect(handler(request("receptionist"))).rejects.toMatchObject({ code: "permission-denied" });
  expect(mockFetch).not.toHaveBeenCalled();
});

test("Worker failures do not leave the old immediate-activation path available", async () => {
  mockFetch.mockResolvedValue({ ok: false, status: 409, json: async () => ({ error: "Duplicate work account" }) });
  await expect(handler(request("receptionist"))).rejects.toMatchObject({ code: "already-exists" });
});
