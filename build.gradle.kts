plugins {
    id("org.springframework.boot") version "3.2.4" apply false
    id("io.spring.dependency-management") version "1.1.4" apply false
    kotlin("jvm") version "1.9.24" apply false
    kotlin("plugin.spring") version "1.9.24" apply false
    kotlin("plugin.jpa") version "1.9.24" apply false
    // CI: análisis estático con SonarQube (tarea `./gradlew sonar`)
    id("org.sonarqube") version "5.1.0.4882"
}

allprojects {
    group = "com.circleguard"
    version = "1.0.0-SNAPSHOT"

    repositories {
        mavenCentral()
    }
}

// -----------------------------------------------------------------------------
// SonarQube: un solo proyecto con los 8 microservicios como módulos.
// La URL y el token los inyecta Jenkins (withSonarQubeEnv); nada sensible aquí.
// -----------------------------------------------------------------------------
sonar {
    properties {
        property("sonar.projectKey", System.getenv("SONAR_PROJECT_KEY") ?: "circleguard")
        property("sonar.projectName", System.getenv("SONAR_PROJECT_NAME") ?: "CircleGuard")
        property("sonar.projectVersion", System.getenv("APP_VERSION") ?: version.toString())
        property("sonar.sourceEncoding", "UTF-8")
        // Clases de arranque y configuración no aportan lógica a cubrir con pruebas unitarias
        property(
            "sonar.coverage.exclusions",
            "**/*Application.java,**/config/**,**/dto/**"
        )
    }
}

subprojects {
    apply(plugin = "java")
    apply(plugin = "org.jetbrains.kotlin.jvm")
    apply(plugin = "jacoco")

    extensions.configure<JavaPluginExtension> {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(21))
        }
    }

    dependencies {
        "implementation"(platform("org.springframework.boot:spring-boot-dependencies:3.2.4"))
        "testImplementation"(platform("org.springframework.boot:spring-boot-dependencies:3.2.4"))
        "compileOnly"("org.projectlombok:lombok")
        "annotationProcessor"("org.projectlombok:lombok")
        "testCompileOnly"("org.projectlombok:lombok")
        "testAnnotationProcessor"("org.projectlombok:lombok")
        "implementation"("org.jetbrains.kotlin:kotlin-reflect")
        "testImplementation"("org.springframework.boot:spring-boot-starter-test")
        "testRuntimeOnly"("com.h2database:h2")
    }

    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile> {
        kotlinOptions {
            freeCompilerArgs = listOf("-Xjsr305=strict")
            jvmTarget = "21"
        }
    }

    extensions.configure<JacocoPluginExtension> {
        toolVersion = "0.8.12"
    }

    // -------------------------------------------------------------------------
    // Pruebas unitarias: todo lo que NO esté etiquetado @Tag("integration").
    // Corren en cada build sin depender de Docker ni de middleware.
    // -------------------------------------------------------------------------
    tasks.named<Test>("test") {
        useJUnitPlatform {
            excludeTags("integration")
        }
        finalizedBy("jacocoTestReport")
    }

    // -------------------------------------------------------------------------
    // Pruebas de integración: @Tag("integration") (Testcontainers, requieren Docker).
    // ./gradlew integrationTest
    // -------------------------------------------------------------------------
    val sourceSets = extensions.getByType<SourceSetContainer>()
    tasks.register<Test>("integrationTest") {
        description = "Pruebas de integración (@Tag(\"integration\"), requieren Docker)."
        group = "verification"
        testClassesDirs = sourceSets["test"].output.classesDirs
        classpath = sourceSets["test"].runtimeClasspath
        useJUnitPlatform {
            includeTags("integration")
        }
        shouldRunAfter("test")
    }

    tasks.named<JacocoReport>("jacocoTestReport") {
        dependsOn("test")
        reports {
            xml.required.set(true)   // lo consume SonarQube
            html.required.set(true)  // lo publica Jenkins
        }
    }
}
