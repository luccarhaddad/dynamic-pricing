FROM gradle:8.5-jdk17 AS builder
WORKDIR /app

COPY build.gradle.kts settings.gradle.kts ./
COPY services/pricing-api/build.gradle.kts ./services/pricing-api/
COPY services/pricing-api/src ./services/pricing-api/src

RUN gradle :services:pricing-api:bootJar --no-daemon

FROM eclipse-temurin:17-jre

RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/services/pricing-api/build/libs/*.jar app.jar

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8081/api/v1/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
