# Jenkins controller para CircleGuard
#  - JDK 21
#  - Docker CLI + Compose: Testcontainers, imagen del cliente web, E2E y despliegue (Sprint 2)
#  - Plugins y configuración declarados en código (plugins.txt + casc/jenkins.yaml)
FROM jenkins/jenkins:lts-jdk21

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg git jq \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

COPY casc/ /var/jenkins_casc/
ENV CASC_JENKINS_CONFIG=/var/jenkins_casc/jenkins.yaml \
    JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    GRADLE_USER_HOME=/var/jenkins_home/.gradle

# Se queda como root para poder usar /var/run/docker.sock (Docker-out-of-Docker)
# en Docker Desktop. Es un entorno de laboratorio local; ver docs/ci/README.md.
