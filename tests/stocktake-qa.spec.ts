import { expect, test, type Page } from "@playwright/test";

const qaUser = process.env.STOCKTAKE_QA_USER;
const qaPassword = process.env.STOCKTAKE_QA_PASSWORD;
const navNames = {
  count: /^(count|count record stock)$/i,
  report: /^(report|report review totals)$/i,
  catalogue: /^(catalogue|catalogue manage products)$/i,
  organisation: /^(organisation|organisation manage access)$/i,
};

test.skip(!qaUser || !qaPassword, "Set STOCKTAKE_QA_USER and STOCKTAKE_QA_PASSWORD before running QA.");

async function signIn(page: Page) {
  await page.goto("/");
  await page.waitForLoadState("networkidle");

  if (await page.getByRole("button", { name: navNames.count }).first().isVisible().catch(() => false)) {
    return;
  }

  if (await page.getByRole("heading", { name: /create account/i }).isVisible().catch(() => false)) {
    await page.getByRole("button", { name: /already have an account\? sign in/i }).click();
  }

  const authPanel = page.locator("section").filter({ has: page.getByRole("heading", { name: /^sign in$/i }) });
  await expect(authPanel).toBeVisible();
  const inputs = authPanel.locator("input");
  await inputs.nth(0).fill(qaUser!);
  await inputs.nth(1).fill(qaPassword!);
  await authPanel.getByRole("button", { name: /sign in/i }).click();

  await expect(page.getByRole("button", { name: /failed to fetch/i })).toHaveCount(0, { timeout: 10_000 });
  await expect(page.getByText(/no organisation access/i)).toHaveCount(0, { timeout: 10_000 });
  await expect(page.getByRole("button", { name: navNames.count }).first()).toBeVisible({ timeout: 15_000 });
  await expect(page.getByRole("img", { name: /auzkiwi logo/i }).first()).toBeVisible();
}

async function expectNoHorizontalScroll(page: Page) {
  const hasHorizontalScroll = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  expect(hasHorizontalScroll).toBe(false);
}

async function openSection(page: Page, name: RegExp) {
  const button = page.getByRole("button", { name }).first();
  await expect(button).toBeVisible();
  await button.click();
  await page.waitForTimeout(300);
}

function visibleReport(page: Page) {
  return page.locator("section:visible").filter({
    has: page.getByRole("button", { name: /csv|export csv/i }),
  }).first();
}

test.describe("Skya Stocktake QA smoke check", () => {
  test.beforeEach(async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (message) => {
      if (message.type() === "error") consoleErrors.push(message.text());
    });
    page.on("pageerror", (error) => consoleErrors.push(error.message));
    test.info().attach("console-errors", {
      body: Buffer.from(consoleErrors.join("\n") || "No console errors captured."),
      contentType: "text/plain",
    });
  });

  test("login, navigation, pages, and responsive layout", async ({ page }, testInfo) => {
    await signIn(page);
    await expectNoHorizontalScroll(page);
    await page.screenshot({ path: testInfo.outputPath("signed-in.png"), fullPage: true });

    await openSection(page, navNames.count);
    await expect(page.getByText(/product code/i).first()).toBeVisible();
    await expect(page.getByText(/count quantity/i).first()).toBeVisible();
    await expect(page.getByText(/location/i).first()).toBeVisible();
    await expectNoHorizontalScroll(page);

    await openSection(page, navNames.report);
    const report = visibleReport(page);
    await expect(report).toBeVisible();
    await expect.poll(async () => (await report.innerText()).toLowerCase()).toContain("total units");
    await expect(report.getByRole("button", { name: /csv|export csv/i }).first()).toBeVisible();
    await expect(report.getByRole("button", { name: /excel/i }).first()).toBeVisible();
    await expect(report.getByRole("button", { name: /pdf/i }).first()).toBeVisible();
    await expect(report.getByRole("button", { name: /print/i }).first()).toBeVisible();
    await expectNoHorizontalScroll(page);
    await page.screenshot({ path: testInfo.outputPath("report.png"), fullPage: true });

    await openSection(page, navNames.catalogue);
    await expect(page.getByText(/product catalogue/i).first()).toBeVisible();
    await expectNoHorizontalScroll(page);

    const organisationButton = page.getByRole("button", { name: navNames.organisation }).first();
    if (await organisationButton.isVisible().catch(() => false)) {
      await organisationButton.click();
      await expect(page.getByText(/organisation/i).first()).toBeVisible();
      await expectNoHorizontalScroll(page);
    }
  });
});
