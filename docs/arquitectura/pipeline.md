# Arquitectura del pipeline CI/CD

## Flujo de un cambio (Sprint 1 + Sprint 2)

```mermaid
flowchart LR
    dev([Desarrollador]) -->|git push rama| gh[(GitHub)]
    gh -->|PR hacia main| gh
    gh -.->|escaneo cada 1 min<br/>o webhook vía ngrok| jk

    subgraph jk[Jenkins · job Multibranch 'circleguard']
        direction LR
        c[Checkout] --> d[Detectar servicios<br/>y cliente web modificados]
        d --> b[Build<br/>gradle assemble]
        b --> u[Pruebas unitarias<br/>+ JaCoCo]
        u --> i[Pruebas integración<br/>Testcontainers]
        i --> s[Análisis<br/>SonarQube]
        s --> q{Quality Gate}
        q -->|OK| w[Imagen cliente web<br/>circleguard/web:versión]
        w --> e{E2E Playwright}
        e -->|OK y rama main| dp[Deploy dev<br/>docker compose]
        dp --> sm{Smoke test}
    end

    s -->|reporte| sq[(SonarQube<br/>circleguard / circleguard-pr)]
    sq -->|webhook resultado| q
    sm -->|OK| ok[✅ dev actualizado<br/>localhost:8090]
    sm -->|falla| rb[↩️ Rollback a la<br/>última versión buena]
    q -->|ERROR| ko[❌ PR bloqueado]
    e -->|falla| ko
    jk -->|commit status| gh
```

En un PR el pipeline termina en las pruebas E2E: el check queda en verde o bloquea el merge.
Solo `main` despliega.

## Infraestructura local (Docker Desktop)

```mermaid
flowchart TB
    subgraph host[PC · Docker Desktop]
        subgraph ci[red circleguard-ci]
            jenkins[cg-jenkins :8080<br/>JDK 21 · JCasC · Docker CLI + Compose]
            sonar[cg-sonarqube :9000<br/>10.7 community]
            db[(cg-sonar-db<br/>PostgreSQL 16)]
        end
        subgraph e2e[red efímera e2e-‹build›]
            webtmp[cliente web<br/>imagen del build]
            pw[Playwright<br/>mcr.microsoft.com/playwright]
        end
        subgraph dev[proyecto circleguard-dev]
            web[circleguard-web :8090<br/>nginx no root]
        end
        sock[/docker.sock/]
        tc[[contenedores efímeros<br/>Testcontainers]]
    end
    jenkins -->|análisis| sonar
    sonar -->|webhook| jenkins
    sonar --> db
    jenkins -->|Docker CLI| sock
    sock --> tc
    sock --> e2e
    sock --> dev
    pw -->|pruebas| webtmp
    jenkins -->|smoke test| web
```

| Fase DevOps | Herramienta | Evidencia |
|-------------|-------------|-----------|
| Dev | Git + GitHub (GitHub Flow, Conventional Commits, `main` protegida) | PRs, historial |
| Build | Gradle 8.14 (wrapper), Java 21 · Docker (imagen web multi-stage) | JARs archivados, imagen `circleguard/web:<versión>` |
| Test | JUnit 5, Mockito, Testcontainers, JaCoCo · Playwright | Reportes JUnit, cobertura, reporte HTML de Playwright |
| Test (calidad) | SonarQube + Quality Gate bloqueante | Proyecto `circleguard` |
| Deploy | Docker Compose + smoke test + rollback | Contenedor `circleguard-web` en http://localhost:8090 |
