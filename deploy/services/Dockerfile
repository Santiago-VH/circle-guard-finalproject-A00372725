# Imagen genérica para los microservicios Spring Boot de CircleGuard.
# No compila: empaqueta el bootJar que ya generó Gradle (./gradlew bootJar).
# Contexto de build = carpeta del servicio, p. ej.:
#   docker build -f deploy/services/Dockerfile -t circleguard/auth:dev services/circleguard-auth-service
FROM eclipse-temurin:21-jre

ARG SERVICE_PORT=8080
ENV SERVICE_PORT=${SERVICE_PORT} \
    JAVA_TOOL_OPTIONS="-Xmx256m -XX:+UseSerialGC"

RUN groupadd --system app && useradd --system --gid app --no-create-home app
WORKDIR /app
# *-SNAPSHOT.jar es el bootJar ejecutable (el "-plain.jar" queda fuera del patrón)
COPY build/libs/*-SNAPSHOT.jar app.jar
USER app

EXPOSE ${SERVICE_PORT}
# Ninguno de los servicios trae Actuator: el healthcheck comprueba que Tomcat
# ya está aceptando conexiones en el puerto del servicio.
HEALTHCHECK --interval=10s --timeout=3s --start-period=40s --retries=12 \
  CMD bash -c "exec 3<>/dev/tcp/127.0.0.1/${SERVICE_PORT}" || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
