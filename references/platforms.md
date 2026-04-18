# Platform Reference — URL Patterns & Extraction Signals

Lazy-loaded in Phase 3 only when a specific platform is active. Keeps the
base SKILL.md small.

For each platform: URL shape, primary CLI + fallbacks, and what to look for.

---

## LinkedIn

**URL shapes:**
- Profile: `linkedin.com/in/<handle>` — global.
- Profile (country-specific subdomain): `uk.linkedin.com/in/<handle>`,
  `de.linkedin.com/in/<handle>`, etc. — same content.
- Company: `linkedin.com/company/<company-slug>`.

**Extraction chain:**
1. `apify call <linkedin-profile-actor> --input '{"urls":[{"url": "<url>"}]}'`
2. fallback: `brightdata scrape <url>`
3. last-ditch: `jina read <url>` — returns visible text but no structured
   fields.

**Signals:**
- Current position, company, location (top of profile).
- Education section — verify DOB/age indirectly.
- Experience — career timeline with dates.
- Featured / Activity — external content signals.
- Recommendations — social graph.

**Watch for:**
- Common-name namesakes. Cross-check location + company.
- Auto-translated bios (LinkedIn machine-translates depending on viewer
  locale).

---

## Instagram

**URL shapes:**
- Profile: `instagram.com/<handle>/`.
- Tagged: `instagram.com/<handle>/tagged/`.

**Extraction chain:**
1. `apify call <instagram-profile-actor> --input '{"usernames":["<handle>"]}'`
2. fallback: `brightdata scrape <url>`

**Signals:**
- Bio: phone/email often in plain text, emoji-separated.
- Post captions: location tags, @mentions for social graph.
- Stories highlights: life-event timestamps.

**Watch for:**
- Instagram hides follower lists from non-authenticated scrapers. That data
  is not recoverable.

---

## Facebook

**URL shapes:**
- Personal: `facebook.com/<id>` or `facebook.com/<handle>`.
- Page: `facebook.com/<page-name>`.
- Group: `facebook.com/groups/<group-id>`.

**Extraction chain:**
- Personal: `brightdata scrape <url>` — **only Bright Data works**, other
  tools get blocked.
- Pages/Groups: `apify call <fb-pages-actor>` → `brightdata scrape`.

**Signals:**
- "About" section — work/education self-reported, verify elsewhere.
- Life events — usually most reliable date source on FB.
- Friends list — rarely scrapable without auth; treat as unavailable.

---

## TikTok

**URL shapes:**
- Profile: `tiktok.com/@<handle>`.
- Video: `tiktok.com/@<handle>/video/<id>`.

**Extraction chain:**
1. `apify call <tiktok-profile-actor>` → profile metadata + recent videos.
2. fallback: `brightdata scrape`.

**Signals:**
- Bio, verified badge, follower count, post frequency.
- Recent video captions: topic signal for psychoprofile.

---

## YouTube

**URL shapes:**
- Channel: `youtube.com/@<handle>` or `youtube.com/channel/<UC...>`.
- Video: `youtube.com/watch?v=<id>`.

**Extraction chain:**
1. `apify call <youtube-channel-actor>` — channel info + recent uploads.
2. For transcripts: `apify call <youtube-transcript-actor>` — yt-dlp and
   BrightData are **both** blocked by YouTube; Apify actors are the only
   reliable path.
3. fallback for page content: `jina read <url>` — gets visible page text
   but no transcript.

**Signals (transcripts > everything else for voice/psychoprofile):**
- Speaking style, topic frequency, mental models.
- Guests + co-speakers — social graph seeds.

---

## Telegram

**URL shapes:**
- Public channel: `t.me/<channel>`.
- Web view (preferred for scraping): `t.me/s/<channel>`.
- Private/DM: not scrapable (only through operator's own `tg.py`, which
  is Phase-2 gated).

**Extraction chain:**
- Public: `WebFetch https://t.me/s/<channel>` → `jina read`.
- Deep history: not available without Telegram auth; operator's own
  session only via Phase 2.

**Signals:**
- Recent messages — topic focus.
- Forwarded-from fields — inbound info-graph.

---

## Twitter / X

**URL shapes:**
- Profile: `x.com/<handle>` (or `twitter.com/<handle>` — same).
- Tweet: `x.com/<handle>/status/<id>`.

**Extraction chain:**
- Most API options have degraded or require paid access. Consider:
  - `jina read` on the public profile page — partial.
  - `brightdata scrape` — most reliable for profile pages.
  - Nitter mirrors come and go; not recommended.

---

## Generic web page

**Extraction chain:**
1. `jina read <url>` — URL → clean markdown.
2. fallback: `brightdata scrape <url>` (handles CAPTCHAs / paywalls).

---

## Ukrainian public registers (for Ukrainian subjects)

- **ЄДР (Unified State Register):** look up companies and their directors.
- **OpenDataBot:** `opendatabot.ua` — ЄДР mirror + court decisions +
  vehicles + real-estate. Paid access for full records; basic data free.
- **YouControl:** `youcontrol.com.ua` — another ЄДР mirror, good English
  interface at `/en/`.
- **Clarity Project:** `clarity-project.info/edr/<едрпоу>` — free ЄДР data,
  often the easiest to reach via `jina read`.
- **Ring.org.ua:** `ring.org.ua/edr/uk/company/<едрпоу>` — yet another ЄДР
  mirror.
- **Prozorro:** `prozorro.gov.ua` — public procurement; contract
  counterparty searches.

**Typical query path for a Ukrainian subject:**
1. Know company name → search YouControl or OpenDataBot by name.
2. Get ЄДРПОУ code → cross-reference with Clarity Project for free full
   detail + Prozorro for contracts.
3. Director name from the register → `jina read` their LinkedIn if public.

---

## Conference archives (useful when a subject has thin profile but deep
speaker history)

- **YouTube channels of conferences** — best source of long-form voice.
- **Lanyrd** — defunct, but wayback copies still useful.
- **Individual conference sites** — often have speaker bios that outlast
  the subject's personal profiles.
- **Wayback Machine:** `web.archive.org/web/2024*/<url>` for deleted
  content.
