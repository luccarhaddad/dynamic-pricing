FROM gradle:8.5-jdk17 AS builder
WORKDIR /app

COPY build.gradle.kts settings.gradle.kts ./
COPY services/event-generator/build.gradle.kts ./services/event-generator/
COPY services/event-generator/src ./services/event-generator/src

RUN gradle :services:event-generator:bootJar --no-daemon

FROM eclipse-temurin:17-jre

RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/services/event-generator/build/libs/*.jar app.jar

EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8082/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
