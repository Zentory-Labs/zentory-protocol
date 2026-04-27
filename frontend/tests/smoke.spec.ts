import { test, expect } from "@playwright/test";

test.describe("smoke", () => {
  test("home loads and renders hero + swap", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: /zentory\s+protocol/i })).toBeVisible();
    await expect(page.getByText("ZENT Swap")).toBeVisible();
  });

  test("stake page loads", async ({ page }) => {
    await page.goto("/stake");
    await expect(page.getByRole("heading", { name: /zent staking/i })).toBeVisible();
    await expect(page.getByText("Stake ZENT")).toBeVisible();
  });

  test("signals page loads", async ({ page }) => {
    await page.goto("/signals");
    await expect(page.getByRole("heading", { name: /signal dashboard/i })).toBeVisible();
  });

  test("govern page loads", async ({ page }) => {
    await page.goto("/govern");
    await expect(page.getByRole("link", { name: "Zentory Labs" }).first()).toBeVisible();
  });
});

