# Company Contact Finder (GS1 Kenya Lead Finder)

Type a company name. The app finds the company's website via
[Serper.dev](https://serper.dev), crawls a few pages for public emails, phone
numbers and social profiles, and asks OpenAI for a short company brief.

Leads go into **lead buckets**. A bucket describes the companies you want and
the GS1 Kenya service you'll offer them, and each lead is scored on how well
it fits. See [project.md](project.md) for the full spec.

## Setup

Requires Elixir 1.17+ and PostgreSQL.

Put your keys in `.env` (git-ignored, loaded automatically in dev; see
`.env.example`):

```sh
SERPER_API_KEY=...        # required
OPENAI_API_KEY=...        # optional: without it, lookups finish with no brief
# OPENAI_MODEL=gpt-4.1-mini
```

Then:

```sh
mix setup
mix phx.server
```

Then visit [localhost:4000](http://localhost:4000).

## How it works

```
company name
  -> Search.Serper            Google results via Serper.dev
  -> Search.WebsiteResolver   pick the official site (skip LinkedIn, directories, ...)
  -> Scraper.Crawler          homepage + contact/about pages, robots.txt, SSRF guard
  -> Scraper.Extractor        emails, phones, social links, page text
  -> AI.CompanyAnalyst        brief, contact role/quality, fit + score against the bucket
```

`Leads.Pipeline` runs these steps under `CompanyContactFinder.TaskSupervisor` and
broadcasts progress over PubSub, so the LiveViews update live. Bulk lookups run
a few at a time (`config :company_contact_finder, :lookups, max_concurrency: 3`).

Crawler limits (pages, timeouts, delay, body size) are in `config/config.exs`
under `:scraper`.

## Tests

All HTTP is stubbed with `Req.Test`, so tests make no network calls.

```sh
mix test
mix precommit   # compile with warnings as errors, format, test
```
