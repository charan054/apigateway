const { test, expect } = require("@playwright/test");
const { STOREFRONT, PRODUCT, INTERNAL_KEY } = require("./stack");

let productId;
const PRODUCT_NAME = `Dove Shampoo ${Date.now()}`;

test.beforeAll(async ({ request }) => {
  // a product to browse: the catalog of a fresh stack is empty
  const created = await request.post(`${PRODUCT}/product/add`, {
    headers: { "X-Service-Key": INTERNAL_KEY },
    data: { productName: PRODUCT_NAME, productCategory: "Personal care", productPrice: 99, productStock: 25 },
  });
  expect(created.ok(), `adding a product failed: ${created.status()}`).toBeTruthy();
  productId = (await created.json()).productId;
});

test("the storefront lists a product and a typo in the search still finds it", async ({ page }) => {
  await page.goto(`${STOREFRONT}/shop.html`);
  await page.fill("#loginPhno", "9000000000");     // the shop opens on the sign-in card; the catalog itself is public
  await page.evaluate(() => { document.getElementById("loginSection")?.classList.add("hidden"); });

  const consoleErrors = [];
  page.on("pageerror", (e) => consoleErrors.push(e.message));

  const response = await page.request.get(`${STOREFRONT}/cart/search?name=shampoe`);
  expect(response.ok()).toBeTruthy();
  expect(response.headers()["x-search-corrected"]).toBe("true");
  const found = await response.json();
  expect(found.map((p) => p.productName)).toContain(PRODUCT_NAME);
  expect(consoleErrors).toEqual([]);
});

test("the product dialog checks delivery for a pincode", async ({ page }) => {
  await page.goto(`${STOREFRONT}/shop.html`);
  await page.waitForFunction(() => typeof openProductModal === "function");
  await page.evaluate(async (id) => {
    document.getElementById("loginSection")?.classList.add("hidden");
    await loadProducts();
    await openProductModal(id);
  }, productId);

  await expect(page.locator("#modalDelivery")).toBeVisible();
  await page.fill("#deliveryPincode", "500081");
  await page.getByRole("button", { name: "Check" }).click();
  await expect(page.locator("#deliveryEstimateResult")).toContainText(/deliver/i);
});

test("the language picker switches the page to Hindi and Telugu and back", async ({ page }) => {
  await page.goto(`${STOREFRONT}/shop.html`);
  const phoneBox = page.locator("#loginPhno");
  await expect(phoneBox).toHaveAttribute("placeholder", "10-digit phone number");

  await page.selectOption("#langSelect", "hi");
  await expect(phoneBox).toHaveAttribute("placeholder", "10 अंकों का फ़ोन नंबर");
  await page.selectOption("#langSelect", "te");
  await expect(phoneBox).toHaveAttribute("placeholder", "10 అంకెల ఫోన్ నంబర్");
  await page.selectOption("#langSelect", "en");
  await expect(phoneBox).toHaveAttribute("placeholder", "10-digit phone number");

  // the choice is remembered
  await page.selectOption("#langSelect", "hi");
  await page.reload();
  await expect(page.locator("#loginPhno")).toHaveAttribute("placeholder", "10 अंकों का फ़ोन नंबर");
});
