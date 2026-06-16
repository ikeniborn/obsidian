# Graph Report - .  (2026-06-16)

## Corpus Check
- 75 files · ~0 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 156 nodes · 328 edges · 15 communities (9 shown, 6 thin omitted)
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 35 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_CouchDB & Security Config|CouchDB & Security Config]]
- [[_COMMUNITY_Setup Orchestration|Setup Orchestration]]
- [[_COMMUNITY_Nginx & Relay Infra|Nginx & Relay Infra]]
- [[_COMMUNITY_S3 Upload & Retention|S3 Upload & Retention]]
- [[_COMMUNITY_SSL Certificate Setup|SSL Certificate Setup]]
- [[_COMMUNITY_CouchDB Backup|CouchDB Backup]]
- [[_COMMUNITY_Backup Fix Design Docs|Backup Fix Design Docs]]
- [[_COMMUNITY_CouchDB local.ini|CouchDB local.ini]]
- [[_COMMUNITY_CouchDB Monitoring|CouchDB Monitoring]]
- [[_COMMUNITY_Misc|Misc]]
- [[_COMMUNITY_Misc|Misc]]
- [[_COMMUNITY_Relationship Schema|Relationship Schema]]
- [[_COMMUNITY_Backup Rotation Spec|Backup Rotation Spec]]
- [[_COMMUNITY_Backup Rotation Spec|Backup Rotation Spec]]
- [[_COMMUNITY_local.ini Setting|local.ini Setting]]

## God Nodes (most connected - your core abstractions)
1. `main()` - 23 edges
2. `info()` - 22 edges
3. `success()` - 21 edges
4. `warning()` - 15 edges
5. `Architecture Knowledge Graph Index` - 12 edges
6. `CouchDB Database Component` - 11 edges
7. `error()` - 10 edges
8. `Flexible Network Architecture Pattern` - 9 edges
9. `cleanup_old_objects()` - 9 edges
10. `info()` - 9 edges

## Surprising Connections (you probably didn't know these)
- `ServerPeer Docker Compose Service` --semantically_similar_to--> `ServerPeer Personal Docker Compose Service`  [INFERRED] [semantically similar]
  docker-compose.serverpeer.yml → docker-compose.serverpeer-personal.yml
- `CLAUDE.md Developer Documentation` --semantically_similar_to--> `README User Guide`  [INFERRED] [semantically similar]
  CLAUDE.md → README.md
- `Nostr Relay Docker Compose Service` --references--> `Nostr Relay WebSocket Server`  [INFERRED]
  docker-compose.nostr-relay.yml → docs/architecture/components/infrastructure/nostr-relay.yml
- `ServerPeer Docker Compose Service` --references--> `ServerPeer P2P Client`  [INFERRED]
  docker-compose.serverpeer.yml → docs/architecture/components/infrastructure/serverpeer.yml
- `ServerPeer Docker Compose Service` --rationale_for--> `Localhost-Only Backend Port Binding`  [INFERRED]
  docker-compose.serverpeer.yml → CLAUDE.md

## Hyperedges (group relationships)
- **CouchDB Performance Optimization Group** — local_ini_write_optimization, local_ini_smoosh_compaction, local_ini_query_server [INFERRED 0.85]
- **Backup Safety & Health Check Group** — couchdb_backup_check_disk_space, couchdb_backup_check_container_health, couchdb_backup_calculate_timeout [EXTRACTED 0.95]

## Communities (15 total, 6 thin omitted)

### Community 0 - "CouchDB & Security Config"
Cohesion: 0.09
Nodes (33): Environment Configuration File /opt/notes/.env, CouchDB Database Component, CouchDB require_valid_user Security Enforcement, CouchDB Single-Node Mode, User Request Data Flow, env-file chmod 600 Security Design, fail2ban Backend-Aware Jail Configuration, fail2ban Intrusion Prevention Component (+25 more)

### Community 1 - "Setup Orchestration"
Cohesion: 0.23
Nodes (31): check_existing_env(), check_notes_directory(), command_exists(), configure_couchdb(), configure_docker_proxy(), configure_network(), configure_nginx(), configure_serverpeer() (+23 more)

### Community 2 - "Nginx & Relay Infra"
Cohesion: 0.15
Nodes (24): Architecture Knowledge Graph Index, Architecture Documentation Metadata, CLAUDE.md Developer Documentation, Backup Orchestration System, Certbot (Let's Encrypt SSL), Deployment Orchestration System, Docker Network, Monitoring & Health Check System (+16 more)

### Community 3 - "S3 Upload & Retention"
Cohesion: 0.17
Nodes (12): cleanup_old_objects(), load_env_file(), Load config, create S3 client, run cleanup. Returns True on success., Test S3 connection without uploading, Load environment variables from .env file, Upload file to S3-compatible storage, Delete S3 objects under prefix older than days. Returns count deleted., run_cleanup() (+4 more)

### Community 4 - "SSL Certificate Setup"
Cohesion: 0.49
Nodes (13): create_ufw_hooks(), error(), info(), install_certbot(), log(), main(), obtain_certificate(), setup_auto_renewal() (+5 more)

### Community 5 - "CouchDB Backup"
Cohesion: 0.56
Nodes (7): check_container_health(), check_disk_space(), error_exit(), log(), couchdb-backup.sh script, show_progress(), update_progress()

### Community 6 - "Backup Fix Design Docs"
Cohesion: 0.40
Nodes (6): Backup Rotation Implementation Plan, CouchDB Backup Fix + nginx 500 Fix Implementation Plan, map variable for Connection header prevents HTTP 500: hardcoded 'upgrade' on non-WebSocket requests sends malformed headers to CouchDB/cowboy, Pre-flight auth check in couchdb-backup.sh prevents silently uploading corrupt 401-error JSON to S3 — fail-fast on credential mismatch, Backup Rotation Design Spec, CouchDB useRequestAPI Verification + Backup Fix Design

### Community 7 - "CouchDB local.ini"
Cohesion: 0.40
Nodes (5): HTTP Security Settings, CORS Configuration for Obsidian, CouchDB Core Settings, Smoosh Automatic Compaction, Write Performance Optimization

### Community 8 - "CouchDB Monitoring"
Cohesion: 0.70
Nodes (4): error(), info(), monitor-couchdb.sh script, warning()

## Knowledge Gaps
- **10 isolated node(s):** `Architecture Documentation Metadata`, `CouchDB Optimization Recommendations`, `README User Guide`, `Relationship Types Schema`, `Script Schema Template` (+5 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Flexible Network Architecture Pattern` connect `CouchDB & Security Config` to `Nginx & Relay Infra`?**
  _High betweenness centrality (0.075) - this node is a cross-community bridge._
- **Why does `Docker Network` connect `Nginx & Relay Infra` to `CouchDB & Security Config`?**
  _High betweenness centrality (0.065) - this node is a cross-community bridge._
- **What connects `Architecture Documentation Metadata`, `CouchDB Optimization Recommendations`, `README User Guide` to the rest of the system?**
  _34 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `CouchDB & Security Config` be split into smaller, more focused modules?**
  _Cohesion score 0.09090909090909091 - nodes in this community are weakly interconnected._
- **Should `Nginx & Relay Infra` be split into smaller, more focused modules?**
  _Cohesion score 0.14855072463768115 - nodes in this community are weakly interconnected._