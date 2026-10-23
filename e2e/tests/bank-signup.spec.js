const { test, expect } = require("@playwright/test");
const { BANK, freshIdentity, codeFromLog } = require("./stack");

test("a new customer signs up with an emailed code, logs in, and sees their active login", async ({ page }) => {
  const { phone, aadhar } = freshIdentity();
  await page.goto(`${BANK}/bankuser.html`);

  // step 1: details + email -> a code is sent, no account yet
  await page.fill("#firstName", "Test");
  await page.fill("#lastName", "Customer");
  await page.fill("#aadharNumber", aadhar);
  await page.fill("#phno", phone);
  await page.fill("#pin", "4321");
  await page.fill("#registerEmail", "e2e.customer@example.com");
  await page.click("#registerButton");
  await expect(page.locator("#signupCodeStep")).toBeVisible();

  // a wrong code is refused and nothing is created
  await page.fill("#signupCode", "000000");
  await page.getByRole("button", { name: /Confirm/ }).click();
  await expect(page.locator("#status")).toContainText(/Invalid or expired code|failed/i);

  // step 2: the real code (read from the bank's log in CI) creates the account
  let code = null;
  for (let attempt = 0; attempt < 20 && !code; attempt++) {
    code = codeFromLog("bank", "signup", phone);
    if (!code) await page.waitForTimeout(1000);
  }
  expect(code, "the sign-up code should have been logged").toBeTruthy();
  await page.fill("#signupCode", code);
  await page.getByRole("button", { name: /Confirm/ }).click();
  await expect(page.locator("#status")).toContainText(/Account created/i);

  // log in with the PIN chosen at sign-up
  await page.fill("#loginPhno", phone);
  await page.fill("#loginPin", "4321");
  await page.locator("#loginCard").getByRole("button", { name: /login/i }).click();
  await expect(page.locator("#sessionStatus")).toContainText(/Logged in as/i);

  // the new Active Logins card lists this browser as the current device
  await page.getByRole("button", { name: "Show my logins" }).click();
  await expect(page.locator("#sessionList")).toContainText("(this device)");
});

test("signing up without an email is refused up front", async ({ page }) => {
  const { phone, aadhar } = freshIdentity();
  await page.goto(`${BANK}/bankuser.html`);
  await page.fill("#firstName", "No");
  await page.fill("#lastName", "Email");
  await page.fill("#aadharNumber", aadhar);
  await page.fill("#phno", phone);
  await page.fill("#pin", "4321");
  await page.click("#registerButton");

  await expect(page.locator("#status")).toContainText(/email/i);
  await expect(page.locator("#signupCodeStep")).toBeHidden();
});
