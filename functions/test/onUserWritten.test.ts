// Mock firebase-admin antes de importar la función
jest.mock("firebase-admin/app", () => ({ initializeApp: jest.fn() }));

const mockSetCustomUserClaims = jest.fn().mockResolvedValue(undefined);
const mockRevokeRefreshTokens = jest.fn().mockResolvedValue(undefined);

jest.mock("firebase-admin/auth", () => ({
  getAuth: jest.fn(() => ({
    setCustomUserClaims: mockSetCustomUserClaims,
    revokeRefreshTokens: mockRevokeRefreshTokens,
  })),
}));

jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentWritten: jest.fn((_, handler) => handler),
}));

jest.mock("firebase-functions/v2", () => ({
  logger: { info: jest.fn() },
}));

// Importar después de los mocks
import { onDocumentWritten } from "firebase-functions/v2/firestore";

const makeEvent = (
  afterData: object | null,
  uid = "uid-test"
) => ({
  params: { uid },
  data: {
    after: {
      exists: afterData !== null,
      data: () => afterData,
    },
  },
});

describe("onUserWritten", () => {
  let handler: (event: any) => Promise<void>;

  beforeAll(async () => {
    // La importación del módulo registra el handler vía onDocumentWritten mock
    await import("../src/index");
    handler = (onDocumentWritten as jest.Mock).mock.calls[0][1];
  });

  beforeEach(() => {
    mockSetCustomUserClaims.mockClear();
    mockRevokeRefreshTokens.mockClear();
  });

  it("asigna claims correctos para un owner", async () => {
    const event = makeEvent({
      role: "owner",
      tenant_id: "tenant-abc",
      branch_id: null,
      status: "active",
    });

    await handler(event);

    expect(mockSetCustomUserClaims).toHaveBeenCalledWith("uid-test", {
      role: "owner",
      tenant_id: "tenant-abc",
      branch_id: null,
    });
    expect(mockRevokeRefreshTokens).not.toHaveBeenCalled();
  });

  it("asigna claims correctos para un staff con branch", async () => {
    const event = makeEvent({
      role: "staff",
      tenant_id: "tenant-abc",
      branch_id: "branch-xyz",
      status: "active",
    });

    await handler(event);

    expect(mockSetCustomUserClaims).toHaveBeenCalledWith("uid-test", {
      role: "staff",
      tenant_id: "tenant-abc",
      branch_id: "branch-xyz",
    });
    expect(mockRevokeRefreshTokens).not.toHaveBeenCalled();
  });

  it("asigna claims para superuser con tenant_id y branch_id en null", async () => {
    const event = makeEvent({
      role: "superuser",
      tenant_id: null,
      branch_id: null,
      status: "active",
    });

    await handler(event);

    expect(mockSetCustomUserClaims).toHaveBeenCalledWith("uid-test", {
      role: "superuser",
      tenant_id: null,
      branch_id: null,
    });
  });

  it("revoca tokens al suspender un usuario", async () => {
    const event = makeEvent({
      role: "staff",
      tenant_id: "tenant-abc",
      branch_id: "branch-xyz",
      status: "suspended",
    });

    await handler(event);

    expect(mockSetCustomUserClaims).toHaveBeenCalled();
    expect(mockRevokeRefreshTokens).toHaveBeenCalledWith("uid-test");
  });

  it("limpia claims cuando el documento es eliminado", async () => {
    const event = makeEvent(null);

    await handler(event);

    expect(mockSetCustomUserClaims).toHaveBeenCalledWith("uid-test", {});
    expect(mockRevokeRefreshTokens).not.toHaveBeenCalled();
  });
  it("no asigna acceso al gimnasio a una cuenta pendiente de activación", async () => {
    await handler(makeEvent({ role: 'staff', tenant_id: 'tenant-abc', branch_id: 'b', status: 'pending' }));
    expect(mockSetCustomUserClaims).toHaveBeenCalledWith('uid-test', {});
    expect(mockRevokeRefreshTokens).not.toHaveBeenCalled();
  });
});
