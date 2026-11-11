jest.mock("firebase-admin/app", () => ({ initializeApp: jest.fn() }));
const mockCreateUser = jest.fn(async () => ({ uid: "new-user" }));
const mockSet = jest.fn(async () => undefined);
let callerProfile = { role: "owner", tenant_id: "gym", status: "active" };
jest.mock("firebase-admin/auth", () => ({ getAuth: () => ({
  createUser: mockCreateUser,
  generatePasswordResetLink: jest.fn(async () => "test-link"),
}) }));
jest.mock("firebase-admin/firestore", () => ({
  getFirestore: () => ({
    collection: (name: string) => {
      if (name === "users") {
        return { doc: () => ({ get: async () => ({ data: () => callerProfile }), set: mockSet }) };
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
  data: { role, tenantId: "gym", branchId: "b", name: "Test", email: "test@example.test" } });

beforeEach(() => {
  callerProfile = { role: "owner", tenant_id: "gym", status: "active" };
  mockCreateUser.mockClear(); mockSet.mockClear();
});
test("new receptionist starts with no modules through the callable too", async () => {
  await handler(request("receptionist"));
  const document = (mockSet.mock.calls as unknown as [Record<string, unknown>][])[0][0];
  expect(document.role).toBe("receptionist");
  expect(Object.values(document.permissions as object).some(Boolean)).toBe(false);
});
test("Owner cannot invite another Owner", async () => {
  await expect(handler(request("owner"))).rejects.toMatchObject({ code: "invalid-argument" });
  expect(mockCreateUser).not.toHaveBeenCalled();
});
test("Staff can invite receptionist but cannot invite Staff", async () => {
  callerProfile.role = "staff";
  await handler(request("receptionist"));
  await expect(handler(request("staff"))).rejects.toMatchObject({ code: "permission-denied" });
});
test("stale Owner claims do not override a suspended current profile", async () => {
  callerProfile.status = "suspended";
  await expect(handler(request("receptionist"))).rejects.toMatchObject({ code: "permission-denied" });
  expect(mockCreateUser).not.toHaveBeenCalled();
});
