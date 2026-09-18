import asyncio
import sys
from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError

FAKE_DATA = {
    "email":    "kingkngdbjodbno@llf.com",
    "password": "Kingking00Q)@)",
    "day":      "1",
    "month":    "January",
    "year":     "1999",
    "fullname": "fjofjinoervnervnioernvemoe",
    "username": "klfeir",
}

SIGNUP_URL = "https://www.instagram.com/accounts/emailsignup/?hl=en"
SS_FILLED  = r"C:\temp\instagram_signup_filled.png"
SS_MODAL   = r"C:\temp\instagram_captcha_modal.png"
SS_AFTER   = r"C:\temp\instagram_captcha_clicked.png"
SS_ERROR   = r"C:\temp\error_missing_element.png"

WAIT_AFTER_SUBMIT = 10_000
WAIT_AFTER_CLICK  = 10_000
CDP_URL = "http://127.0.0.1:9222"


async def try_selectors(page, name, selectors, timeout_per=4000):
    for sel in selectors:
        try:
            loc = page.locator(sel).first
            if await loc.count() == 0:
                continue
            await loc.wait_for(state="visible", timeout=timeout_per)
            print(f"  ✅ {name} → {sel}")
            return loc
        except PlaywrightTimeoutError:
            continue
        except Exception as e:
            print(f"     ⚠️  {sel}: {e}")
            continue
    print(f"  ❌ {name} → پیدا نشد")
    return None


async def select_dropdown(page, combobox, value):
    await combobox.scroll_into_view_if_needed()
    await combobox.click()
    await page.wait_for_timeout(800)
    option = page.get_by_role("option", name=value, exact=True)
    n = await option.count()
    print(f"    {n} گزینه با متن دقیق '{value}'")
    for i in range(n):
        cand = option.nth(i)
        try:
            if await cand.is_visible():
                await cand.scroll_into_view_if_needed()
                await cand.click()
                await page.wait_for_timeout(400)
                return
        except Exception:
            continue
    raise RuntimeError(f"گزینه‌ی '{value}' visible پیدا نشد")


async def find_captcha_checkbox(page, timeout_ms=15000):
    outer_sel = "iframe#captcha-recaptcha"
    print(f"  🔎 جستجوی '{outer_sel}'...")
    try:
        await page.wait_for_selector(outer_sel, state="visible", timeout=timeout_ms)
        print("    ✅ iframe#captcha-recaptcha visible")
    except PlaywrightTimeoutError:
        print("    ❌ iframe#captcha-recaptcha ظاهر نشد")
        return None

    outer = page.frame_locator(outer_sel)

    for sel in ["#recaptcha-anchor", ".recaptcha-checkbox-border",
                ".recaptcha-checkbox", "div.recaptcha-checkbox"]:
        try:
            cb = outer.locator(sel).first
            if await cb.count() > 0 and await cb.is_visible(timeout=2000):
                print(f"    ✅ چک‌باکس پیدا شد (level 1): {sel}")
                return cb
        except Exception:
            pass

    nested_sels = [
        "iframe[src*='recaptcha/api2/anchor']",
        "iframe[src*='google.com/recaptcha']",
        "iframe[title*='reCAPTCHA']",
        "iframe[title*='recaptcha']",
    ]
    for nsel in nested_sels:
        try:
            nested = outer.frame_locator(nsel)
            cb = nested.locator("#recaptcha-anchor").first
            if await cb.count() > 0:
                print(f"    ✅ چک‌باکس پیدا شد (level 2): {nsel}")
                return cb
        except Exception:
            pass

    print("    ❌ چک‌باکس پیدا نشد")
    return None


async def main():
    async with async_playwright() as p:
        print(f"🔌 اتصال به Chrome روی {CDP_URL}...")
        browser = await p.chromium.connect_over_cdp(CDP_URL)
        context = browser.contexts[0] if browser.contexts else await browser.new_context()

        if context.pages:
            page = context.pages[0]
        else:
            page = await context.new_page()

        try:
            print(f"🌐 رفتن به: {SIGNUP_URL}")
            await page.goto(SIGNUP_URL, wait_until="domcontentloaded", timeout=60_000)
            await page.wait_for_timeout(4000)

            for txt in ["Allow all cookies", "Accept all", "Only allow essential cookies", "Accept"]:
                try:
                    btn = page.get_by_role("button", name=txt, exact=False).first
                    if await btn.is_visible(timeout=1500):
                        await btn.click()
                        print(f"  🍪 بستن بنر: {txt}")
                        await page.wait_for_timeout(800)
                        break
                except Exception:
                    pass

            print("✅ صفحه بارگذاری شد.\n")

            fields = {
                "email":    ["//label[normalize-space()='Mobile number or email']/preceding-sibling::input"],
                "password": ["input[type='password']"],
                "month":    ["div[aria-label='Select Month']"],
                "day":      ["div[aria-label='Select Day']"],
                "year":     ["div[aria-label='Select Year']"],
                "fullname": [
                    "//label[normalize-space()='Full name']/preceding-sibling::input",
                    "input[aria-label='Full name']",
                ],
                "username": ["input[aria-label='Username']"],
            }

            locators, missing = {}, []
            print("🔍 بررسی المان‌ها:")
            for name, sels in fields.items():
                loc = await try_selectors(page, name, sels)
                if loc is None:
                    missing.append(name)
                locators[name] = loc

            if missing:
                print(f"\n❌ پیدا نشده: {missing}")
                await page.screenshot(path=SS_ERROR, full_page=True)
                await browser.close()
                sys.exit(1)

            print("\n✏️  پر کردن فیلدها...")
            await locators["email"].fill(FAKE_DATA["email"]);                print("  ✅ Email")
            await locators["password"].fill(FAKE_DATA["password"]);          print("  ✅ Password")
            await select_dropdown(page, locators["year"],  FAKE_DATA["year"]);   print(f"  ✅ Year → {FAKE_DATA['year']}")
            await select_dropdown(page, locators["month"], FAKE_DATA["month"]);  print(f"  ✅ Month → {FAKE_DATA['month']}")
            await select_dropdown(page, locators["day"],   FAKE_DATA["day"]);    print(f"  ✅ Day → {FAKE_DATA['day']}")
            await locators["fullname"].fill(FAKE_DATA["fullname"]);          print("  ✅ Full Name")
            await locators["username"].fill(FAKE_DATA["username"]);          print("  ✅ Username")

            await page.wait_for_timeout(800)
            await page.screenshot(path=SS_FILLED, full_page=True)
            print(f"📸 فرم پر شده: {SS_FILLED}")

            print("\n🖱️  کلیک روی Submit...")
            submit = page.locator(
                "//div[@role='button'][.//span[normalize-space()='Submit']]"
            ).first
            if await submit.count() == 0:
                submit = page.get_by_role("button", name="Submit", exact=True).first
            await submit.scroll_into_view_if_needed()
            await submit.click()
            print("  ✅ Submit کلیک شد.")

            print(f"\n⏳ انتظار {WAIT_AFTER_SUBMIT/1000:.0f} ثانیه...")
            await page.wait_for_timeout(WAIT_AFTER_SUBMIT)

            print("\n🔍 بررسی وجود reCAPTCHA...")
            checkbox = await find_captcha_checkbox(page)

            if checkbox is None:
                await page.screenshot(path=SS_MODAL, full_page=True)
                print(f"📸 اسکرین‌شات بعد از Submit: {SS_MODAL}")
                print("ℹ️  reCAPTCHA پیدا نشد.")
            else:
                await page.screenshot(path=SS_MODAL, full_page=True)
                print(f"📸 اسکرین‌شات modal قبل از کلیک: {SS_MODAL}")

                print("\n🖱️  کلیک روی چک‌باکس 'I'm not a robot'...")
                clicked = False
                for attempt in range(3):
                    try:
                        await checkbox.scroll_into_view_if_needed()
                        await checkbox.click(timeout=5000)
                        clicked = True
                        print(f"  ✅ کلیک موفق (تلاش #{attempt+1})")
                        break
                    except Exception as e:
                        print(f"  ⚠️  تلاش #{attempt+1} ناموفق: {e}")
                        await page.wait_for_timeout(700)

                if not clicked:
                    try:
                        await checkbox.click(force=True, timeout=5000)
                        print("  ✅ با force کلیک شد")
                    except Exception as e:
                        print(f"  ❌ force هم نشد: {e}")

                print(f"\n⏳ انتظار {WAIT_AFTER_CLICK/1000:.0f} ثانیه بعد از کلیک...")
                await page.wait_for_timeout(WAIT_AFTER_CLICK)

                await page.screenshot(path=SS_AFTER, full_page=True)
                print(f"📸 اسکرین‌شات بعد از کلیک: {SS_AFTER}")

            print("\n🎉 تمام شد!")

        except Exception as e:
            print(f"\n❌ خطا: {e}")
            try:
                await page.screenshot(path=SS_ERROR, full_page=True)
                print(f"📸 اسکرین‌شات خطا: {SS_ERROR}")
            except Exception:
                pass
            await browser.close()
            sys.exit(1)

        print("🔌 قطع اتصال CDP (Chrome باز می‌مونه)")


if __name__ == "__main__":
    asyncio.run(main())
