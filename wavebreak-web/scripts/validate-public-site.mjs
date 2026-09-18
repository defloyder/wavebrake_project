import assert from 'node:assert/strict';
import { mkdirSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const modulePath = process.env.PLAYWRIGHT_MODULE;
if (!modulePath) throw new Error('Set PLAYWRIGHT_MODULE to playwright/index.mjs');
const { chromium } = await import(pathToFileURL(modulePath).href);
const base = process.env.SITE_URL || 'http://127.0.0.1:8097';
const output = process.env.SCREENSHOT_DIR || '../.artifacts/public-site';
mkdirSync(output, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const report = [];
const injectedHosts = new Set();
try {
    for (const width of [320, 390, 768, 1440, 1920]) {
        const context = await browser.newContext({ viewport: { width, height: 960 }, deviceScaleFactor: 1 });
        const page = await context.newPage();
        const errors = [];
        const externalRequests = [];
        page.on('pageerror', error => errors.push(error.message));
        page.on('request', request => {
            const url = new URL(request.url());
            // Local antivirus injects its own polling script into browser responses.
            if (url.hostname === 'gc.kis.v2.scr.kaspersky-labs.com') {
                injectedHosts.add(url.hostname);
                return;
            }
            if (url.origin !== new URL(base).origin) externalRequests.push(request.url());
        });
        for (const route of ['/', '/pricing', '/access', '/download']) {
            const response = await page.goto(base + route, { waitUntil: 'domcontentloaded' });
            assert.equal(response.status(), 200, route);
            await page.evaluate(() => Promise.race([document.fonts.ready, new Promise(resolve => setTimeout(resolve, 3000))]));
            await page.waitForTimeout(300);
            assert.equal(await page.locator('h1').count(), 1);
            assert.equal(await page.locator('header').count(), 1);
            assert.equal(await page.locator('footer').count(), 1);
            const brokenImages = await page.locator('img').evaluateAll(images =>
                images.filter(image => !image.complete || image.naturalWidth === 0).map(image => image.src));
            assert.deepEqual(brokenImages, [], 'Broken images');
            const clippedPreviewText = await page.locator('.download-device-core').evaluateAll(cores =>
                cores.flatMap(core => {
                    const frame = core.closest('.download-device').getBoundingClientRect();
                    return [...core.querySelectorAll('strong, small, .download-device-location')].filter(text => {
                        const rect = text.getBoundingClientRect();
                        return rect.bottom > frame.bottom + 1 || rect.top < frame.top || rect.right > frame.right;
                    }).map(text => text.textContent);
                }));
            assert.deepEqual(clippedPreviewText, [], 'Clipped app preview text');
            const schemas = await page.locator('script[type="application/ld+json"]').allTextContents();
            for (const schema of schemas) assert.equal(JSON.parse(schema)['@context'], 'https://schema.org');
            const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1);
            assert.equal(overflow, false, 'Horizontal overflow: ' + route + ' at ' + width);
            const canvas = page.locator('#download-tide');
            const pixels = await canvas.evaluate(c => {
                const data = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
                let painted = 0;
                for (let i = 3; i < data.length; i += 4) if (data[i]) painted++;
                return painted;
            });
            assert.ok(pixels > 100, 'Wave canvas is blank');
            const frame = await canvas.evaluate(c => c.toDataURL());
            await page.waitForTimeout(180);
            assert.notEqual(await canvas.evaluate(c => c.toDataURL()), frame, 'Wave is not moving');
            if (width < 761) {
                await page.locator('#wb-burger').click();
                assert.equal(await page.locator('#wb-burger').getAttribute('aria-expanded'), 'true');
                await page.keyboard.press('Escape');
                assert.equal(await page.locator('#wb-burger').getAttribute('aria-expanded'), 'false');
            }
            const firstFAQ = page.locator('details').first();
            if (await firstFAQ.count()) {
                await firstFAQ.locator('summary').click();
                assert.equal(await firstFAQ.getAttribute('open'), '');
            }
            await page.locator('footer').scrollIntoViewIfNeeded();
            await page.waitForTimeout(700);
            await page.evaluate(() => window.scrollTo(0, 0));
            await page.waitForTimeout(700);
            await page.screenshot({ path: output + '/' + (route.slice(1) || 'home') + '-' + width + '.png', fullPage: true });
            assert.deepEqual(errors, [], 'JavaScript errors');
            assert.deepEqual(externalRequests, [], 'Unexpected external dependencies');
            report.push({ route, width, status: 'PASSED', paintedPixels: pixels });
        }
        await context.close();
    }
    const reduced = await browser.newContext({ viewport: { width: 390, height: 844 }, reducedMotion: 'reduce' });
    const page = await reduced.newPage();
    await page.goto(base, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(500);
    const before = await page.locator('canvas').evaluate(c => c.toDataURL());
    await page.waitForTimeout(300);
    assert.equal(await page.locator('canvas').evaluate(c => c.toDataURL()), before, 'Reduced motion ignored');
    await page.setViewportSize({ width: 430, height: 844 });
    assert.ok(await page.locator('canvas').evaluate(c => c.getContext('2d').getImageData(0, 0, c.width, c.height).data.some(value => value > 0)), 'Canvas blank after resize');
    await reduced.close();
    const noJS = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 1440, height: 960 } });
    const staticPage = await noJS.newPage();
    await staticPage.goto(base);
    assert.ok(await staticPage.locator('h1').isVisible(), 'Content requires JavaScript');
    await noJS.close();
    console.log(JSON.stringify({ checks: report, reducedMotion: 'PASSED', noJavaScript: 'PASSED', environmentInjectedHosts: [...injectedHosts] }, null, 2));
} finally {
    await browser.close();
}
