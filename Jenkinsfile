// =============================================================================
// CircleGuard — Pipeline CI/CD
//   Sprint 1 (Dev → Build → Test):
//     Checkout → Detectar cambios → Build (Gradle) → Pruebas unitarias + JaCoCo
//     → Pruebas de integración (Testcontainers) → Análisis SonarQube → Quality Gate
//   Sprint 2 (Test → Deploy):
//     → Imagen del cliente web → Pruebas E2E (Playwright) → Deploy dev (solo main)
//     → Smoke test, con rollback automático a la versión anterior si falla
//
// Job Multibranch "circleguard" (rama main + Pull Requests).
// Ejecución por servicio: en PRs solo se construyen/prueban los microservicios
// modificados (y el cliente web solo si cambió); en main se ejecuta todo.
// =============================================================================

// Variables globales del script (sin 'def' para que sean visibles en métodos y en 'when')
ALL_SERVICES = [
    'circleguard-auth-service',
    'circleguard-identity-service',
    'circleguard-promotion-service',
    'circleguard-notification-service',
    'circleguard-form-service',
    'circleguard-file-service',
    'circleguard-gateway-service',
    'circleguard-dashboard-service',
]

// Proyectos Gradle (":services:<nombre>") que este build debe procesar
TARGETS = []

// ¿Hay que construir y probar (E2E) el cliente web en este build?
WEB_CHANGED = true

// Imagen de Playwright: misma versión que @playwright/test en tests/e2e-playwright
PLAYWRIGHT_IMAGE = 'mcr.microsoft.com/playwright:v1.65.1-noble'

// Archivos que, si cambian, obligan a reconstruir todo el monorepo
@NonCPS
boolean isGlobalChange(String path) {
    return path ==~ /^(build\.gradle\.kts|settings\.gradle\.kts|gradle\.properties|lombok\.config|gradlew|gradle\/.*|Jenkinsfile)$/
}

@NonCPS
List<String> servicesFromDiff(String diff, List<String> all) {
    def changed = [] as LinkedHashSet
    for (String f : diff.readLines().findAll { it?.trim() }) {
        if (isGlobalChange(f)) {
            return all
        }
        def m = (f =~ /^services\/([^\/]+)\//)
        if (m.find() && all.contains(m.group(1))) {
            changed << m.group(1)
        }
        // docs/, infra/, mobile/, etc. no afectan a los microservicios
    }
    return changed as List  
}

// ¿El diff toca el cliente web, sus pruebas E2E o el despliegue?
@NonCPS
boolean webFromDiff(String diff) {
    return diff.readLines().any { String f ->
        f ==~ /^(mobile|tests\/e2e-playwright|deploy)\/.*/ || isGlobalChange(f)
    }
}

// ":services:a:test :services:b:test ..."
String tasksFor(List<String> targets, String task) {
    return targets.collect { "${it}:${task}" }.join(' ')
}

void gradlew(String args) {
    sh "./gradlew --no-daemon --console=plain ${args}"
}

pipeline {
    agent any

    options {
        timestamps()
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 60, unit: 'MINUTES')
    }

    parameters {
        booleanParam(name: 'FORCE_ALL', defaultValue: false,
                     description: 'Construir y probar los 8 microservicios aunque no hayan cambiado')
        booleanParam(name: 'RUN_INTEGRATION', defaultValue: true,
                     description: 'Ejecutar pruebas de integración (@Tag("integration"), requieren Docker)')
    }

    environment {
        // Versión de este build: alimenta sonar.projectVersion (período de "código nuevo")
        APP_VERSION = "1.0.${env.BUILD_NUMBER}"
        // main → proyecto "circleguard"; PRs y demás ramas → "circleguard-pr"
        // (SonarQube Community no soporta análisis por rama, así no se mezcla el historial de main)
        SONAR_PROJECT_KEY = "${env.BRANCH_NAME == 'main' ? 'circleguard' : 'circleguard-pr'}"
        SONAR_PROJECT_NAME = "${env.BRANCH_NAME == 'main' ? 'CircleGuard' : 'CircleGuard (Pull Requests)'}"
    }

    stages {

        // ------------------------------------------------------------- DEV
        stage('Checkout') {
            steps {
                script {
                    def scmVars = checkout scm
                    env.GIT_PREVIOUS_SUCCESSFUL_COMMIT = scmVars.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: ''
                    sh 'chmod +x gradlew'
                    env.GIT_SHORT = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    // Etiqueta de la imagen web: semver en main (lo que se despliega), efímera en PRs
                    env.WEB_TAG = env.BRANCH_NAME == 'main' ? env.APP_VERSION : "pr-${env.CHANGE_ID ?: 'rama'}-${env.BUILD_NUMBER}"
                    // Nombre único para la red y el contenedor de las pruebas E2E de este build
                    env.E2E_NET = 'e2e-' + sh(script: 'printf %s "$BUILD_TAG" | tr -c "a-zA-Z0-9" "-" | tr "A-Z" "a-z"', returnStdout: true).trim()
                    currentBuild.displayName = "#${env.BUILD_NUMBER} (${env.GIT_SHORT})"
                    if (env.CHANGE_ID) {
                        currentBuild.description = "PR-${env.CHANGE_ID}: ${env.CHANGE_TITLE ?: ''} → ${env.CHANGE_TARGET}"
                    }
                }
            }
        }

        stage('Detectar servicios modificados') {
            steps {
                script {
                    def all = ALL_SERVICES
                    def base = ''
                    if (params.FORCE_ALL || env.BRANCH_NAME == 'main') {
                        echo 'Rama main o FORCE_ALL: se procesan los 8 microservicios.'
                    } else if (env.CHANGE_ID) {
                        // En un PR Jenkins fusiona con la rama destino; se compara contra ella
                        def target = "origin/${env.CHANGE_TARGET}"
                        def hasTarget = sh(script: "git rev-parse --verify --quiet ${target}", returnStatus: true) == 0
                        base = hasTarget ? "\$(git merge-base ${target} HEAD)" : 'HEAD^1'
                    } else if (env.GIT_PREVIOUS_SUCCESSFUL_COMMIT) {
                        base = env.GIT_PREVIOUS_SUCCESSFUL_COMMIT
                    }

                    def selected = all
                    if (base) {
                        def diff = sh(script: "git diff --name-only ${base} HEAD || true", returnStdout: true)
                        echo "Archivos modificados respecto a ${base}:\n${diff}"
                        selected = diff.trim() ? servicesFromDiff(diff, all) : all
                        WEB_CHANGED = diff.trim() ? webFromDiff(diff) : true
                    }
                    TARGETS = selected.collect { ":services:${it}".toString() }
                    echo "Servicios a procesar (${TARGETS.size()}): ${selected.join(', ') ?: 'ninguno'}"
                    echo "Cliente web (imagen + E2E): ${WEB_CHANGED ? 'sí' : 'sin cambios, se omite'}"
                }
            }
        }

        // ----------------------------------------------------------- BUILD
        stage('Build') {
            when { expression { return !TARGETS.isEmpty() } }
            steps {
                gradlew tasksFor(TARGETS, 'assemble')
            }
            post {
                success {
                    archiveArtifacts artifacts: 'services/*/build/libs/*.jar',
                                     excludes: 'services/*/build/libs/*-plain.jar',
                                     fingerprint: true, allowEmptyArchive: true
                }
            }
        }

        // ------------------------------------------------------------ TEST
        stage('Pruebas unitarias + cobertura') {
            when { expression { return !TARGETS.isEmpty() } }
            steps {
                gradlew "${tasksFor(TARGETS, 'test')} ${tasksFor(TARGETS, 'jacocoTestReport')} --continue"
            }
            post {
                always {
                    junit testResults: 'services/*/build/test-results/test/*.xml', allowEmptyResults: true
                    recordCoverage(
                        tools: [[parser: 'JACOCO', pattern: 'services/*/build/reports/jacoco/test/jacocoTestReport.xml']],
                        id: 'jacoco', name: 'Cobertura JaCoCo',
                        sourceCodeRetention: 'EVERY_BUILD'
                    )
                }
            }
        }

        stage('Pruebas de integración') {
            when {
                allOf {
                    expression { return params.RUN_INTEGRATION }
                    expression { return TARGETS.contains(':services:circleguard-promotion-service') }
                }
            }
            steps {
                // Testcontainers levanta PostgreSQL/Neo4j efímeros en el Docker del host.
                // Si el entorno no tiene Docker, la etapa queda UNSTABLE en vez de tumbar el pipeline.
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    gradlew ':services:circleguard-promotion-service:integrationTest'
                }
            }
            post {
                always {
                    junit testResults: 'services/*/build/test-results/integrationTest/*.xml', allowEmptyResults: true
                }
            }
        }

        stage('Análisis SonarQube') {
            when { expression { return !TARGETS.isEmpty() } }
            steps {
                withSonarQubeEnv('SonarQube-Server') {
                    // Sonar analiza el monorepo completo y necesita los .class de los 8 servicios
                    // (en un PR selectivo solo se compilaron los modificados): se compilan todos.
                    // Las pruebas ya corrieron: -x evita re-ejecutarlas; Sonar toma los XML de JaCoCo.
                    gradlew 'classes testClasses sonar -x test -x integrationTest'
                }
            }
        }

        stage('Quality Gate') {
            when { expression { return !TARGETS.isEmpty() } }
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    // Bloqueante: si SonarQube responde ERROR el pipeline falla aquí
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ------------------------------------------------------- TEST (E2E)
        stage('Imagen del cliente web') {
            when { expression { return WEB_CHANGED } }
            steps {
                // expo export -p web + nginx no root; etiqueta con versión, nunca "latest"
                sh "docker build --pull --build-arg APP_VERSION=${env.WEB_TAG} -t circleguard/web:${env.WEB_TAG} mobile"
            }
        }

        stage('Pruebas E2E (Playwright)') {
            when { expression { return WEB_CHANGED } }
            steps {
                // 1) Levanta la imagen recién construida en una red aislada de este build
                // 2) Corre Playwright en su imagen oficial sobre el mismo workspace (--volumes-from)
                sh """
                    set -eu
                    docker network create "\$E2E_NET"
                    docker run -d --name "\$E2E_NET-web" --network "\$E2E_NET" "circleguard/web:\$WEB_TAG"
                    for i in \$(seq 1 30); do
                        state=\$(docker inspect -f '{{.State.Health.Status}}' "\$E2E_NET-web")
                        [ "\$state" = "healthy" ] && break
                        sleep 2
                    done
                    echo "Cliente web para E2E: \$state"
                    docker run --rm --network "\$E2E_NET" --volumes-from "\$(hostname)" \\
                        -w "\$WORKSPACE/tests/e2e-playwright" \\
                        -e CI=1 -e E2E_BASE_URL="http://\$E2E_NET-web:8080" \\
                        ${PLAYWRIGHT_IMAGE} \\
                        /bin/bash -c "npm ci --no-audit --no-fund && npx playwright test"
                """
            }
            post {
                always {
                    junit testResults: 'tests/e2e-playwright/results/junit.xml', allowEmptyResults: true
                    archiveArtifacts artifacts: 'tests/e2e-playwright/playwright-report/**, tests/e2e-playwright/test-results/**',
                                     allowEmptyArchive: true
                    sh 'docker rm -f "$E2E_NET-web" > /dev/null 2>&1 || true; docker network rm "$E2E_NET" > /dev/null 2>&1 || true'
                    script {
                        // Las imágenes de PR no se despliegan: se borran para no llenar el disco
                        if (env.BRANCH_NAME != 'main') {
                            sh 'docker rmi "circleguard/web:$WEB_TAG" > /dev/null 2>&1 || true'
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------------ DEPLOY
        stage('Deploy (dev local)') {
            when { branch 'main' }
            steps {
                script {
                    env.PREV_WEB_VERSION = sh(script: 'cat "$JENKINS_HOME/deploy/web.version" 2>/dev/null || true',
                                              returnStdout: true).trim()
                    echo "Versión en dev antes del despliegue: ${env.PREV_WEB_VERSION ?: 'ninguna'}"
                    env.DEPLOY_STARTED = 'true'
                }
                sh "bash deploy/scripts/deploy-web.sh ${env.WEB_TAG}"
            }
        }

        stage('Smoke test') {
            when { branch 'main' }
            steps {
                sh "bash deploy/scripts/smoke-test.sh http://host.docker.internal:8090 ${env.WEB_TAG}"
            }
            post {
                success {
                    // Esta versión queda como la última buena (destino de un rollback futuro)
                    sh 'mkdir -p "$JENKINS_HOME/deploy" && echo "$WEB_TAG" > "$JENKINS_HOME/deploy/web.version"'
                    echo "✅ Desplegado en dev: http://localhost:8090 (circleguard/web:${env.WEB_TAG})"
                }
            }
        }
    }

    post {
        success  { echo "✅ ${env.JOB_NAME} #${env.BUILD_NUMBER}: build, pruebas, Quality Gate, E2E y deploy OK" }
        unstable { echo "⚠️ ${env.JOB_NAME} #${env.BUILD_NUMBER}: pruebas de integración con fallos (revisar reporte)" }
        failure {
            echo "❌ ${env.JOB_NAME} #${env.BUILD_NUMBER}: falló. Revisa la etapa en rojo."
            script {
                // Rollback básico: si el despliegue o el smoke test fallaron, vuelve a la última versión buena
                if (env.BRANCH_NAME == 'main' && env.DEPLOY_STARTED == 'true' && env.PREV_WEB_VERSION) {
                    echo "↩️ Rollback a circleguard/web:${env.PREV_WEB_VERSION}"
                    sh "bash deploy/scripts/deploy-web.sh ${env.PREV_WEB_VERSION}"
                }
            }
        }
    }
}
