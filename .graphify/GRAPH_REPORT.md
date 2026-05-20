# Graph Report - .  (2026-05-20)

## Corpus Check
- Corpus is ~31,253 words - fits in a single context window. You may not need a graph.

## Summary
- 71 nodes · 104 edges · 10 communities (7 shown, 3 thin omitted)
- Extraction: 75% EXTRACTED · 25% INFERRED · 0% AMBIGUOUS · INFERRED: 26 edges (avg confidence: 0.87)
- Token cost: 37,000 input · 6,400 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Security & CouchDB Config|Security & CouchDB Config]]
- [[_COMMUNITY_Core Architecture|Core Architecture]]
- [[_COMMUNITY_Network & Config Patterns|Network & Config Patterns]]
- [[_COMMUNITY_P2P Sync Stack|P2P Sync Stack]]
- [[_COMMUNITY_S3 Backup Upload|S3 Backup Upload]]
- [[_COMMUNITY_Deployment Flow & PRD|Deployment Flow & PRD]]
- [[_COMMUNITY_Documentation|Documentation]]
- [[_COMMUNITY_Image Update Detection|Image Update Detection]]
- [[_COMMUNITY_BuildKit Proxy Workaround|BuildKit Proxy Workaround]]
- [[_COMMUNITY_Schema Definitions|Schema Definitions]]

## God Nodes (most connected - your core abstractions)
1. `Architecture Knowledge Graph Index` - 12 edges
2. `CouchDB Database Component` - 11 edges
3. `Flexible Network Architecture Pattern` - 9 edges
4. `setup.sh Interactive Configuration Script` - 7 edges
5. `deploy.sh Production Deployment Script` - 7 edges
6. `Docker Network` - 6 edges
7. `fail2ban Intrusion Prevention Component` - 6 edges
8. `Full Production Deployment Workflow` - 6 edges
9. `Backup Orchestration System` - 5 edges
10. `UFW Firewall` - 5 edges

## Surprising Connections (you probably didn't know these)
- `S3 Upload Script` --implements--> `S3-Compatible Backup Storage`  [INFERRED]
  scripts/s3_upload.py → docs/architecture/components/infrastructure/s3-storage.yml
- `ServerPeer Docker Compose Service` --semantically_similar_to--> `ServerPeer Personal Docker Compose Service`  [INFERRED] [semantically similar]
  docker-compose.serverpeer.yml → docker-compose.serverpeer-personal.yml
- `README User Guide` --semantically_similar_to--> `CLAUDE.md Developer Documentation`  [INFERRED] [semantically similar]
  README.md → CLAUDE.md
- `Backup Orchestration System` --references--> `S3 Upload Script`  [EXTRACTED]
  docs/architecture/components/application/backup-system.yml → scripts/s3_upload.py
- `Nostr Relay WebSocket Server` --references--> `Nostr Relay Docker Compose Service`  [INFERRED]
  docs/architecture/components/infrastructure/nostr-relay.yml → docker-compose.nostr-relay.yml

## Hyperedges (group relationships)
- **P2P Signaling and Sync Stack** — component_nostr_relay, component_serverpeer, compose_nostr_relay_service, compose_serverpeer_service [INFERRED 0.95]
- **Backup Pipeline: CouchDB → S3** — component_backup_system, s3_upload_script, component_s3_storage [EXTRACTED 1.00]
- **SSL Renewal Coordination: UFW + Certbot + Nginx** — component_ufw_firewall, component_certbot, component_nginx [EXTRACTED 1.00]
- **Three-Script Deployment Pipeline (install → setup → deploy)** — script_install, script_setup, script_deploy [EXTRACTED 1.00]
- **Layered Security Model (UFW static + fail2ban dynamic + CouchDB auth)** — security_firewall_rules, fail2ban_component, couchdb_require_valid_user [INFERRED 0.85]
- **Inbound Request Path (UFW → Nginx → CouchDB)** — security_firewall_rules, dataflow_user_request, couchdb_component [EXTRACTED 1.00]

## Communities (10 total, 3 thin omitted)

### Community 0 - "Security & CouchDB Config"
Cohesion: 0.17
Nodes (16): CouchDB Database Component, CouchDB require_valid_user Security Enforcement, CouchDB Single-Node Mode, fail2ban Backend-Aware Jail Configuration, fail2ban Intrusion Prevention Component, fail2ban UFW Dynamic Rule Injection, PEP 668 Compliant Python Dependency Installation, Python Requirements (boto3) (+8 more)

### Community 1 - "Core Architecture"
Cohesion: 0.24
Nodes (15): Architecture Knowledge Graph Index, Architecture Documentation Metadata, Backup Orchestration System, Certbot (Let's Encrypt SSL), Deployment Orchestration System, Monitoring & Health Check System, Nginx Reverse Proxy, S3-Compatible Backup Storage (+7 more)

### Community 2 - "Network & Config Patterns"
Cohesion: 0.24
Nodes (11): Environment Configuration File /opt/notes/.env, env-file chmod 600 Security Design, Isolated Network Mode Variant, Shared Network Mode Variant, Docker Image Prepull Pattern, Flexible Network Architecture Pattern, Image ID vs Manifest Digest Comparison Strategy, Pattern Schema Template (+3 more)

### Community 3 - "P2P Sync Stack"
Cohesion: 0.31
Nodes (10): Docker Network, Nostr Relay WebSocket Server, ServerPeer P2P Client, CouchDB Docker Compose Service, Nostr Relay Docker Compose Service, ServerPeer Personal Docker Compose Service, ServerPeer Docker Compose Service, /opt/notes/.env Configuration File (+2 more)

### Community 4 - "S3 Backup Upload"
Cohesion: 0.38
Nodes (6): load_env_file(), Load environment variables from .env file, Upload file to S3-compatible storage, Test S3 connection without uploading, test_s3_connection(), upload_to_s3()

### Community 5 - "Deployment Flow & PRD"
Cohesion: 0.33
Nodes (6): User Request Data Flow, Deny-by-Default Firewall Policy, Dual Backend Support Concept (CouchDB + ServerPeer), Graceful Degradation (P2P works offline), Obsidian Sync Server PRD, UFW Firewall Rules Security Configuration

### Community 6 - "Documentation"
Cohesion: 0.67
Nodes (3): CLAUDE.md Developer Documentation, CouchDB Optimization Recommendations, README User Guide

## Knowledge Gaps
- **23 isolated node(s):** `Load environment variables from .env file`, `Upload file to S3-compatible storage`, `Test S3 connection without uploading`, `Architecture Documentation Metadata`, `CouchDB Optimization Recommendations` (+18 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Flexible Network Architecture Pattern` connect `Network & Config Patterns` to `Security & CouchDB Config`, `P2P Sync Stack`, `Deployment Flow & PRD`?**
  _High betweenness centrality (0.426) - this node is a cross-community bridge._
- **Why does `Docker Network` connect `P2P Sync Stack` to `Core Architecture`, `Network & Config Patterns`?**
  _High betweenness centrality (0.375) - this node is a cross-community bridge._
- **Why does `Architecture Knowledge Graph Index` connect `Core Architecture` to `P2P Sync Stack`, `Documentation`?**
  _High betweenness centrality (0.242) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `Flexible Network Architecture Pattern` (e.g. with `Docker Network` and `Pattern Schema Template`) actually correct?**
  _`Flexible Network Architecture Pattern` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Load environment variables from .env file`, `Upload file to S3-compatible storage`, `Test S3 connection without uploading` to the rest of the system?**
  _23 weakly-connected nodes found - possible documentation gaps or missing edges._