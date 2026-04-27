# Apify Actor Catalog — Phase 3 Extraction

Lazy-loaded in Phase 3 only when an `apify call` is about to fire. Maps
each platform + use-case to an actor ID, input shape, output keys, quirks.

Conventions:

- `apify/<slug>` = official Apify-maintained actor.
- `<author>/<slug>` = community actor. Use only when no official exists;
  verify maintenance status (last-run date on the Store page) before
  trusting.
- All actors invoked via `apify call <actor-id> --input <json>`. Add
  `--silent` for machine-parsing.
- Cost = nominal Apify-Store list price at time of writing; check the
  Store page for the live number before quoting in the audit log.
- `# TODO: verify on Apify Store` means the slug is a plausible guess
  from naming convention — confirm before relying on it.

---

## Instagram

### Instagram — profile

- **Actor ID:** `apify/instagram-profile-scraper`
- **Input shape:**
  ```json
  { "usernames": ["someone"], "resultsType": "details" }
  ```
- **Output key fields:** `username`, `fullName`, `biography`, `externalUrl`,
  `followersCount`, `followsCount`, `postsCount`, `profilePicUrl`, `verified`,
  `isBusinessAccount`, `businessCategoryName`.
- **Typical cost:** ~$2 per 1k profiles.
- **Notes:** Bio often holds plain-text email/phone separated by emoji.
  Follow `externalUrl` (linktree/site). For non-business accounts `email`
  and `phone` come back null even when present in bio — parse `biography`
  yourself.

### Instagram — posts

- **Actor ID:** `apify/instagram-scraper`
- **Input shape:**
  ```json
  { "directUrls": ["https://instagram.com/someone/"], "resultsType": "posts", "resultsLimit": 50 }
  ```
- **Output key fields:** `id`, `shortCode`, `caption`, `hashtags`, `mentions`,
  `url`, `commentsCount`, `likesCount`, `timestamp`, `locationName`,
  `ownerUsername`, `displayUrl` (image), `videoUrl` (if reel).
- **Typical cost:** ~$2.30 per 1k results.
- **Notes:** Same actor handles posts, reels, and IGTV via `resultsType`.
  Stories require auth and are not returned.

### Instagram — comments

- **Actor ID:** `apify/instagram-comment-scraper`
- **Input shape:**
  ```json
  { "directUrls": ["https://instagram.com/p/<shortcode>/"], "resultsLimit": 100 }
  ```
- **Output key fields:** `id`, `text`, `ownerUsername`, `timestamp`,
  `likesCount`, `repliesCount`, `replyToCommentId`.
- **Typical cost:** ~$2 per 1k comments.
- **Notes:** Reply-threads one hop deep; nested replies need re-scrape
  by `replyToCommentId`. Heavy posts rate-limit — if first call returns
  < requested count without an error, switch to `brightdata scrape`
  rather than retrying.

### Instagram — reels / stories

- **Actor ID:** `apify/instagram-reel-scraper` for reels; stories need
  `apify/instagram-api-scraper` with a session cookie.
- **Input shape (reels):** `{ "username": "someone", "resultsLimit": 30 }`
- **Output key fields (reels):** `id`, `caption`, `videoUrl`, `viewCount`,
  `playCount`, `musicTitle`, `timestamp`, `hashtags`.
- **Typical cost:** ~$2.30 per 1k reels; stories ~$5 per 1k.
- **Notes:** Stories disappear after 24h; only "highlights" reliably
  scrape. Reels captions usually outperform posts for voice signal.

---

## Facebook

Personal profiles are mostly blocked by Apify — Meta's anti-scrape posture
against `facebook.com/<id>` is stricter than for pages/groups. For
personal, `platforms.md` says go straight to `brightdata scrape`. Actors
below cover what *is* reachable.

### Facebook — pages

- **Actor ID:** `apify/facebook-pages-scraper`
- **Input shape:**
  ```json
  { "startUrls": [{ "url": "https://facebook.com/<page-name>" }], "resultsLimit": 1 }
  ```
- **Output key fields:** `pageName`, `pageId`, `categories`, `info`
  (description, founded, mission), `likes`, `followers`, `address`, `phone`,
  `email`, `website`, `verified`, `coverPhoto`, `profilePhoto`.
- **Typical cost:** ~$3 per 1k pages.
- **Notes:** Returns the public "About" tab cleanly. If the page hides its
  email, the actor sets `email: null` rather than failing.

### Facebook — page posts

- **Actor ID:** `apify/facebook-posts-scraper`
- **Input shape:**
  ```json
  { "startUrls": [{ "url": "https://facebook.com/<page-name>" }], "resultsLimit": 50 }
  ```
- **Output key fields:** `postId`, `text`, `time`, `url`, `likesCount`,
  `commentsCount`, `sharesCount`, `media` (image/video URLs), `link`
  (outbound), `topReactionsCount`.
- **Typical cost:** ~$3 per 1k posts.
- **Notes:** Reactions breakdown is partial (top 3 only). For pages with
  > 1000 posts, paginate by `resultsLimit` — the actor times out ~10 min.

### Facebook — groups

- **Actor ID:** `apify/facebook-groups-scraper`
- **Input shape:**
  ```json
  { "startUrls": [{ "url": "https://facebook.com/groups/<id>" }], "resultsLimit": 100 }
  ```
- **Output key fields:** `postId`, `text`, `time`, `authorName`, `authorUrl`,
  `commentsCount`, `reactionsCount`, `media`.
- **Typical cost:** ~$4 per 1k posts.
- **Notes:** Public groups only. Closed/private return zero results with
  no error — check `resultsCount` in the run summary, not just exit code.
  `authorUrl` is usable for downstream lookup; `authorName` may be a
  display alias.

### Facebook — personal profile

- **Status:** No reliable Apify actor. Skip to `brightdata scrape` per
  `platforms.md`. `cleansyntax/facebook-profile-posts-scraper` is the
  highest-traffic alternative on the Store (~167 users/30d as of
  2026-04-27) but volume is low — verify currency before relying. The
  earlier `apify/facebook-profile-scraper` slug does not exist.

---

## LinkedIn

### LinkedIn — profile

- **Actor ID:** `harvestapi/linkedin-profile-scraper` (community, no
  cookies; ~5.7k users/30d, verified 2026-04-27). The `apify/`-prefixed
  slug does not exist on the Store.
- **Input shape:**
  ```json
  { "queries": ["https://linkedin.com/in/<handle>"] }
  ```
  Alternative input keys: `urls` (URLs only), `publicIdentifiers`
  (last URL segment), `profileIds` (numeric). `profileScraperMode`
  defaults to the no-email tier; set
  `"profileScraperMode": "Profile details + email search ($10 per 1k)"`
  to enable email lookup (~2× cost).
- **Output key fields:** `fullName`, `headline`, `location`, `currentPosition`,
  `experience` (array: title/company/dates), `education`, `skills`, `about`,
  `connections`, `followers`, `profilePicUrl`, `publicIdentifier`.
- **Typical cost:** ~$5 per 1k profiles (LinkedIn is the most expensive
  surface — proxies cost more here than anywhere else).
- **Notes:** Many community alternatives exist; price/quality varies —
  prefer the one with the most recent successful runs. Returns `null`
  for fields the profile hides. Country-subdomain URLs
  (`uk.linkedin.com/in/...`) work the same as `linkedin.com/in/...`.

### LinkedIn — company page

- **Actor ID:** `harvestapi/linkedin-company` (community, no cookies;
  ~1.3k users/30d, verified 2026-04-27). The `apify/`-prefixed slug does
  not exist on the Store.
- **Input shape:**
  ```json
  { "companies": ["https://linkedin.com/company/<slug>"] }
  ```
  Alternative input key: `searches` (array of company-name strings to
  search on LinkedIn — fuzzy and slower).
- **Output key fields:** `companyName`, `tagline`, `description`, `industry`,
  `headquarters`, `companySize`, `founded`, `specialties`, `website`,
  `followers`, `employeesOnLinkedIn`.
- **Typical cost:** ~$5 per 1k pages.
- **Notes:** `employeesOnLinkedIn` is a count, not a list. To enumerate
  employees, use `apify/linkedin-companies-employees-scraper` (community)
  — much pricier (~$10/1k profiles) and slow.

---

## TikTok

### TikTok — profile

- **Actor ID:** `clockworks/tiktok-profile-scraper` (community, widely used)
- **Input shape:**
  ```json
  { "profiles": ["someone"], "resultsPerPage": 1 }
  ```
- **Output key fields:** `uniqueId`, `nickname`, `signature` (bio),
  `verified`, `followerCount`, `followingCount`, `heartCount` (total likes),
  `videoCount`, `avatarLarger`, `bioLink`, `commerceUserInfo`.
- **Typical cost:** ~$1 per 1k profiles.
- **Notes:** Bio link is single-slot — usually a linktree or the subject's
  primary platform. `commerceUserInfo` indicates a TikTok Shop seller.

### TikTok — videos

- **Actor ID:** `clockworks/tiktok-scraper`
- **Input shape:**
  ```json
  { "profiles": ["someone"], "resultsPerPage": 50, "shouldDownloadVideos": false }
  ```
- **Output key fields:** `id`, `text` (caption), `createTime`, `webVideoUrl`,
  `playCount`, `diggCount` (likes), `shareCount`, `commentCount`,
  `musicMeta`, `hashtags`, `mentions`.
- **Typical cost:** ~$1.50 per 1k videos.
- **Notes:** Keep `shouldDownloadVideos: false` unless you need binaries
  — downloads multiply cost and storage. `text` is the only per-video
  text signal; transcripts require Whisper separately.

### TikTok — comments

- **Actor ID:** `clockworks/tiktok-comments-scraper`
- **Input shape:**
  ```json
  { "postURLs": ["https://tiktok.com/@<handle>/video/<id>"], "commentsPerPost": 100 }
  ```
- **Output key fields:** `cid`, `text`, `createTime`, `diggCount`,
  `replyCommentTotal`, `uid` (commenter id), `uniqueId` (commenter handle).
- **Typical cost:** ~$1 per 1k comments.
- **Notes:** Reply-threads one hop deep; re-scrape by parent id for
  nested replies. Comment text often non-Latin — language detection needed.

---

## YouTube

### YouTube — channel

- **Actor ID:** `apify/youtube-scraper`
- **Input shape:**
  ```json
  { "startUrls": [{ "url": "https://youtube.com/@<handle>" }], "maxResults": 50 }
  ```
- **Output key fields:** `channelName`, `channelUrl`, `subscriberCount`,
  `videoCount`, `viewCount`, `description`, `joinedDate`, `country`,
  `videos` (array of recent uploads with id/title/url/views/duration/date).
- **Typical cost:** ~$5 per 1k results.
- **Notes:** A "result" here = one video. A channel with 1 metadata row +
  50 video rows counts as 51. Set `maxResults` strictly. For just channel
  metadata, set `maxResults: 1` and read the channel-level fields.

### YouTube — video metadata

- **Actor ID:** `apify/youtube-scraper` (same actor) — pass video URLs.
- **Input shape:**
  ```json
  { "startUrls": [{ "url": "https://youtube.com/watch?v=<id>" }] }
  ```
- **Output key fields:** `title`, `viewCount`, `likes`, `commentsCount`,
  `duration`, `date`, `description`, `tags`, `channelName`, `channelUrl`.
- **Typical cost:** ~$5 per 1k videos.
- **Notes:** `description` field carries the full video description (often
  with timestamped chapters and external links — useful for cross-ref).

### YouTube — transcript

- **Actor IDs (two viable, different input shapes):**
  - `pintostudio/youtube-transcript-scraper` — single video at a time:
    ```json
    { "videoUrl": "https://youtube.com/watch?v=<id>", "targetLanguage": "en" }
    ```
  - `topaz_sharingan/Youtube-Transcript-Scraper` — bulk; note the
    capitalised slug:
    ```json
    { "startUrls": ["https://youtube.com/watch?v=<id>"], "timestamps": false }
    ```
  Both verified 2026-04-27. Prefer `topaz_sharingan` for bulk runs;
  `pintostudio` for single-video calls (simpler input).
- **Output key fields:** `videoUrl`, `transcript` (array of `{start, dur,
  text}`) **or** `text` (concatenated string), `language`, `isAutoGenerated`.
- **Typical cost:** ~$0.50 per 1k videos.
- **Notes:** Apify is the most reliable path. Auto-generated captions
  exist for almost every video > 60s; `isAutoGenerated: true` means
  lower fidelity (weight down for psychoprofile). Empty `transcript` =
  captions disabled — fall back per `content-extraction.md` §"YouTube".

---

## Google Maps

### Google Maps — place details

- **Actor ID:** `compass/crawler-google-places`
- **Input shape:**
  ```json
  { "searchStringsArray": ["<query or place name>"], "maxCrawledPlacesPerSearch": 1, "language": "en" }
  ```
- **Output key fields:** `title`, `address`, `phone`, `website`,
  `categoryName`, `categories`, `location` (lat/lng), `placeId`, `cid`,
  `openingHours`, `totalScore` (rating), `reviewsCount`, `imagesCount`,
  `permanentlyClosed`.
- **Typical cost:** ~$7 per 1k places.
- **Notes:** Pass either a search string or a direct Maps URL via
  `startUrls`. For a known business, prefer the URL form — search-string
  matching is fuzzy.

### Google Maps — reviews

- **Actor ID:** `compass/google-maps-reviews-scraper`
- **Input shape:**
  ```json
  { "startUrls": [{ "url": "https://maps.google.com/?cid=<cid>" }], "maxReviews": 200, "reviewsSort": "newest" }
  ```
- **Output key fields:** `reviewId`, `name` (reviewer), `text`, `stars`,
  `publishedAtDate`, `likesCount`, `responseFromOwnerText`,
  `responseFromOwnerDate`, `reviewerUrl`, `reviewerNumberOfReviews`.
- **Typical cost:** ~$3 per 1k reviews.
- **Notes:** Sort by `newest` for recency or `mostRelevant` for signal.
  `reviewerUrl` is a Google Maps contributor profile — usable for
  reverse-lookup of the reviewer's other reviews if the subject is a
  reviewer rather than the reviewed.

---

## X / Twitter

Reality: since the post-2023 API lockdown, every X scraper has been
broken at some point. Community actors often list as "running" but
return partial/stale data. Treat X content as Grade B at best until
cross-referenced. Note when X is the sole source for a claim.

### X — profile

- **Actor ID:** `apidojo/twitter-user-scraper` (community, currently
  the most maintained; verified 2026-04-27).
- **Input shape:**
  ```json
  { "twitterHandles": ["someone"], "maxItems": 100 }
  ```
  Alternative input keys: `startUrls` (full Twitter/X URLs — supports
  profile, tweet, search, list URLs), `searchTerms` (X search queries),
  `twitterUserIds` (numeric IDs).
- **Output key fields:** `userName`, `name`, `description` (bio), `location`,
  `url` (pinned link), `followersCount`, `friendsCount` (following),
  `statusesCount`, `verified`, `isBlueVerified`, `createdAt`, `profileImage`.
- **Typical cost:** ~$0.50 per 1k profiles when working; cost spikes when
  the actor is using paid residential proxies as a workaround.
- **Notes:** Bio often holds the link the subject most wants you to find.
  `isBlueVerified` (paid) is not the same as the legacy `verified`
  (institutional) — distinguish in the dossier.

### X — tweets

- **Actor ID:** `apidojo/tweet-scraper` (community; ~5.2k users/30d,
  verified 2026-04-27).
- **Input shape:**
  ```json
  { "twitterHandles": ["someone"], "maxItems": 100, "sort": "Latest" }
  ```
- **Output key fields:** `id`, `text`, `createdAt`, `url`, `replyCount`,
  `retweetCount`, `likeCount`, `quoteCount`, `viewCount`, `lang`,
  `inReplyToUsername`, `quotedTweet`, `entities` (urls/mentions/hashtags).
- **Typical cost:** ~$0.40 per 1k tweets when working.
- **Notes:** Often returns 0–10% of historical tweets due to pagination
  caps. For deep history, `brightdata scrape` on the profile is sometimes
  better. Nitter via `jina read` is an intermittent third option (see
  `content-extraction.md`).

---

## Telegram

Public Telegram channels are best fetched directly via
`WebFetch https://t.me/s/<channel>` rather than Apify — the `/s/` web
view returns clean HTML with the recent ~20 messages, no auth needed,
no actor cost. Use the actor below only when you need bulk historical
backfill.

### Telegram — public channel bulk

- **Actor ID:** `viralanalyzer/telegram-channel-scraper` (community).
  Low Apify Store traffic (~4 users/30d as of 2026-04-27) — verify
  currency before relying. The earlier `web.harvester/*` and
  `lukaskrivka/*` slugs do not exist on the Store.
- **Input shape:**
  ```json
  { "channels": ["durov"], "maxPostsPerChannel": 200 }
  ```
  `channels` accepts bare usernames or full `https://t.me/<name>` URLs;
  up to 50 per run. `maxPostsPerChannel` is capped at 500.
- **Output key fields:** `messageId`, `date`, `text`, `views`, `forwards`,
  `replyTo`, `media`, `forwardedFrom`, `links`, `mentions`.
- **Typical cost:** ~$2 per 1k messages.
- **Notes:** Public channels only. Private/DM is operator-session
  territory (Phase 2). For < 20 recent messages, prefer
  `WebFetch t.me/s/<channel>` — zero cost, immediate. `forwardedFrom`
  is the strongest signal for the channel's info-graph.

---

## Fallback chains

Restating the Phase 3 rule (`SKILL.md` §"Phase 3"): on the **first** failure
of a primary tool, switch to the fallback. Do not retry the same tool.

| Platform | Primary | Fallback 1 | Fallback 2 |
|---|---|---|---|
| Instagram | `apify call apify/instagram-*` | `brightdata scrape <url>` | — |
| Facebook (page/group) | `apify call apify/facebook-*` | `brightdata scrape <url>` | — |
| Facebook (personal) | `brightdata scrape <url>` | stop, mark gap | — |
| LinkedIn | `apify call harvestapi/linkedin-*` | `brightdata scrape <url>` | `jina read <url>` |
| TikTok | `apify call clockworks/tiktok-*` | `brightdata scrape <url>` | — |
| YouTube (channel/video) | `apify call apify/youtube-scraper` | `jina read <url>` | `brightdata scrape <url>` |
| YouTube (transcript) | `apify call <transcript-actor>` | `whisper` on audio | stop, mark gap |
| Google Maps | `apify call compass/*` | `jina read <url>` | — |
| X / Twitter | `apify call <x-actor>` | `brightdata scrape <url>` | `jina read https://nitter.<mirror>/<handle>` |
| Telegram (public) | `WebFetch t.me/s/<channel>` | `jina read t.me/s/<channel>` | `apify call <telegram-actor>` (bulk only) |

A failure means: non-zero exit code, empty/null `result`, or a
`schema_version` envelope with an explicit `error` field. Partial results
(some fields populated, others null) are **not** failures — log the gaps
and move on.
