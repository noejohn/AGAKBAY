const nodemailer = require("nodemailer");
const { HttpsError } = require("firebase-functions/v2/https");

// Admin emails (new-account welcome, password reset codes) go out through
// the project's own Gmail account over SMTP. Resend can't be used for these
// yet: without a verified domain it only delivers to the Resend account
// owner, and these must reach any new admin's inbox.
//
// Both values are Firebase secrets, never in code or .env:
//   firebase functions:secrets:set GMAIL_USER
//   firebase functions:secrets:set GMAIL_APP_PASSWORD   (a Gmail App
//     Password — requires 2-Step Verification on that Gmail account)
const MAIL_SECRETS = ["GMAIL_USER", "GMAIL_APP_PASSWORD"];

// Where admins sign in — the dashboard is hosted on Vercel. Kept in code
// (not the gitignored functions/.env) so every teammate's deploy sends the
// same link; ADMIN_WEB_URL can still override it.
function adminWebUrl() {
  return (process.env.ADMIN_WEB_URL || "https://agakbay.vercel.app").replace(/\/+$/, "");
}

let transporter = null;

function getTransporter() {
  const user = process.env.GMAIL_USER;
  const pass = process.env.GMAIL_APP_PASSWORD;
  if (!user || !pass) {
    throw new HttpsError(
      "failed-precondition",
      "Email is not configured. Set the GMAIL_USER and GMAIL_APP_PASSWORD secrets.",
    );
  }
  if (!transporter) {
    transporter = nodemailer.createTransport({
      service: "gmail",
      auth: { user, pass },
    });
  }
  return transporter;
}

async function sendMail({ to, subject, text, html }) {
  await getTransporter().sendMail({
    from: `"Agakbay" <${process.env.GMAIL_USER}>`,
    to,
    subject,
    text,
    html,
  });
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Shared AGAKBAY-branded email frame. `bodyHtml` must already be escaped. */
function emailLayout(title, bodyHtml) {
  return `<!doctype html>
<html><body style="margin:0;background:#f4f1e6;font-family:Arial,Helvetica,sans-serif;color:#2b2117">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:24px 12px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
        style="max-width:520px;background:#ffffff;border-radius:16px;overflow:hidden">
        <tr><td style="background:#16342a;padding:20px 28px;color:#ffffff;font-size:20px;font-weight:bold">
          Agakbay Admin
        </td></tr>
        <tr><td style="padding:28px">
          <h1 style="margin:0 0 16px;font-size:20px">${escapeHtml(title)}</h1>
          ${bodyHtml}
          <p style="margin:24px 0 0;font-size:12px;color:#7a6f63">
            Can't find our emails? Check your Spam folder and mark this message as "Not spam".
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

function button(href, label) {
  return `<p style="margin:20px 0"><a href="${escapeHtml(href)}"
    style="display:inline-block;background:#1fa35c;color:#ffffff;text-decoration:none;
    padding:12px 22px;border-radius:10px;font-weight:bold">${escapeHtml(label)}</a></p>`;
}

/**
 * Sent to a newly created admin. Contains their sign-in email and a one-time
 * link to set their own password — the password is never written anywhere,
 * and the admin who created the account never sees the link.
 */
async function sendAdminWelcomeEmail({
  to,
  fullName,
  adminRole,
  managedMountainName,
  setupLink,
}) {
  const roleLabel = adminRole === "mountain_head"
    ? `Mountain Head — ${managedMountainName}`
    : "Tourism Admin";
  const signInUrl = adminWebUrl();
  const html = emailLayout("Your Agakbay admin account is ready", `
    <p style="margin:0 0 12px">Hi ${escapeHtml(fullName)},</p>
    <p style="margin:0 0 12px">An <b>administrator account</b> for the Agakbay
      Admin Dashboard has been created for you. This account is for
      administrators only — please don't share it.</p>
    <table role="presentation" cellpadding="0" cellspacing="0"
      style="margin:16px 0;background:#f4f1e6;border-radius:10px;padding:14px 16px;font-size:14px">
      <tr><td style="padding:4px 12px 4px 0;color:#7a6f63">Role</td>
          <td style="padding:4px 0"><b>${escapeHtml(roleLabel)}</b></td></tr>
      <tr><td style="padding:4px 12px 4px 0;color:#7a6f63">Sign-in email</td>
          <td style="padding:4px 0"><b>${escapeHtml(to)}</b></td></tr>
    </table>
    <p style="margin:0"><b>Step 1.</b> Set your password (this link works once and expires in about an hour):</p>
    ${button(setupLink, "Set my password")}
    <p style="margin:0"><b>Step 2.</b> Sign in to the Agakbay Admin Dashboard:</p>
    ${button(signInUrl, "Open Agakbay Admin")}
    <p style="margin:0;font-size:13px;color:#7a6f63">If the setup link expires, use
      <b>Forgot password?</b> on the sign-in page to get a reset code.
      If you weren't expecting this account, you can ignore this email.</p>
  `);
  const text = [
    `Hi ${fullName},`,
    "",
    "An administrator account for the Agakbay Admin Dashboard has been created for you.",
    `Role: ${roleLabel}`,
    `Sign-in email: ${to}`,
    "",
    `Step 1 — set your password (works once, expires in about an hour): ${setupLink}`,
    `Step 2 — sign in: ${signInUrl}`,
    "",
    "If the link expires, use 'Forgot password?' on the sign-in page.",
  ].join("\n");
  await sendMail({ to, subject: "Your Agakbay admin account", text, html });
}

/** Sent when an admin uses "Forgot password?" on the dashboard sign-in page. */
async function sendAdminResetCodeEmail({ to, code, expiresInMinutes }) {
  const html = emailLayout("Your password reset code", `
    <p style="margin:0 0 12px">Use this code to reset your Agakbay Admin password:</p>
    <p style="margin:16px 0;font-size:32px;font-weight:bold;letter-spacing:8px;
      background:#f4f1e6;border-radius:10px;padding:14px;text-align:center">${escapeHtml(code)}</p>
    <p style="margin:0;font-size:13px;color:#7a6f63">The code expires in
      ${expiresInMinutes} minutes. If you didn't ask to reset your password,
      ignore this email — your password stays the same.</p>
  `);
  const text = `Your Agakbay Admin password reset code is ${code}. ` +
    `It expires in ${expiresInMinutes} minutes. If you didn't ask for this, ignore this email.`;
  await sendMail({ to, subject: `${code} is your Agakbay password reset code`, text, html });
}

module.exports = {
  MAIL_SECRETS,
  adminWebUrl,
  escapeHtml,
  sendAdminWelcomeEmail,
  sendAdminResetCodeEmail,
};
