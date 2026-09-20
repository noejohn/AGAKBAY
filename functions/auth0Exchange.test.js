process.env.AUTH0_DOMAIN = "test-tenant.us.auth0.com";
process.env.AUTH0_CLIENT_ID = "test-client-id";

const mockGetUserByEmail = jest.fn();
const mockCreateUser = jest.fn();
const mockSetCustomUserClaims = jest.fn();
const mockCreateCustomToken = jest.fn().mockResolvedValue("fake-custom-token");
const mockDocGet = jest.fn();
const mockDocSet = jest.fn();
const mockDocUpdate = jest.fn();
const mockPublicProfileSet = jest.fn();

jest.mock("firebase-admin", () => ({
  initializeApp: jest.fn(),
  auth: jest.fn(() => ({
    getUserByEmail: mockGetUserByEmail,
    createUser: mockCreateUser,
    setCustomUserClaims: mockSetCustomUserClaims,
    createCustomToken: mockCreateCustomToken,
  })),
  firestore: Object.assign(
    jest.fn(() => ({
      collection: jest.fn(() => ({
        doc: jest.fn(() => ({
          get: mockDocGet,
          set: mockDocSet,
          update: mockDocUpdate,
          collection: jest.fn(() => ({
            doc: jest.fn(() => ({ set: mockPublicProfileSet })),
          })),
        })),
      })),
    })),
    { FieldValue: { serverTimestamp: jest.fn() } },
  ),
}));

const mockJwtVerify = jest.fn();
jest.mock("jose", () => ({
  createRemoteJWKSet: jest.fn(() => ({})),
  jwtVerify: (...args) => mockJwtVerify(...args),
}));

const mockGetRedisClient = jest.fn();
jest.mock("./redisCache", () => ({
  getRedisClient: (...args) => mockGetRedisClient(...args),
}));

const {
  resolveFirebaseUid,
  exchangeAuth0Token,
  setInitialAccountType,
} = require("./auth0Exchange");

beforeEach(() => {
  jest.clearAllMocks();
  // No Redis configured by default — matches production behavior when the
  // UPSTASH_* secrets aren't set, and keeps every pre-existing test above
  // unaffected by the rate limiter (it fails open with a null client).
  mockGetRedisClient.mockReturnValue(null);
});

describe("resolveFirebaseUid", () => {
  it("reuses the existing Firebase uid when the email matches a migrated user", async () => {
    mockGetUserByEmail.mockResolvedValue({ uid: "existing-uid-123" });

    const { uid, isNew } = await resolveFirebaseUid({ email: "a@b.com", displayName: "A" });

    expect(uid).toBe("existing-uid-123");
    expect(isNew).toBe(false);
    expect(mockCreateUser).not.toHaveBeenCalled();
  });

  it("creates a new Firebase user when no account exists for that email", async () => {
    mockGetUserByEmail.mockRejectedValue({ code: "auth/user-not-found" });
    mockCreateUser.mockResolvedValue({ uid: "new-uid-456" });

    const { uid, isNew } = await resolveFirebaseUid({ email: "new@b.com", displayName: "New" });

    expect(uid).toBe("new-uid-456");
    expect(isNew).toBe(true);
  });

  it("rethrows unexpected lookup errors instead of treating them as not-found", async () => {
    mockGetUserByEmail.mockRejectedValue({ code: "auth/internal-error" });

    await expect(resolveFirebaseUid({ email: "x@b.com" })).rejects.toEqual({
      code: "auth/internal-error",
    });
  });
});

describe("exchangeAuth0Token", () => {
  const callHandler = (data) => exchangeAuth0Token.run({ data, auth: null });

  it("rejects when idToken is missing", async () => {
    await expect(callHandler({})).rejects.toThrow(/idToken/);
  });

  it("rejects with unauthenticated when JWT verification fails", async () => {
    mockJwtVerify.mockRejectedValue(new Error("bad signature"));

    await expect(callHandler({ idToken: "bogus" })).rejects.toThrow(/Invalid or expired/);
  });

  it("rejects when the Auth0 email is not verified", async () => {
    mockJwtVerify.mockResolvedValue({
      payload: { email: "a@b.com", email_verified: false },
    });

    await expect(callHandler({ idToken: "tok" })).rejects.toThrow(/not verified/);
  });

  it("mirrors an existing user's Firestore role into custom claims before minting a token", async () => {
    mockJwtVerify.mockResolvedValue({
      payload: { email: "guide@b.com", email_verified: true, name: "Guide Person" },
    });
    mockGetUserByEmail.mockResolvedValue({ uid: "guide-uid" });
    mockDocGet.mockResolvedValue({
      data: () => ({ role: "tour_guide", accountType: "tour_guide", guideVerified: true }),
    });

    const result = await callHandler({ idToken: "tok" });

    expect(mockSetCustomUserClaims).toHaveBeenCalledWith("guide-uid", {
      role: "tour_guide",
      accountType: "tour_guide",
      guideVerified: true,
      admin: false,
    });
    expect(mockCreateCustomToken).toHaveBeenCalledWith("guide-uid");
    expect(result.firebaseCustomToken).toBe("fake-custom-token");
  });

  it("mirrors admin: true only when Firestore role is exactly 'admin'", async () => {
    mockJwtVerify.mockResolvedValue({
      payload: { email: "admin@b.com", email_verified: true, name: "Admin Person" },
    });
    mockGetUserByEmail.mockResolvedValue({ uid: "admin-uid" });
    mockDocGet.mockResolvedValue({
      data: () => ({ role: "admin", accountType: "admin", guideVerified: null }),
    });

    await callHandler({ idToken: "tok" });

    expect(mockSetCustomUserClaims).toHaveBeenCalledWith("admin-uid", {
      role: "admin",
      accountType: "admin",
      guideVerified: null,
      admin: true,
    });
  });

  it("bootstraps a fresh hiker doc and default claims for a brand-new user", async () => {
    mockJwtVerify.mockResolvedValue({
      payload: { email: "fresh@b.com", email_verified: true, name: "Fresh Hiker" },
    });
    mockGetUserByEmail.mockRejectedValue({ code: "auth/user-not-found" });
    mockCreateUser.mockResolvedValue({ uid: "fresh-uid" });

    const result = await callHandler({ idToken: "tok" });

    expect(mockDocSet).toHaveBeenCalledWith(
      expect.objectContaining({
        role: "hiker",
        accountType: "hiker",
        guideVerified: null,
        accountTypeConfirmed: false,
      }),
    );
    expect(mockSetCustomUserClaims).toHaveBeenCalledWith("fresh-uid", {
      role: "hiker",
      accountType: "hiker",
      guideVerified: null,
      admin: false,
    });
    expect(result.isNewUser).toBe(true);
  });

  it("rejects with resource-exhausted once the per-email rate limit is exceeded", async () => {
    mockJwtVerify.mockResolvedValue({
      payload: { email: "spammer@b.com", email_verified: true, name: "Spammer" },
    });
    mockGetRedisClient.mockReturnValue({
      incr: jest.fn().mockResolvedValue(11),
      expire: jest.fn(),
    });

    await expect(callHandler({ idToken: "tok" })).rejects.toMatchObject({
      code: "resource-exhausted",
    });
    expect(mockGetUserByEmail).not.toHaveBeenCalled();
  });
});

describe("setInitialAccountType", () => {
  const callHandler = (data, uid = "user-1") =>
    setInitialAccountType.run({ data, auth: { uid } });

  it("rejects when not signed in", async () => {
    await expect(
      setInitialAccountType.run({ data: { accountType: "hiker" }, auth: null }),
    ).rejects.toThrow(/signed in/);
  });

  it("rejects an invalid accountType value", async () => {
    mockDocGet.mockResolvedValue({ exists: true, data: () => ({}) });

    await expect(callHandler({ accountType: "admin" })).rejects.toThrow(
      /hiker.*tour_guide/,
    );
  });

  it("rejects when no profile document exists", async () => {
    mockDocGet.mockResolvedValue({ exists: false });

    await expect(callHandler({ accountType: "hiker" })).rejects.toThrow(
      /No user profile/,
    );
  });

  it("refuses to run a second time once accountTypeConfirmed is true", async () => {
    mockDocGet.mockResolvedValue({
      exists: true,
      data: () => ({ accountTypeConfirmed: true }),
    });

    await expect(callHandler({ accountType: "tour_guide" })).rejects.toThrow(
      /already been set/,
    );
    expect(mockDocUpdate).not.toHaveBeenCalled();
  });

  it("sets hiker with guideVerified null, and marks confirmed", async () => {
    mockDocGet.mockResolvedValue({
      exists: true,
      data: () => ({ accountTypeConfirmed: false }),
    });

    const result = await callHandler({ accountType: "hiker" }, "user-2");

    expect(mockDocUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        accountType: "hiker",
        role: "hiker",
        guideVerified: null,
        accountTypeConfirmed: true,
      }),
    );
    expect(mockSetCustomUserClaims).toHaveBeenCalledWith("user-2", {
      role: "hiker",
      accountType: "hiker",
      guideVerified: null,
    });
    expect(result.accountType).toBe("hiker");
  });

  it("sets tour_guide with guideVerified false (pending), not true", async () => {
    mockDocGet.mockResolvedValue({
      exists: true,
      data: () => ({ accountTypeConfirmed: false }),
    });

    await callHandler({ accountType: "tour_guide" }, "user-3");

    expect(mockDocUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        accountType: "tour_guide",
        role: "tour_guide",
        guideVerified: false,
        accountTypeConfirmed: true,
      }),
    );
    expect(mockSetCustomUserClaims).toHaveBeenCalledWith("user-3", {
      role: "tour_guide",
      accountType: "tour_guide",
      guideVerified: false,
    });
  });
});
