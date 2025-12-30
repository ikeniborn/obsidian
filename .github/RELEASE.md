# Release Process Guide

Этот проект использует автоматизированное управление релизами через GitHub Actions.

## Как работает система релизов

### 1. Автоматическое создание релиза

При создании нового тега версии автоматически:
1. Генерируется changelog из commit messages
2. Обновляется файл `CHANGELOG.md`
3. Создается GitHub Release с автогенерированными release notes

### 2. Формат тегов

Используем Semantic Versioning (semver):
- **MAJOR** (v2.0.0) - breaking changes
- **MINOR** (v1.2.0) - новая функциональность (backward compatible)
- **PATCH** (v1.2.1) - bug fixes

## Создание нового релиза

### Способ 1: Автоматический (рекомендуется)

1. **Создайте тег локально:**
   ```bash
   git tag v2.1.0
   git push origin v2.1.0
   ```

2. **GitHub Actions автоматически:**
   - Сгенерирует changelog из коммитов
   - Обновит `CHANGELOG.md`
   - Создаст GitHub Release

### Способ 2: Ручной через GitHub Actions

1. Перейдите: **Actions → Release Management → Run workflow**
2. Введите версию (например, `v2.1.0`)
3. Нажмите **Run workflow**

### Способ 3: Полностью ручной

1. Создайте тег:
   ```bash
   git tag v2.1.0
   git push origin v2.1.0
   ```

2. Создайте release на GitHub:
   - **Releases → Draft a new release**
   - Выберите тег `v2.1.0`
   - GitHub автоматически сгенерирует release notes

## Формат commit messages

Для корректной группировки в changelog используйте префиксы:

### Категории коммитов

| Префикс | Категория | Пример |
|---------|-----------|--------|
| `feat:` | 🚀 New Features | `feat: Add S3 backup support` |
| `fix:` | 🐛 Bug Fixes | `fix: Resolve SSL renewal issue` |
| `perf:` | ⚡ Performance | `perf: Optimize backup script` |
| `refactor:` | 🔧 Refactoring | `refactor: Move scripts to scripts/ directory` |
| `docs:` | 📝 Documentation | `docs: Update installation guide` |
| `chore:` | 🏗️ Infrastructure | `chore: Add GitHub Actions for releases` |
| `security:` | 🔒 Security | `security: Update dependencies` |

### Примеры хороших коммитов

```bash
# Features
git commit -m "feat: Add automated S3 backups with cron scheduling"
git commit -m "feat: Nginx auto-detection and SSL with UFW-aware certbot hooks"

# Bug Fixes
git commit -m "fix: Resolve port conflict in nginx setup"
git commit -m "fix: Correct script paths in deploy.sh"

# Breaking Changes (добавьте BREAKING CHANGE в body)
git commit -m "feat: Restructure scripts directory

BREAKING CHANGE: couchdb-backup.sh moved to scripts/ directory.
Update cron jobs and systemd services to use new path."

# Refactoring
git commit -m "refactor: Move backup script to scripts/ directory"

# Documentation
git commit -m "docs: Update README with new scripts structure"

# Infrastructure
git commit -m "chore: Add GitHub Actions for automated releases"
```

## Labels для Pull Requests

При создании PR добавляйте соответствующие labels для корректной группировки в release notes:

| Label | Описание |
|-------|----------|
| `breaking-change` | ⚠️ Breaking Changes |
| `security` | 🔒 Security |
| `feature` | 🚀 New Features |
| `bug` | 🐛 Bug Fixes |
| `performance` | ⚡ Performance |
| `refactor` | 🔧 Refactoring |
| `documentation` | 📝 Documentation |
| `infrastructure` | 🏗️ Infrastructure |
| `test` | 🧪 Testing |

## Changelog Validation

При создании Pull Request:
- CI проверит наличие изменений в `CHANGELOG.md`
- Если изменений нет, PR получит комментарий с напоминанием

### Обновление CHANGELOG.md вручную

Если нужно добавить entry вручную:

```markdown
## [2.1.0] - 2025-11-17

### 🔧 Refactoring
- Перемещение couchdb-backup.sh в scripts/
- Обновление всех ссылок на скрипт
- Автокопирование скриптов в /opt/notes при deploy

### 🏗️ Infrastructure
- Добавлены GitHub Actions для автоматических релизов
- Добавлен changelog validator для PR

### 📝 Documentation
- Обновлена документация с новой структурой
- Добавлен RELEASE.md guide
```

## Проверка релиза

После создания релиза проверьте:
1. **GitHub Releases** - release создан
2. **CHANGELOG.md** - файл обновлен
3. **Release Notes** - группировка по категориям корректна

## Troubleshooting

### Релиз не создался автоматически

1. Проверьте **Actions → Release Management**
2. Посмотрите логи workflow
3. Убедитесь, что тег имеет формат `v*.*.*`

### Changelog пустой

Причины:
- Нет коммитов между релизами
- Commit messages не имеют правильных префиксов

Решение: Добавьте записи в `CHANGELOG.md` вручную

### Workflow failed

1. Проверьте логи в GitHub Actions
2. Убедитесь, что есть права на создание releases
3. Проверьте формат тега и commit messages

## Примеры

### Создание patch релиза (bug fix)

```bash
# Fix bug
git commit -m "fix: Resolve backup script permissions issue"

# Create tag
git tag v2.0.1
git push origin v2.0.1
```

### Создание minor релиза (new feature)

```bash
# Add feature
git commit -m "feat: Add email notifications for backup failures"

# Create tag
git tag v2.1.0
git push origin v2.1.0
```

### Создание major релиза (breaking change)

```bash
# Breaking change
git commit -m "refactor: Move all scripts to scripts/ directory

BREAKING CHANGE: All scripts moved to scripts/ directory.
Update cron jobs and systemd services to use /opt/notes/scripts/ path."

# Create tag
git tag v3.0.0
git push origin v3.0.0
```

## Версионирование

**Когда увеличивать версию:**

- **PATCH (v2.0.X)**: Bug fixes, documentation updates
- **MINOR (v2.X.0)**: Новая функциональность (backward compatible)
- **MAJOR (vX.0.0)**: Breaking changes, несовместимые изменения

**Текущая версия:** v3.0.0 (см. latest release на GitHub)

---

**См. также:**
- [Semantic Versioning](https://semver.org/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
