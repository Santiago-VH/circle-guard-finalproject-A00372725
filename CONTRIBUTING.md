## Estrategia de ramas: GitHub Flow

Se usó **GitHub Flow**, una sola rama de larga duración (`main`), siempre desplegable, y
ramas cortas por historia de usuario que entran a `main` por Pull Request.

```
main ──●──────────●───────────●──────▶   (protegida)
        \        / \         /
         ●──●──●    ●──●──●─      feature/HU-03-jenkins-pipeline, fix/..., docs/...
```

GitFlow (`develop`, `release/*`,`hotfix/*`) agrega ramas y fusiones que aquí no aportan. 
Trunk-based puro (commits directos a `main`) quitaría el PR, que es justo el punto donde Jenkins y SonarQube bloquean cambios
malos. GitHub Flow mantiene el PR como puerta de calidad con el mínimo de ceremonia.

### Nombres de rama

| Prefijo      | Uso                                     | Ejemplo                           |
|--------------|-----------------------------------------|-----------------------------------|
| `feature/`   | Nueva funcionalidad o historia          | `feature/HU-04-jenkinsfile`       |
| `fix/`       | Corrección de un defecto                | `fix/sonar-hotspot-cors`          |
| `ci/`        | Cambios del pipeline o la infraestructura de CI | `ci/quality-gate`         |
| `docs/`      | Solo documentación                      | `docs/sprint-1-review`            |
| `test/`      | Solo pruebas                            | `test/gateway-qr-coverage`        |

### Flujo de trabajo

1. Crear la rama desde `main` actualizada: `git switch main && git pull && git switch -c feature/HU-xx-descripcion`
2. Hacer commits pequeños con **Conventional Commits** (ver abajo).
3. `git push -u origin <rama>` y abrir un **Pull Request** hacia `main` con título en formato Conventional Commit.
4. Jenkins ejecuta el pipeline sobre el PR (build, pruebas, SonarQube + Quality Gate)
   y reporta el estado en GitHub.
5. Solo se fusiona si el check de Jenkins está en verde. Se usa **Squash and merge**:
   el título del PR (en formato Conventional Commit) queda como el commit en `main`.
6. Borrar la rama después de fusionar.

### Protección de `main` (GitHub → Settings → Branches → Branch protection rule)

- ✅ Require a pull request before merging
- ✅ Require status checks to pass before merging → check `continuous-integration/jenkins/pr-merge`
- ✅ Require branches to be up to date before merging
- ✅ Require conversation resolution before merging
- ✅ Do not allow bypassing the above settings
- ❌ Allow force pushes / ❌ Allow deletions

### Lista de autorrevisión del PR

```markdown
- [ ] Título en formato Conventional Commits
- [ ] `./gradlew test` pasa en local
- [ ] Hay pruebas para el código nuevo
- [ ] No hay credenciales, tokens ni `.env` en el diff
- [ ] Pipeline de Jenkins en verde (build, pruebas, Quality Gate)
- [ ] Issues y hotspots nuevos revisados en SonarQube (`circleguard-pr`)
```

## Conventional Commits

Formato: `<tipo>(<alcance>): <descripción en minúscula, imperativo>`

| Tipo       | Cuándo                                   | Efecto en semver (Sprint 2) |
|------------|------------------------------------------|-----------------------------|
| `feat`     | Nueva funcionalidad                      | MINOR                       |
| `fix`      | Corrección de defecto                    | PATCH                       |
| `feat!` / `BREAKING CHANGE:` | Cambio incompatible    | MAJOR                       |
| `ci`       | Jenkinsfile, infra de CI                 | —                           |
| `build`    | Gradle, dependencias, Dockerfiles        | —                           |
| `test`     | Agregar o corregir pruebas               | —                           |
| `docs`     | Documentación                            | —                           |
| `refactor` | Cambio interno sin cambiar comportamiento | —                          |
| `chore`    | Mantenimiento (gitattributes, etc.)      | —                           |

Alcances sugeridos: `auth`, `identity`, `promotion`, `notification`, `form`, `file`,
`gateway`, `dashboard`, `mobile`, `jenkins`, `sonar`, `infra`.

Ejemplos:

```
ci(jenkins): agrega pipeline multibranch con quality gate bloqueante
build(gradle): integra jacoco y plugin de sonarqube
test(promotion): etiqueta pruebas con testcontainers como integration
fix(gateway): corrige expiracion de QR firmado
```

## Antes de abrir el PR

```bash
./gradlew test                 # pruebas unitarias (sin Docker)
./gradlew integrationTest      # pruebas de integración (requiere Docker)
```
