# Build stage
FROM gradle:8.5-jdk17 AS builder
WORKDIR /app

COPY build.gradle.kts settings.gradle.kts ./
COPY flink-pricing-job/build.gradle.kts ./flink-pricing-job/
RUN gradle :flink-pricing-job:dependencies --no-daemon || true

COPY flink-pricing-job/src ./flink-pricing-job/src
RUN gradle :flink-pricing-job:shadowJar --no-daemon

# Download S3 plugin JARs for Flink filesystem plugin
RUN mkdir -p /tmp/flink-plugins/s3-fs-hadoop && \
    cd /tmp/flink-plugins/s3-fs-hadoop && \
    curl -L -o flink-s3-fs-hadoop-1.17.2.jar \
      https://repo.maven.apache.org/maven2/org/apache/flink/flink-s3-fs-hadoop/1.17.2/flink-s3-fs-hadoop-1.17.2.jar

# Runtime stage - Use official Flink image
FROM flink:1.17.2

# Install S3 filesystem plugin
# Flink plugins must be in /opt/flink/plugins/<plugin-name>/ directory
RUN mkdir -p /opt/flink/plugins/s3-fs-hadoop
COPY --from=builder /tmp/flink-plugins/s3-fs-hadoop/*.jar /opt/flink/plugins/s3-fs-hadoop/

# Copy our application JAR
COPY --from=builder /app/flink-pricing-job/build/libs/*.jar /opt/flink/usrlib/pricing-job.jar
