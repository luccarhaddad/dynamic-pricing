FROM gradle:8.5-jdk17 AS builder
WORKDIR /app

COPY build.gradle.kts settings.gradle.kts ./
COPY flink-pricing-job/build.gradle.kts ./flink-pricing-job/

COPY flink-pricing-job/src ./flink-pricing-job/src

RUN gradle :flink-pricing-job:shadowJar --no-daemon

FROM eclipse-temurin:17-jre

RUN apt-get update && \
    apt-get install -y --no-install-recommends wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/flink-pricing-job/build/libs/*.jar app.jar

ENTRYPOINT ["java", "--add-opens", "java.base/java.lang=ALL-UNNAMED", "-jar", "app.jar"]

