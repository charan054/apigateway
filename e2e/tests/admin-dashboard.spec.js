const { test, expect } = require("@playwright/test");
const { STOREFRONT } = require("./stack");

test("the admin dashboard loads with its sign-in and two-step controls", async ({ page }) => {
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto(`${STOREFRONT}/cart.html`);

  await expect(page.locator("#adminUsername")).toBeVisible();
  await expect(page.locator("#adminPassword")).toBeVisible();
  await expect(page.getByRole("button", { name: "Sign In" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Set up two-step" })).toBeVisible();
  // the authenticator-code box only shows when an account with two-step on signs in
  await expect(page.locator("#adminCode")).toBeHidden();
  expect(errors).toEqual([]);
});

test("a wrong admin sign-in is refused with a message", async ({ page }) => {
  await page.goto(`${STOREFRONT}/cart.html`);
  await page.fill("#adminUsername", "nobody");
  await page.fill("#adminPassword", "not-a-real-password");
  await page.getByRole("button", { name: "Sign In" }).click();

  await expect(page.locator("#status")).toContainText(/invalid|failed/i);
});
