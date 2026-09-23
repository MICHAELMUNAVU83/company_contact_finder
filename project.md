# Company Contact Finder — Project Spec

Codebase: `company_contact_finder` (`CompanyContactFinder` / `CompanyContactFinderWeb`).
Product name in the UI: **GS1 Kenya Lead Finder**, in GS1 blue (`#002C6C`),
GS1 orange (`#F26334`) and white.

## Overview

The app takes a company name, finds the company's official website using the
[Serper.dev](https://serper.dev) Google Search API, then scrapes that website for
publicly listed contact information (emails and phone numbers). It then uses
OpenAI to write a short brief on the company and analyse what was collected.

Leads are organised into **lead buckets**. A bucket describes the companies
GS1 Kenya wants (target description, industries, locations, sizes,
disqualifiers) and the service it will offer them (e.g. GS1 barcodes, GLNs,
traceability). Each lead is scored against its bucket.

## User flow

1. User creates a lead bucket: which leads they want and which service to offer.
2. User enters a company name (or a list) and picks the bucket.
3. The app queries Serper.dev and picks the most likely official website.
4. The app crawls a small set of pages on that domain and extracts contact info.
5. The scraped page text and contacts go to OpenAI, which returns a company
   brief, an analysis of the contacts, and a fit + score against the bucket.
6. Results stream into the UI as they are found and are saved to the database.
7. User can view past lookups and export results to CSV.

## Architecture

Phoenix 1.8 + LiveView, Postgres (Ecto), `Req` for all HTTP calls.

```
lib/company_contact_finder/
  leads.ex                  # Context: create/list/get lookups & contacts
  leads/lookup.ex           # Schema: one search for one company
  leads/contact.ex          # Schema: an extracted email/phone
  leads/company_brief.ex    # Schema: AI-generated brief for a lookup
  search/serper.ex          # Serper.dev API client
  search/website_resolver.ex# Picks the official site from search results
  scraper/crawler.ex        # Fetches pages on the target domain
  scraper/robots.ex         # robots.txt rules
  scraper/url_guard.ex      # URL validation / SSRF guard
  scraper/extractor.ex      # Parses HTML, extracts emails/phones
  ai/openai.ex              # OpenAI API client
  ai/company_analyst.ex     # Builds the prompt, parses the brief/analysis
  leads/pipeline.ex         # Runs search -> crawl -> extract -> brief
  leads/csv_export.ex       # CSV export
lib/company_contact_finder_web/live/
  lookup_live/index.ex      # Search form + history
  lookup_live/show.ex       # Live results for one lookup
```

## 1. Search: Serper.dev

- Endpoint: `POST https://google.serper.dev/search`
- Headers: `X-API-KEY: <key>`, `Content-Type: application/json`
- Body: `{"q": "<company name> official website", "num": 10}`
- API key read from `SERPER_API_KEY` in `config/runtime.exs`. Never commit it.

```elixir
Req.post!("https://google.serper.dev/search",
  headers: [{"x-api-key", api_key}],
  json: %{q: "#{company} official website", num: 10}
)
```

Useful response fields: `knowledgeGraph.website` (best signal when present) and
`organic[].link`.

## 2. Website resolution

Pick the website in this order:

1. `knowledgeGraph.website` if present.
2. Otherwise the first `organic` result whose domain is **not** a directory or
   social site. Maintain a blocklist: `linkedin.com`, `facebook.com`,
   `instagram.com`, `x.com`, `twitter.com`, `wikipedia.org`, `crunchbase.com`,
   `bloomberg.com`, `yelp.com`, `glassdoor.com`, `indeed.com`, `zoominfo.com`, etc.
3. Bonus score for domains containing a normalized form of the company name.

Store the chosen URL and the candidates on the lookup so the user can override
a bad pick and re-run.

## 3. Crawling

- Normalize to the root domain (`https://example.com`).
- Fetch the homepage, then contact-related pages found in homepage links or
  common paths: `/contact`, `/contact-us`, `/about`, `/about-us`, `/team`,
  `/impressum`, `/support`.
- Limits: same domain only, max ~10 pages per lookup, 10s timeout per request,
  follow redirects, max body size ~2 MB.
- Check `robots.txt` and skip disallowed paths.
- SSRF guard (`Scraper.UrlGuard`): every URL and every redirect hop must be
  http(s) and must not resolve to localhost or a private, loopback or
  link-local IP. Redirects are followed manually so each hop is checked.
- Send a clear User-Agent: `GS1KenyaLeadFinder/1.0 (+https://www.gs1kenya.org)`.
- Rate limit: one request at a time per domain, with a small delay between requests.

## 4. Extraction

Parse HTML with `LazyHTML` (already a Phoenix dependency, so no extra package).

**Emails**
- `mailto:` links (most reliable).
- Regex over visible text: `~r/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/`
- Handle simple obfuscation: `name [at] domain [dot] com`, `name(at)domain.com`.
- Drop false positives: image filenames (`logo@2x.png`), `example.com`,
  `sentry.io`/`wixpress.com` tracking addresses.
- Lowercase and dedupe.

**Phone numbers**
- `tel:` links (most reliable).
- Regex over text near keywords like "Phone", "Tel", "Call".
- Normalize to E.164 where possible (optionally `ex_phone_number`).

**Also worth capturing:** social profile links (LinkedIn, Facebook, X) and
physical address if present in the footer or contact page.

For each contact, record the `source_url` it was found on.

## 5. AI brief & analysis (OpenAI)

After crawling, send the cleaned visible text of the crawled pages (homepage,
about and contact pages, trimmed to about 15k characters) plus the extracted
contacts to OpenAI.

- Endpoint: `POST https://api.openai.com/v1/chat/completions`
- Auth: `Authorization: Bearer <OPENAI_API_KEY>`
- Model is configurable (`OPENAI_MODEL`). Use a small, cheap model by default.
- Use **structured outputs** (`response_format: {type: "json_schema", ...}`)
  so the response always parses.

```elixir
Req.post!("https://api.openai.com/v1/chat/completions",
  auth: {:bearer, api_key},
  receive_timeout: 60_000,
  json: %{
    model: model,
    messages: [
      %{role: "system", content: system_prompt},
      %{role: "user", content: page_text_and_contacts}
    ],
    response_format: %{type: "json_schema", json_schema: brief_schema}
  }
)
```

**What the model returns (JSON):**

```json
{
  "summary": "2–4 sentence overview of what the company does",
  "industry": "Logistics",
  "products_services": ["Freight forwarding", "Warehousing"],
  "locations": ["Nairobi, Kenya"],
  "company_size_hint": "small | medium | large | unknown",
  "target_customers": "Who they sell to",
  "contacts_analysis": [
    {"value": "sales@acme.com", "role": "sales", "quality": "high",
     "note": "Listed on contact page as the sales inbox"}
  ],
  "best_contact": "sales@acme.com",
  "lead_score": 0-100,
  "lead_score_reason": "Why this score",
  "outreach_angle": "One suggested talking point for a first message"
}
```

**Rules for the prompt:**
- Answer **only** from the provided page text. Say "unknown" when something
  isn't stated, and never invent contacts, people or numbers.
- Classify each contact: `general | sales | support | hr | person | other`.
  Flag low-quality ones such as `noreply@` addresses or personal Gmail accounts.
- The AI step is optional. If OpenAI fails or no key is set, the lookup still
  finishes with the scraped contacts, and the brief is marked `failed` with a
  retry button.
- Log the model used and token usage on each lookup to track cost.

## 5b. Lead buckets & scoring

A bucket holds:

- `name`
- `target_description`: the kind of company we want (required)
- `industries`, `locations`, `company_sizes` (small | medium | large)
- `service`: the GS1 Kenya service to offer (required). Presets: GS1 barcodes
  (GTINs), GLNs, SSCC logistics labels, traceability, barcode verification,
  GS1 standards training, product data management. Free text is allowed.
- `service_details`: what exactly we'll offer
- `disqualifiers`: who is not a fit (e.g. already GS1 members)

With a bucket, the model returns `fit` (strong | partial | weak | unknown),
`fit_reason` and a `pitch` for the service, and scores 0–100 as roughly:

- 50% fit with the target leads
- 30% likely need for the service (sells physical products through retailers
  or exports, with no sign of already having it)
- 20% reachability (contact quality)

A disqualifier means a weak fit. Without a bucket, the score is a general
lead-quality score.

**Rescoring.** Briefs record `scored_bucket_id` and `scored_at`. A brief is
**stale** if it was scored against another bucket or before the bucket's
`criteria_changed_at`. Renaming a bucket doesn't make scores stale. Moving a
lead to another bucket rescores it automatically. Editing criteria shows an
"Rescore N outdated" button on the bucket (re-uses the stored scraped text, no
re-crawl).

## 6. Data model

```
buckets
  id, name, target_description, industries (array), locations (array),
  company_sizes (array), service, service_details, disqualifiers,
  criteria_changed_at, inserted_at, updated_at

lookups
  id, company_name, query, website_url, candidates (map),
  status (pending | searching | crawling | analysing | done | failed),
  error, website_overridden, pages_crawled, bucket_id (FK, nilify on delete),
  scraped_text (kept so the AI brief can be retried without re-crawling),
  inserted_at, updated_at

company_briefs
  id, lookup_id (FK, unique), summary, industry, products_services (array),
  locations (array), company_size_hint, target_customers, best_contact,
  lead_score, lead_score_reason, outreach_angle, fit, fit_reason, pitch,
  scored_bucket_id, scored_at,
  raw_response (map), model, prompt_tokens, completion_tokens,
  status (pending | done | failed), error, inserted_at, updated_at

contacts
  id, lookup_id (FK), type (email | phone | social),
  value, source_url, role, quality, ai_note, inserted_at
  unique index on (lookup_id, type, value)
```

## 7. Background processing

- Run the pipeline outside the LiveView process: start with `Task.Supervisor`,
  and move to Oban when you need retries or batch jobs.
- Broadcast progress via `Phoenix.PubSub` on `"lookup:#{id}"`. The Show LiveView
  subscribes and updates a stream of contacts.

## 8. UI

- **Index**: company name input, submit button, table of recent lookups with status.
- **Show**: resolved website (editable, with a "re-run" button), live status,
  a **company brief card** (summary, industry, services, locations, lead score
  with its reason, suggested outreach angle), contacts grouped by type with
  AI role/quality badges and source links, and an "Export CSV" button.
- Index table shows the lead score so you can sort the best leads first.
- Bulk mode: paste a list of company names and queue each one.
- Both single and bulk search take an optional bucket.
- **Buckets** (`/buckets`): cards with lead count, strong fits and average score.
- **Bucket form**: a 3-step form (name → which leads → what we offer), with
  service presets.
- **Bucket page**: criteria, "Add companies" (bulk into this bucket), leads
  ranked by score with fit badges and "Outdated" markers, "Rescore", CSV
  export and delete (leads are kept).
- **Lookup page**: a bucket picker (changing it rescores), and the fit badge,
  fit reason and pitch in the brief card.

## 9. Config

```elixir
# config/runtime.exs
config :company_contact_finder, :serper, api_key: System.get_env("SERPER_API_KEY")
config :company_contact_finder, :scraper, max_pages: 10, request_timeout: 10_000
config :company_contact_finder, :openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  model: System.get_env("OPENAI_MODEL")
```

## 10. Testing

- Use `Req.Test` stubs for Serper and site fetches. No real network calls in tests.
- Fixture HTML files in `test/support/fixtures/` for extractor tests (mailto,
  obfuscated emails, tel links, false positives).
- Unit tests for the website resolver's blocklist and scoring.
- `Req.Test` stub for OpenAI. Test that the JSON parses into a brief, and
  that a failed or missing-key call still completes the lookup.
- LiveView tests for the submit → progress → results flow.

## 11. Scope & compliance

- Collect **only publicly published business contact info** (emails, phones,
  social links). The tool must not collect credentials, passwords, or anything
  behind a login.
- Respect `robots.txt` and site terms, and keep crawl volume low.
- Only scraped public page text is sent to OpenAI. Show AI output as
  AI-generated in the UI, since it can be wrong.
- If leads are used for outreach, follow applicable law (GDPR, CAN-SPAM, Kenya
  Data Protection Act, etc.), for example by honoring opt-outs.

## Milestones

1. Serper client + website resolver (with tests).
2. Crawler + extractor (with fixture tests).
3. Schemas, context, migrations.
4. Async pipeline + PubSub.
5. LiveView UI (index + show).
6. OpenAI brief + contact analysis (schema, client, UI card).
7. CSV export (including brief fields), bulk mode, manual website override.
8. GS1 Kenya branding, lead buckets, bucket-based scoring and rescoring.
