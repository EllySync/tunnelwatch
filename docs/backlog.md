# TunnelWatch Norway - Product Backlog

**Product Owner:** You  
**Tech Lead:** AI Assistant  
**Created:** December 6, 2025  
**Target:** MVP - ASAP  

---

## 📊 Epics Overview

| # | Epic | Priority | Stories |
|---|------|----------|---------|
| E1 | Infrastructure Setup | 🔴 Critical | 5 |
| E2 | Data Ingestion | 🔴 Critical | 4 |
| E3 | Web Frontend | 🟡 High | 5 |
| E4 | Notifications | 🟡 High | 4 |
| E5 | Operations | 🟢 Medium | 3 |

---

## 🔴 Epic 1: Infrastructure Setup

*Set up the foundation: Docker, database, and configuration*

### US-1.1: Docker Compose Stack
**As a** developer  
**I want** a working Docker Compose configuration  
**So that** I can start all services with one command  

**Acceptance Criteria:**
- [ ] `docker-compose.yml` defines all 7 services (postgres, redis, php, nginx, worker, beat, signal-api)
- [ ] All containers start with `docker compose up -d`
- [ ] Containers restart automatically on failure
- [ ] Services communicate via internal `tunnelwatch` network
- [ ] Volumes persist data for postgres, redis, signal

**Estimate:** 2 hours

---

### US-1.2: Environment Configuration
**As a** developer  
**I want** a secure environment configuration  
**So that** secrets are not committed to git  

**Acceptance Criteria:**
- [ ] `.env.example` template with all required variables
- [ ] `.gitignore` excludes `.env` and sensitive files
- [ ] Documentation explains each variable
- [ ] Default values work for local development

**Estimate:** 1 hour

---

### US-1.3: PostgreSQL Database Schema
**As a** developer  
**I want** a database schema for tunnels, status updates, and subscriptions  
**So that** data is properly stored and queryable  

**Acceptance Criteria:**
- [ ] `tunnels` table with: id, name, vegvesen_id, coordinates, length, active
- [ ] `status_updates` table with: tunnel_id, status, message, severity, timestamp
- [ ] `subscriptions` table with: phone_number, tunnel_id, active
- [ ] `tunnel_current_status` view for easy querying
- [ ] Indexes on frequently queried columns
- [ ] Automatic `updated_at` triggers

**Estimate:** 2 hours

---

### US-1.4: Seed Data for MVP Tunnels
**As a** developer  
**I want** Mastrafjordtunnelen and Byfjordtunnelen pre-loaded  
**So that** the system monitors them from startup  

**Acceptance Criteria:**
- [ ] Mastrafjordtunnelen: id=`79604497`, correct coordinates
- [ ] Byfjordtunnelen: correct vegvesen_id (find via API)
- [ ] Initial status set to 'open'
- [ ] Seed script runs automatically on first startup

**Estimate:** 1 hour

---

### US-1.5: PHP Application Container
**As a** developer  
**I want** a PHP-FPM container with PostgreSQL support  
**So that** the web frontend can connect to the database  

**Acceptance Criteria:**
- [ ] PHP 8.2 with PDO PostgreSQL extension
- [ ] Composer autoloading configured
- [ ] Connects to postgres container via environment variables
- [ ] Nginx forwards PHP requests correctly

**Estimate:** 2 hours

---

## 🔴 Epic 2: Data Ingestion

*Poll Vegvesen API and detect tunnel status changes*

### US-2.1: Vegvesen API Service
**As a** system  
**I want** to fetch tunnel data from Vegvesen's open API  
**So that** I have real-time tunnel status  

**Acceptance Criteria:**
- [ ] Fetches from `https://fjelloverganger-backend.atlas.vegvesen.no/v1/tunneler`
- [ ] Parses GeoJSON response correctly
- [ ] Handles network errors gracefully (retry, log, continue)
- [ ] Extracts: id, navn, status, statusTungbil, fremtidigStatus, trafikkmeldinger
- [ ] Returns structured Python dict

**Estimate:** 3 hours

---

### US-2.2: Status Mapping Logic
**As a** system  
**I want** to convert API status to internal format  
**So that** statuses are consistent across the application  

**Acceptance Criteria:**
- [ ] Maps `Apen` → `open`
- [ ] Maps `Stengt` → `closed`
- [ ] Maps `Kolonnekjoring` → `restricted`
- [ ] Generates Norwegian message based on status
- [ ] Generates English message based on status
- [ ] Determines severity: high (closed), medium (restricted), low (open)
- [ ] Includes `fremtidigStatus` info if present

**Estimate:** 2 hours

---

### US-2.3: Celery Scheduled Task
**As a** system  
**I want** a task that runs every 60 seconds  
**So that** tunnel status is checked continuously  

**Acceptance Criteria:**
- [ ] Celery beat schedules `check_all_tunnels` every 60 seconds
- [ ] Task fetches API data
- [ ] Compares with last known status in database
- [ ] Only triggers updates/notifications when status changes
- [ ] Logs each check with timestamp

**Estimate:** 2 hours

---

### US-2.4: Database Update on Status Change
**As a** system  
**I want** to record status changes in the database  
**So that** history is preserved  

**Acceptance Criteria:**
- [ ] Inserts new row in `status_updates` when status changes
- [ ] Stores: tunnel_id, status, message (NO), message (EN), severity, timestamp
- [ ] Stores `expected_reopen` if `fremtidigStatus` is present
- [ ] Does NOT insert if status unchanged
- [ ] Logs status changes to console

**Estimate:** 2 hours

---

## 🟡 Epic 3: Web Frontend

*PHP website showing tunnel status with language toggle*

### US-3.1: Homepage with Tunnel Cards
**As a** visitor  
**I want** to see all monitored tunnels with their current status  
**So that** I know which tunnels are open or closed  

**Acceptance Criteria:**
- [ ] Displays card for each active tunnel
- [ ] Shows: tunnel name, status badge, status message, length
- [ ] Color-coded status bar (green=open, red=closed, yellow=restricted)
- [ ] Shows "last updated" time
- [ ] Responsive design (mobile-friendly)
- [ ] Auto-refreshes every 60 seconds

**Estimate:** 3 hours

---

### US-3.2: Language Toggle (NO/EN)
**As a** visitor  
**I want** to switch between Norwegian and English  
**So that** I can read in my preferred language  

**Acceptance Criteria:**
- [ ] Toggle button/dropdown in header
- [ ] Stores preference in cookie/localStorage
- [ ] Translates: page title, status badges, status messages, labels
- [ ] Default language: Norwegian
- [ ] URL stays the same (no `/en/` prefix)

**Estimate:** 3 hours

---

### US-3.3: Status Badge Component
**As a** visitor  
**I want** clear visual status indicators  
**So that** I can quickly see tunnel status  

**Acceptance Criteria:**
- [ ] ✅ Åpen / Open (green badge)
- [ ] 🚫 Stengt / Closed (red badge)
- [ ] ⚠️ Kolonnekjøring / Restricted (yellow badge)
- [ ] ❓ Ukjent / Unknown (gray badge)
- [ ] Emoji + text for accessibility

**Estimate:** 1 hour

---

### US-3.4: JSON API Endpoint
**As a** developer  
**I want** a JSON API endpoint  
**So that** I can fetch tunnel data programmatically  

**Acceptance Criteria:**
- [ ] `GET /api.php` returns JSON
- [ ] Response includes: success, data (array of tunnels), updated_at
- [ ] Each tunnel has: id, name, status, message, length, last_updated
- [ ] Returns 500 with error message on failure
- [ ] CORS headers allow frontend fetch

**Estimate:** 1 hour

---

### US-3.5: CSS Styling with Tailwind
**As a** visitor  
**I want** a clean, modern design  
**So that** the site looks professional  

**Acceptance Criteria:**
- [ ] Uses Tailwind CSS (CDN for MVP)
- [ ] Blue header with logo/title
- [ ] Card grid layout (1 col mobile, 2-3 cols desktop)
- [ ] Custom CSS for status bars and badges
- [ ] Consistent spacing and typography

**Estimate:** 2 hours

---

## 🟡 Epic 4: Notifications

*Signal notifications when tunnel status changes*

### US-4.1: Signal CLI Container
**As a** system  
**I want** Signal CLI running as a REST API  
**So that** I can send Signal messages programmatically  

**Acceptance Criteria:**
- [ ] Uses `bbernhard/signal-cli-rest-api` image
- [ ] Volume persists Signal registration data
- [ ] Accessible at `http://signal-api:8080` from worker
- [ ] Health check confirms container is ready

**Estimate:** 1 hour

---

### US-4.2: Signal Registration Script
**As an** admin  
**I want** a script to register my Signal number  
**So that** the bot can send messages  

**Acceptance Criteria:**
- [ ] `scripts/register-signal.sh` prompts for verification code
- [ ] Sends test message to confirm registration
- [ ] Clear instructions and error handling
- [ ] Works with +47 Norwegian numbers

**Estimate:** 2 hours

---

### US-4.3: Signal Notification Service
**As a** system  
**I want** to send formatted Signal messages  
**So that** subscribers receive tunnel alerts  

**Acceptance Criteria:**
- [ ] Python service calls Signal REST API
- [ ] Formats message: emoji + tunnel name + status + message + time
- [ ] Sends to multiple recipients in one call
- [ ] Handles API errors gracefully
- [ ] Logs success/failure

**Message format:**
```
🚫 Mastrafjordtunnelen

Status: STENGT
Info: Tunnelen er stengt

TunnelWatch - 14:30
```

**Estimate:** 2 hours

---

### US-4.4: Add Subscription Script
**As an** admin  
**I want** a script to add phone numbers to tunnel subscriptions  
**So that** people receive notifications  

**Acceptance Criteria:**
- [ ] `scripts/add-subscription.sh +47XXXXXXXX tunnel-id`
- [ ] Inserts/updates subscription in database
- [ ] Shows confirmation message
- [ ] Lists available tunnels if wrong ID given

**Estimate:** 1 hour

---

## 🟢 Epic 5: Operations

*Scripts and tools for running the service*

### US-5.1: Makefile Commands
**As a** developer  
**I want** simple make commands  
**So that** common tasks are easy to run  

**Acceptance Criteria:**
- [ ] `make up` - Start all services
- [ ] `make down` - Stop all services
- [ ] `make logs` - Tail logs
- [ ] `make restart` - Restart services
- [ ] `make build` - Rebuild containers

**Estimate:** 1 hour

---

### US-5.2: Database Backup Script
**As an** admin  
**I want** to backup the database  
**So that** I can recover from data loss  

**Acceptance Criteria:**
- [ ] `scripts/backup-db.sh` creates timestamped backup
- [ ] Compresses with gzip
- [ ] Supports custom backup path via env var
- [ ] Optional: delete backups older than X days

**Estimate:** 1 hour

---

### US-5.3: Health Check Endpoint
**As an** admin  
**I want** to know if the service is healthy  
**So that** I can monitor uptime  

**Acceptance Criteria:**
- [ ] `GET /health.php` returns JSON status
- [ ] Checks: database connection, last status update time
- [ ] Returns 200 if healthy, 500 if not
- [ ] Includes timestamp

**Estimate:** 1 hour

---

## 📅 Sprint Plan (Suggested)

### Sprint 1: Foundation (Day 1-2)
- US-1.1: Docker Compose Stack
- US-1.2: Environment Configuration
- US-1.3: PostgreSQL Database Schema
- US-1.4: Seed Data for MVP Tunnels
- US-1.5: PHP Application Container

### Sprint 2: Data Pipeline (Day 2-3)
- US-2.1: Vegvesen API Service
- US-2.2: Status Mapping Logic
- US-2.3: Celery Scheduled Task
- US-2.4: Database Update on Status Change

### Sprint 3: Frontend (Day 3-4)
- US-3.1: Homepage with Tunnel Cards
- US-3.2: Language Toggle (NO/EN)
- US-3.3: Status Badge Component
- US-3.4: JSON API Endpoint
- US-3.5: CSS Styling with Tailwind

### Sprint 4: Notifications & Launch (Day 4-5)
- US-4.1: Signal CLI Container
- US-4.2: Signal Registration Script
- US-4.3: Signal Notification Service
- US-4.4: Add Subscription Script
- US-5.1: Makefile Commands
- US-5.2: Database Backup Script
- US-5.3: Health Check Endpoint

---

## ✅ Definition of Done

A story is complete when:
- [ ] Code is written and works locally
- [ ] Tested manually (happy path + error cases)
- [ ] No hardcoded secrets
- [ ] Logs appropriate information
- [ ] Documented if needed (README, comments)

---

## 🚀 Post-MVP Backlog (Future)

*Not in scope for MVP, but tracked for later:*

- [ ] Self-service subscription via website
- [ ] Email notifications
- [ ] SMS notifications (Twilio)
- [ ] Historical status chart/graph
- [ ] More tunnels (user can add via UI)
- [ ] Mobile app (PWA)
- [ ] Admin dashboard
- [ ] Cloudflare tunnel setup automation
- [ ] Automated testing (unit + integration)
- [ ] CI/CD pipeline

---

**Ready to start Sprint 1?** 🚀
