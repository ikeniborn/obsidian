# Graph Report - .  (2026-05-22)

## Corpus Check
- Corpus is ~0 words - fits in a single context window. You may not need a graph.

## Summary
- 101 nodes · 154 edges · 13 communities (10 shown, 3 thin omitted)
- Extraction: 76% EXTRACTED · 24% INFERRED · 0% AMBIGUOUS · INFERRED: 37 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Architecture Docs|Architecture Docs]]
- [[_COMMUNITY_Backup Plans & Rationale|Backup Plans & Rationale]]
- [[_COMMUNITY_S3 Upload Core|S3 Upload Core]]
- [[_COMMUNITY_S3 Cleanup & Tests|S3 Cleanup & Tests]]
- [[_COMMUNITY_Network & Env Config|Network & Env Config]]
- [[_COMMUNITY_Install & Setup Scripts|Install & Setup Scripts]]
- [[_COMMUNITY_Docker Compose Services|Docker Compose Services]]
- [[_COMMUNITY_Request Flow & Security|Request Flow & Security]]
- [[_COMMUNITY_CouchDB Component|CouchDB Component]]
- [[_COMMUNITY_Fail2ban Integration|Fail2ban Integration]]
- [[_COMMUNITY_Image ID Comparison Pattern|Image ID Comparison Pattern]]
- [[_COMMUNITY_BuildKit Prepull Pattern|BuildKit Prepull Pattern]]
- [[_COMMUNITY_Relationship Schema|Relationship Schema]]

## God Nodes (most connected - your core abstractions)
1. `Architecture Knowledge Graph Index` - 12 edges
2. `CouchDB Database Component` - 11 edges
3. `Flexible Network Architecture Pattern` - 9 edges
4. `cleanup_old_objects()` - 9 edges
5. `TestCleanupOldObjects` - 8 edges
6. `setup.sh Interactive Configuration Script` - 7 edges
7. `deploy.sh Production Deployment Script` - 7 edges
8. `cleanup_old_objects()` - 7 edges
9. `load_env_file()` - 6 edges
10. `Docker Network` - 6 edges

## Surprising Connections (you probably didn't know these)
- `S3 Upload Script` --implements--> `S3-Compatible Backup Storage`  [INFERRED]
  scripts/s3_upload.py → docs/architecture/components/infrastructure/s3-storage.yml
- `ServerPeer Docker Compose Service` --semantically_similar_to--> `ServerPeer Personal Docker Compose Service`  [INFERRED] [semantically similar]
  docker-compose.serverpeer.yml → docker-compose.serverpeer-personal.yml
- `Nostr Relay Docker Compose Service` --references--> `Nostr Relay WebSocket Server`  [INFERRED]
  docker-compose.nostr-relay.yml → docs/architecture/components/infrastructure/nostr-relay.yml
- `CLAUDE.md Developer Documentation` --semantically_similar_to--> `README User Guide`  [INFERRED] [semantically similar]
  CLAUDE.md → README.md
- `cleanup_old_objects()` --rationale_for--> `S3 cleanup failure should not fail the backup run — upload success is more critical than rotation`  [EXTRACTED]
  scripts/s3_upload.py → docs/superpowers/specs/2026-05-20-backup-rotation-design.md

## Communities (13 total, 3 thin omitted)

### Community 0 - "Architecture Docs"
Cohesion: 0.2
Nodes (19): Architecture Knowledge Graph Index, Architecture Documentation Metadata, CLAUDE.md Developer Documentation, Backup Orchestration System, Certbot (Let's Encrypt SSL), Deployment Orchestration System, Docker Network, Monitoring & Health Check System (+11 more)

### Community 1 - "Backup Plans & Rationale"
Cohesion: 0.18
Nodes (16): Backup Rotation Implementation Plan, CouchDB Backup Fix + nginx 500 Fix Implementation Plan, S3 delete_objects API max 1000 keys per request — batching required for large prefix cleanups, map variable for Connection header prevents HTTP 500: hardcoded 'upgrade' on non-WebSocket requests sends malformed headers to CouchDB/cowboy, Pre-flight auth check in couchdb-backup.sh prevents silently uploading corrupt 401-error JSON to S3 — fail-fast on credential mismatch, S3 cleanup failure should not fail the backup run — upload success is more critical than rotation, S3 rotation added to s3_upload.py (not couchdb-backup.sh) to keep cleanup reusable across backends and testable in isolation, cleanup_old_objects() (+8 more)

### Community 2 - "S3 Upload Core"
Cohesion: 0.21
Nodes (11): load_env_file(), Load config, create S3 client, run cleanup. Returns True on success., Test S3 connection without uploading, Load environment variables from .env file, Load environment variables from .env file, Upload file to S3-compatible storage, Upload file to S3-compatible storage, Test S3 connection without uploading (+3 more)

### Community 3 - "S3 Cleanup & Tests"
Cohesion: 0.33
Nodes (4): cleanup_old_objects(), Delete S3 objects under prefix older than days. Returns count deleted., Return mock S3 client. Pass None to simulate empty prefix (no Contents key)., TestCleanupOldObjects

### Community 4 - "Network & Env Config"
Cohesion: 0.24
Nodes (11): Environment Configuration File /opt/notes/.env, env-file chmod 600 Security Design, Isolated Network Mode Variant, Shared Network Mode Variant, Docker Image Prepull Pattern, Flexible Network Architecture Pattern, Image ID vs Manifest Digest Comparison Strategy, Pattern Schema Template (+3 more)

### Community 5 - "Install & Setup Scripts"
Cohesion: 0.33
Nodes (7): PEP 668 Compliant Python Dependency Installation, Workflow Schema Template, install.sh Dependency Installation Script, setup.sh Interactive Configuration Script, Backend-Aware S3 Backup Prefix Configuration, Conditional .env Variable Generation per Backend, Full Production Deployment Workflow

### Community 6 - "Docker Compose Services"
Cohesion: 0.47
Nodes (6): CouchDB Docker Compose Service, Nostr Relay Docker Compose Service, ServerPeer Personal Docker Compose Service, ServerPeer Docker Compose Service, /opt/notes/.env Configuration File, Localhost-Only Backend Port Binding

### Community 7 - "Request Flow & Security"
Cohesion: 0.33
Nodes (6): User Request Data Flow, Deny-by-Default Firewall Policy, Dual Backend Support Concept (CouchDB + ServerPeer), Graceful Degradation (P2P works offline), Obsidian Sync Server PRD, UFW Firewall Rules Security Configuration

### Community 8 - "CouchDB Component"
Cohesion: 0.33
Nodes (6): CouchDB Database Component, CouchDB require_valid_user Security Enforcement, CouchDB Single-Node Mode, Python Requirements (boto3), Component Schema Template, couchdb-backup.sh Backup Script

### Community 9 - "Fail2ban Integration"
Cohesion: 0.67
Nodes (3): fail2ban Backend-Aware Jail Configuration, fail2ban Intrusion Prevention Component, fail2ban UFW Dynamic Rule Injection

## Knowledge Gaps
- **34 isolated node(s):** `Load environment variables from .env file`, `Upload file to S3-compatible storage`, `Test S3 connection without uploading`, `Architecture Documentation Metadata`, `CouchDB Optimization Recommendations` (+29 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Flexible Network Architecture Pattern` connect `Network & Env Config` to `Architecture Docs`, `Install & Setup Scripts`, `Request Flow & Security`?**
  _High betweenness centrality (0.292) - this node is a cross-community bridge._
- **Why does `Docker Network` connect `Architecture Docs` to `Network & Env Config`?**
  _High betweenness centrality (0.270) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `Flexible Network Architecture Pattern` (e.g. with `Docker Network` and `Pattern Schema Template`) actually correct?**
  _`Flexible Network Architecture Pattern` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `cleanup_old_objects()` (e.g. with `.test_deletes_objects_older_than_days()` and `.test_keeps_objects_within_retention()`) actually correct?**
  _`cleanup_old_objects()` has 6 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Load environment variables from .env file`, `Upload file to S3-compatible storage`, `Test S3 connection without uploading` to the rest of the system?**
  _34 weakly-connected nodes found - possible documentation gaps or missing edges._