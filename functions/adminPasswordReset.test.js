jest.mock("./mailer", () => ({
  MAIL_SECRETS: [],
  sendAdminResetCodeEmail: jest.fn().mockResolvedValue(),
}));

const {
  passwordProblem,
  hashCode,
  codesMatch,
  normalizeEmail,
} = require("./adminPasswordReset");

describe("passwordProblem (new admin password rules)", () => {
  test("accepts a strong password", () => {
    expect(passwordProblem("Hiking#2026")).toBeNull();
  });

  test.each([
    ["short1!", /at least 8/],
    ["longpassword!", /number/],
    ["longpassword1", /special/],
    [undefined, /at least 8/],
  ])("rejects %p", (password, message) => {
    expect(passwordProblem(password)).toMatch(message);
  });
});

describe("reset codes", () => {
  test("the right code for the right account matches", () => {
    const stored = hashCode("123456", "uid-1");
    expect(codesMatch("123456", "uid-1", stored)).toBe(true);
  });

  test("a wrong code does not match", () => {
    const stored = hashCode("123456", "uid-1");
    expect(codesMatch("654321", "uid-1", stored)).toBe(false);
  });

  test("a code issued for another account does not match", () => {
    const stored = hashCode("123456", "uid-1");
    expect(codesMatch("123456", "uid-2", stored)).toBe(false);
  });

  test("the raw code is never what gets stored", () => {
    expect(hashCode("123456", "uid-1")).not.toContain("123456");
  });

  test("a missing stored hash never matches", () => {
    expect(codesMatch("123456", "uid-1", undefined)).toBe(false);
  });
});

test("emails are compared case-insensitively", () => {
  expect(normalizeEmail("  Admin@Example.COM ")).toBe("admin@example.com");
});
