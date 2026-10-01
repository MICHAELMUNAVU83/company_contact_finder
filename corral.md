# Corral — AI-Native B2B Lead Intelligence & Outbound Engine
### Project Specification & Scaffolding Blueprint
**Backend:** FastAPI (Python 3.12+) | **Frontend:** Next.js 15+ (TypeScript, React 19) | **Database:** PostgreSQL 16 + `pgvector`

---

## 1. Executive Summary & Product Vision

**Corral** is an AI-native, multi-tenant B2B Lead Intelligence and Full-Funnel Outbound Acceleration SaaS. It supersedes traditional single-purpose scrapers and generic cold email tools by managing the complete sales pipeline:

1. **Discovery & Deep Crawl**: Product-grounded search via Serper + headless JavaScript scraping via Crawl4AI/Playwright with stealth anti-bot protection.
2. **Waterfall Enrichment**: Multi-tiered contact discovery (scraped pages → B2B waterfall APIs → SMTP verification).
3. **Product Knowledge Base**: Decoupled product onboarding (pitch decks, value propositions, pain points, objection battlecards) stored with vector embeddings for hyper-accurate ICP matching.
4. **Multichannel Sequences**: Rotated email sending pools (preventing domain blacklisting) + LinkedIn soft touches + phone call tasks.
5. **Unified Smart Inbox (Unibox)**: Real-time incoming reply classification (Interested, Objection, OOO, Not Interested) with an AI copilot that pre-drafts contextual replies.
6. **Conversion & ERP Handoff**: Embedded Cal.com scheduling links, automatic meeting detection, and bi-directional synchronization with an external ERP (such as an Elixir Phoenix ERP).

---

## 2. Competitive Benchmarking: Core Decisions

| Feature / Area | Competitor Approach | Corral Architecture Decision |
| :--- | :--- | :--- |
| **Enrichment Depth** | **Clay**: 50+ waterfall enrichment APIs with custom LLM prompts. | **Adopt Clay's Waterfall**: Cascade from free crawl to fallback B2B APIs (Hunter, Dropcontact) and verify via ZeroBounce before queuing. |
| **Deliverability** | **Instantly / Smartlead**: Mailbox rotation across 20+ accounts with automated warmup. | **Adopt Mailbox Pools**: Rotate sending across dedicated Google/Outlook accounts; cap at 30-35 emails/day per inbox with random jitter (2-7 mins). |
| **Sequencing** | **Lemlist / Apollo**: Multichannel steps (Email, LinkedIn, Call tasks). | **Adopt Multichannel Timeline**: Visual sequence builder supporting automated emails, manual LinkedIn tasks, and AI call script generation. |
| **Product Grounding** | **11x / Artisan**: Deep product onboarding before drafting. | **First-Class Product Knowledge Base**: Replaces rigid "lead buckets" with a dedicated repository of offerings, ICP criteria, and objection matrices. |
| **UI / UX Polish** | Traditional CRMs: Clunky, slow, table-heavy, excessive latency. | **Emil Kowalski Design Principles**: Snappy 140ms micro-interactions, `scale(0.97)` active states, `Cmd+K` command bar, and TanStack Virtual tables. |

---

## 3. Core Mental Model: Replacing "Lead Buckets" with Product Knowledge Bases

### Why Drop the Legacy "Lead Bucket" Pattern?
In previous iterations, a "Lead Bucket" conflated the **Product**, the **Target ICP Filter**, and the **Lead List** into one rigid container. Leads could not easily be evaluated against multiple offerings, and editing criteria caused cascading rescore invalidations.

### The Corral Hierarchy
```
┌────────────────────────────────────────────────────────┐
│              ORGANIZATION (Multi-tenant)               │
└───────────────────────────┬────────────────────────────┘
                            │
       ┌────────────────────┼────────────────────┐
       ▼                    ▼                    ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   PRODUCT    │     │    MASTER    │     │  CAMPAIGN    │
│  KNOWLEDGE   │     │   LEAD CRM   │     │  SEQUENCES   │
│     BASE     │     │  (Companies  │     │(Multichannel │
│ (Offerings,  │     │  & Contacts) │     │  Workflows)  │
│ Value Props, │     │              │     │              │
│ Case Studies)│     │              │     │              │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       └─────────────┬──────┴────────────────────┘
                     ▼
       ┌───────────────────────────┐
       │      SMART SEGMENTS       │
       │   Dynamic Filter Views    │
       │ (e.g. "Fit > 80% for P1,  │
       │  Retail, Not Contacted")  │
       └───────────────────────────┘
```

1. **Product Knowledge Base (The Brain)**:
   - Contains Offerings, Target Personas, ICP Firmographics, Value Propositions, Case Studies/Proof Points, and Objection Handling Battlecards.
   - Text documents (PDFs, sales decks) are chunked and vectorized (`pgvector`) for context retrieval during scoring and email drafting.
2. **Master Lead Directory**:
   - A single, deduplicated CRM of Companies and Contacts per Organization.
   - A single company can have multiple dynamic evaluation scores: `FitScore = 94%` for Product A, and `FitScore = 32%` for Product B.
3. **Smart Segments**:
   - Dynamic saved views: *"All Food & Beverage companies in East Africa with verified decision-maker emails and FitScore > 80 for Product A"*.
   - Instant 1-click merging, splitting, and team deduplication.

---

## 4. End-to-End Funnel Architecture

```mermaid
flowchart TD
    A["1. Product Onboarding<br/>(Value Prop, ICP, Battlecards)"] --> B["2. Discovery Search<br/>(Serper Google Search)"]
    B --> C["3. Stealth Web Crawl<br/>(Crawl4AI + Playwright)"]
    C --> D["4. Waterfall Contact Finding<br/>(Regex -> B2B APIs -> ZeroBounce)"]
    D --> E["5. AI Qualification & ICP Scoring<br/>(Grounded in Product KB)"]
    E --> F["6. Multichannel Campaign Sequence<br/>(Mailbox Pool Rotation)"]
    F --> G["7. Unified Smart Inbox (Unibox)<br/>(Sentiment Classification)"]
    G --> H{"Lead Reply Status"}
    H -->|"Interested"| I["AI Copilot Drafts Reply + Cal.com Link"]
    H -->|"Objection"| J["AI Drafts Battlecard Response"]
    H -->|"Not Interested / OOO"| K["Auto-tag & Sequence Paused"]
    I --> L["8. Call Booked (Cal.com Webhook)"]
    L --> M["9. Bi-directional Sync to Phoenix ERP"]
```

### Detailed Stages:
1. **Product Onboarding**: SDR or business owner inputs product specs or drops a pitch deck URL/PDF. AI generates ICP queries, key pain points, and battlecard entries.
2. **Discovery & Crawling**: Queries Serper.dev for directories, rankings, and industry listings. Crawl4AI crawls candidate domains headlessly, bypasses JavaScript challenges, and converts page content to clean, token-efficient Markdown.
3. **Waterfall Enrichment**: 
   - Tier 1: Scrape `mailto:`, contact pages, and footer info.
   - Tier 2: Fallback query to Hunter / Dropcontact API for targeted executive titles (e.g. CEO, Head of Supply Chain).
   - Tier 3: SMTP ping via ZeroBounce / Bouncer API to verify deliverability.
4. **AI ICP Evaluation**: Evaluates crawled Markdown against the Product Knowledge Base using LiteLLM + Instructor to output structured fit scores, reasons, and personalized icebreakers.
5. **Multichannel Sequence**: Scheduled emails dispatch across rotated mailboxes with random delays (2-7 mins) to protect sender reputation.
6. **Unibox & Reply Copilot**: All inbound replies sync via webhooks/IMAP. Gemini 2.5 Flash / Claude 3.5 Haiku classifies sentiment in <2s (`Interested`, `Objection`, `OOO`, `Not Interested`). The AI Copilot drafts a contextual response including the prospect's Cal.com booking link.
7. **Booking & ERP Handoff**: When a meeting is booked, the sequence stops automatically, and an authenticated webhook notifies the parent Phoenix ERP to create an active Deal.

---

## 5. Technology Stack

### Backend (Python 3.12+)
- **API Framework**: **FastAPI** (async native, OpenAPI 3.1, Pydantic v2).
- **ORM & Migrations**: **SQLAlchemy 2.0 (Async)** + **Alembic**.
- **Database**: **PostgreSQL 16** with **`pgvector`** extension.
- **Scraping Engine**: **Crawl4AI** + **Playwright Python** (stealth mode, JS rendering, HTML-to-Markdown).
- **Data Manipulation**: **Polars** (high-speed lead CSV ingestion, cleaning, and deduplication).
- **AI Layer**: **LiteLLM** (model-agnostic wrapper) + **Instructor** (Pydantic-enforced structured outputs).
- **Task Queue & Scheduler**: **ARQ** (Async Redis Queue) or **Celery** with Redis backend.

### Frontend (Next.js 15+ / React 19)
- **Framework**: **Next.js 15 (App Router)** with TypeScript.
- **Styling**: **Tailwind CSS v4** (CSS variables, native imports, zero-runtime).
- **UI Components**: **shadcn/ui** built on **Radix UI Primitives**.
- **Data Fetching & State**: **TanStack Query v5** (optimistic updates) + **Zustand**.
- **Tables & Virtualization**: **TanStack Table v8** + **TanStack Virtual** (smooth 60fps scrolling for 20,000+ leads).
- **Icons & Motion**: **Lucide Icons** + **Framer Motion** (with Emil Kowalski motion constraints).

---

## 6. Complete Database Schema (PostgreSQL DDL)

```sql
-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- 1. Organizations (Multi-tenant)
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Users & Workspace Members
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    role VARCHAR(50) DEFAULT 'member', -- 'owner', 'admin', 'member'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(org_id, email)
);

-- 3. Products / Offerings Knowledge Base
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    tagline VARCHAR(500),
    value_proposition TEXT NOT NULL,
    target_icp JSONB NOT NULL DEFAULT '{}', -- {industries: [], locations: [], sizes: []}
    pain_points JSONB NOT NULL DEFAULT '[]',
    proof_points JSONB NOT NULL DEFAULT '[]',
    objection_matrix JSONB NOT NULL DEFAULT '{}', -- {objection: counter_argument}
    disqualifiers TEXT,
    embedding vector(1536), -- for semantic matching against scraped leads
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Master Companies
CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    domain VARCHAR(255) NOT NULL,
    website_url VARCHAR(1000),
    industry VARCHAR(255),
    locations JSONB DEFAULT '[]',
    employee_count_range VARCHAR(50),
    tech_stack JSONB DEFAULT '[]',
    scraped_markdown TEXT,
    scraped_at TIMESTAMPTZ,
    status VARCHAR(50) DEFAULT 'unverified', -- 'unverified', 'crawled', 'failed'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(org_id, domain)
);

-- 5. Product Fit Evaluations (M:N between Companies and Products)
CREATE TABLE company_product_fits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    fit_score INT CHECK (fit_score BETWEEN 0 AND 100),
    fit_tier VARCHAR(20), -- 'strong', 'moderate', 'weak', 'disqualified'
    executive_summary TEXT,
    pitch TEXT,
    outreach_angle TEXT,
    raw_ai_analysis JSONB,
    evaluated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(company_id, product_id)
);

-- 6. Contacts (Decision Makers & Leads)
CREATE TABLE contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    company_id UUID REFERENCES companies(id) ON DELETE SET NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    email_verification_status VARCHAR(50) DEFAULT 'unverified', -- 'valid', 'catchall', 'invalid'
    phone VARCHAR(50),
    job_title VARCHAR(255),
    linkedin_url VARCHAR(500),
    source VARCHAR(50) DEFAULT 'scraped', -- 'scraped', 'waterfall', 'manual'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(org_id, email)
);

-- 7. Mailbox Sending Pool (Rotation & Deliverability)
CREATE TABLE mailboxes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    display_name VARCHAR(255) NOT NULL,
    smtp_host VARCHAR(255) NOT NULL,
    smtp_port INT NOT NULL,
    smtp_user VARCHAR(255) NOT NULL,
    smtp_pass_encrypted TEXT NOT NULL,
    daily_quota INT DEFAULT 35,
    sent_today INT DEFAULT 0,
    warmup_enabled BOOLEAN DEFAULT TRUE,
    health_score INT DEFAULT 100,
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'paused', 'error'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Campaigns & Sequences
CREATE TABLE campaigns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'draft', -- 'draft', 'active', 'paused', 'completed'
    sequence_steps JSONB NOT NULL DEFAULT '[]', -- [{step: 1, type: 'email', delay_days: 0, subject: '', body: ''}]
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Campaign Enrollments
CREATE TABLE campaign_enrollments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    campaign_id UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    current_step INT DEFAULT 1,
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'paused', 'bounced', 'replied', 'booked'
    next_action_at TIMESTAMPTZ,
    last_sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(campaign_id, contact_id)
);

-- 10. Inbox Threads & Replies (Unified Unibox)
CREATE TABLE inbox_threads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    campaign_id UUID REFERENCES campaigns(id) ON DELETE SET NULL,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    mailbox_id UUID REFERENCES mailboxes(id) ON DELETE SET NULL,
    subject VARCHAR(500),
    snippet TEXT,
    sentiment_label VARCHAR(50), -- 'interested', 'objection', 'ooo', 'not_interested', 'meeting_booked'
    is_read BOOLEAN DEFAULT FALSE,
    ai_draft_reply TEXT,
    last_activity_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. Thread Messages
CREATE TABLE inbox_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id UUID NOT NULL REFERENCES inbox_threads(id) ON DELETE CASCADE,
    direction VARCHAR(20) NOT NULL, -- 'inbound', 'outbound'
    sender_email VARCHAR(255) NOT NULL,
    recipient_email VARCHAR(255) NOT NULL,
    subject VARCHAR(500),
    body_text TEXT NOT NULL,
    body_html TEXT,
    sent_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 7. Repository & Project Directory Structure

```
corral/
├── backend/                        # FastAPI Application
│   ├── app/
│   │   ├── api/
│   │   │   ├── v1/
│   │   │   │   ├── auth.py         # JWT & Tenant authentication
│   │   │   │   ├── products.py     # Product Knowledge Base endpoints
│   │   │   │   ├── discovery.py    # Search, Serper & Crawl triggers
│   │   │   │   ├── leads.py        # Master Companies & Contacts CRM
│   │   │   │   ├── campaigns.py    # Sequence Builder & Enrollment
│   │   │   │   ├── mailboxes.py    # Mailbox Pool & Health
│   │   │   │   ├── unibox.py       # Smart Inbox & Copilot Drafting
│   │   │   │   ├── webhooks.py     # Inbound email & Cal.com webhooks
│   │   │   │   └── erp_sync.py     # Phoenix ERP bi-directional sync
│   │   │   └── router.py
│   │   ├── core/
│   │   │   ├── config.py           # Pydantic Settings
│   │   │   ├── database.py         # Async SQLAlchemy session manager
│   │   │   ├── security.py         # Password hashing & JWT
│   │   │   └── redis.py            # Redis client for caching & queues
│   │   ├── models/                 # SQLAlchemy 2.0 ORM Models
│   │   │   ├── organization.py
│   │   │   ├── product.py
│   │   │   ├── company.py
│   │   │   ├── contact.py
│   │   │   ├── campaign.py
│   │   │   └── unibox.py
│   │   ├── schemas/                # Pydantic v2 Models (DTOs)
│   │   ├── services/               # Core Business Logic
│   │   │   ├── search/             # Serper client & domain resolution
│   │   │   ├── scraper/            # Crawl4AI + Playwright headless engine
│   │   │   ├── enrichment/         # Waterfall B2B API caller & Verifier
│   │   │   ├── ai/                 # LiteLLM, Instructor & Knowledge Base RAG
│   │   │   ├── outreach/           # Email dispatcher & jitter rotator
│   │   │   └── booking/            # Cal.com integration
│   │   └── workers/                # ARQ Async Worker Tasks
│   │       ├── crawl_worker.py
│   │       ├── scoring_worker.py
│   │       └── sequence_worker.py
│   ├── alembic/                    # Database Migrations
│   ├── pyproject.toml              # UV / Poetry dependencies
│   └── main.py                     # ASGI entrypoint
│
├── frontend/                       # Next.js 15 Client
│   ├── src/
│   │   ├── app/
│   │   │   ├── (auth)/             # Login, Signup, Org select
│   │   │   ├── (dashboard)/
│   │   │   │   ├── products/       # Product Knowledge Base studio
│   │   │   │   ├── discovery/      # Search & Live Crawl view
│   │   │   │   ├── leads/          # Virtualized Master CRM Table
│   │   │   │   ├── campaigns/      # Visual Sequence Builder
│   │   │   │   ├── mailboxes/      # Sending Pool health & warmup stats
│   │   │   │   ├── unibox/         # Unified Smart Inbox & Copilot
│   │   │   │   └── settings/       # Team, API keys, Webhooks
│   │   │   ├── api/                # Next.js route handlers
│   │   │   ├── layout.tsx
│   │   │   └── page.tsx
│   │   ├── components/
│   │   │   ├── ui/                 # shadcn/ui primitives
│   │   │   ├── command-menu.tsx    # Cmd+K Global Quick Navigation
│   │   │   ├── leads-table.tsx     # TanStack Virtual table
│   │   │   ├── sequence-flow.tsx   # Visual sequence step builder
│   │   │   └── unibox-pane.tsx     # Split-pane email reader & AI copilot
│   │   ├── hooks/                  # Custom React hooks
│   │   ├── lib/                    # API client, TanStack Query, utils
│   │   └── stores/                 # Zustand state stores
│   ├── tailwind.config.ts
│   └── package.json
│
└── docker-compose.yml              # PostgreSQL + pgvector, Redis, Backend, Frontend
```

---

## 8. Emil Kowalski UI / UX Engineering Standards

To deliver an elite, modern software experience (comparable to Linear, Raycast, and Superhuman), frontend components in Corral follow these rules:

1. **Physical Button Press**:
   ```css
   .button {
     transition: transform 140ms cubic-bezier(0.23, 1, 0.32, 1);
   }
   .button:active {
     transform: scale(0.97);
   }
   ```
2. **Natural Modal / Popover Entrances**:
   - Never animate from `scale(0)` (which feels artificial). Animate from `scale(0.95)` with `opacity: 0` using a 180–220ms `ease-out` curve.
   - Popovers scale from their trigger origin: `transform-origin: var(--transform-origin)`.
3. **Zero-Latency Keyboard Navigation**:
   - `Cmd+K` / `Ctrl+K`: Global command bar opens instantly with zero artificial delay.
   - `J` / `K`: Instantly cycle through Unibox emails without frame drops.
   - `E`: Instant archive with optimistic UI state removal.
4. **Data Density & Typography**:
   - Use tabular figures (`tabular-nums`) for scores, email counts, and metrics to prevent jitter on value updates.
   - Restrained color palette (Zinc neutral foundation) paired with purposeful semantic tokens:
     - `Emerald` for `Interested` / `Verified`.
     - `Amber` for `Objection` / `Catch-all`.
     - `Rose` for `Disqualified` / `Invalid`.

---

## 9. Operating Costs & Unit Economics (Non-AI)

Running Corral requires standard cloud infrastructure, auxiliary domains, mailboxes, and scraping proxies:

| Component | Provider / Setup | MVP Cost (1–5 Orgs) | Growth Cost (50 Orgs) |
| :--- | :--- | :--- | :--- |
| **Backend & Workers** | Railway / Fly.io / AWS ECS | $20 / month | $120 / month |
| **Frontend** | Vercel Pro | $20 / month | $40 / month |
| **PostgreSQL + pgvector**| Neon / Supabase | $25 / month | $100 / month |
| **Redis Cache & Queue** | Upstash / Managed Redis | $10 / month | $30 / month |
| **Google Search API** | Serper.dev ($50 / 50k calls) | ~$10 / month | $60 / month |
| **Rotating Crawl Proxies**| Bright Data / Webshare | $15 / month | $80 / month |
| **Auxiliary Domains** | 3–5 domains on Cloudflare | $4 / month | $20 / month |
| **Mailbox Pool** | 6–10 Google Workspace accounts | $36 / month | $240 / month |
| **Email Verification** | ZeroBounce ($15 / 10k checks) | $15 / month | $60 / month |
| **Meeting Scheduler** | Cal.com API | Free / $0 | $15 / month |
| **Total Non-AI Run Cost**| | **~$155 – $200 / month** | **~$765 / month** |

*Economics*: Charging **$99 – $199 / org / month**, the platform breaks even at just **2 paying clients**, yielding ~85% gross margins.

---

## 10. Scaffolding & Setup Guide

### Step 1: Initialize Database & Services via Docker
```bash
# docker-compose.yml
version: '3.8'
services:
  postgres:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: corral
      POSTGRES_USER: corral_user
      POSTGRES_PASSWORD: corral_password
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

volumes:
  pgdata:
```

### Step 2: Initialize Backend (FastAPI + UV)
```bash
# 1. Install uv (ultra-fast Python package manager)
curl -LsSf https://astral.sh/uv/install.sh | sh

# 2. Initialize project
mkdir backend && cd backend
uv init
uv add fastapi uvicorn[standard] sqlalchemy[asyncio] asyncpg alembic pydantic-settings
uv add crawl4ai playwright litellm instructor polars arq redis
playwright install chromium

# 3. Initialize Alembic for migrations
uv run alembic init -t async alembic
```

### Step 3: Initialize Frontend (Next.js 15 + Tailwind v4 + shadcn)
```bash
# 1. Create Next.js app
npx create-next-app@latest frontend \
  --typescript \
  --tailwind \
  --eslint \
  --app \
  --src-dir \
  --import-alias "@/*"

cd frontend

# 2. Add UI & State packages
npm install @tanstack/react-query @tanstack/react-table @tanstack/react-virtual zustand
npm install lucide-react framer-motion clsx tailwind-merge
npx shadcn@latest init
```

### Step 4: Environment Variables (`.env.example`)
```ini
# Database & Redis
DATABASE_URL=postgresql+asyncpg://corral_user:corral_password@localhost:5432/corral
REDIS_URL=redis://localhost:6379/0

# Search & Scraping
SERPER_API_KEY=your_serper_key
PROXY_POOL_URL=http://user:pass@proxy.brightdata.com:22225

# AI Engine
OPENAI_API_KEY=your_openai_key
ANTHROPIC_API_KEY=your_anthropic_key
DEFAULT_FAST_MODEL=gemini/gemini-2.5-flash
DEFAULT_REASONING_MODEL=claude-3-5-sonnet-20241022

# Lead Enrichment Fallbacks
HUNTER_API_KEY=your_hunter_key
ZEROBOUNCE_API_KEY=your_zerobounce_key

# Calendar & ERP
CAL_API_KEY=your_cal_com_key
PHOENIX_ERP_WEBHOOK_URL=https://erp.yourdomain.com/api/webhooks/corral
PHOENIX_ERP_SECRET=your_hmac_secret
```

---

## 11. Bi-directional Phoenix ERP Integration

When Corral runs alongside an existing Elixir Phoenix ERP:

1. **Authentication (SSO / Token Exchange)**:
   - Phoenix ERP generates a signed HMAC-SHA256 JWT containing `user_id`, `org_id`, and `role`.
   - Next.js reads this token from the parent session or an iframe query parameter, passing it to FastAPI in the `Authorization: Bearer <token>` header.
2. **Opportunity Handoff (Webhook)**:
   - When a lead reaches `sentiment = "meeting_booked"`, FastAPI signs a payload with `PHOENIX_ERP_SECRET` and POSTs it to `PHOENIX_ERP_WEBHOOK_URL`.
   - The Elixir ERP receives the payload, verifies the signature using `Plug.Crypto`, and automatically opens an active CRM deal/opportunity in the ERP database.
