// =============================================================================
// CircleGuard — Pipeline CI (Sprint 1: Dev → Build → Test)
//
// Job Multibranch "circleguard" (rama main + Pull Requests).
//   Checkout → Detectar cambios → Build (Gradle) → Pruebas unitarias + JaCoCo
//   → Pruebas de integración (Testcontainers) → Análisis SonarQube → Quality Gate
//
// Ejecución por servicio: en PRs solo se construyen/prueban los microservicios
// modificados.
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
                    }
                    TARGETS = selected.collect { ":services:${it}".toString() }
                    echo "Servicios a procesar (${TARGETS.size()}): ${selected.join(', ') ?: 'ninguno'}"
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
                    // Las pruebas ya corrieron: -x evita re-ejecutarlas; Sonar toma los XML de JaCoCo
                    gradlew 'sonar -x test -x integrationTest'
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
    }

    post {
        success  { echo "✅ ${env.JOB_NAME} #${env.BUILD_NUMBER}: build, pruebas y Quality Gate OK" }
        unstable { echo "⚠️ ${env.JOB_NAME} #${env.BUILD_NUMBER}: pruebas de integración con fallos (revisar reporte)" }
        failure  { echo "❌ ${env.JOB_NAME} #${env.BUILD_NUMBER}: falló. Revisa la etapa en rojo." }
    }
}
