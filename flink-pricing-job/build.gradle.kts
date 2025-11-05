plugins {
    application
    id("com.github.johnrengelman.shadow")
}

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

val flinkVersion = "1.17.2"
val kafkaVersion = "3.9.0"
val postgresqlVersion = "42.7.4"
val hadoopVersion = "3.3.4"

dependencies {
    // Flink Core - need to be included for standalone execution
    implementation("org.apache.flink:flink-streaming-java:$flinkVersion")
    implementation("org.apache.flink:flink-clients:$flinkVersion")

    // Flink Connectors - packaged with application
    implementation("org.apache.flink:flink-connector-kafka:$flinkVersion")
    implementation("org.apache.flink:flink-connector-jdbc:1.16.3")

    // S3 FileSystem Support for checkpoints
    compileOnly("org.apache.flink:flink-s3-fs-hadoop:$flinkVersion")

    // Kafka & Serialization
    implementation("org.apache.kafka:kafka-clients:$kafkaVersion")
    implementation("com.fasterxml.jackson.core:jackson-databind:2.17.2")
    implementation("com.fasterxml.jackson.datatype:jackson-datatype-jsr310:2.17.2")

    // Database
    runtimeOnly("org.postgresql:postgresql:$postgresqlVersion")

    // JSON Schema validation (optional for future use)
    implementation("com.github.java-json-tools:json-schema-validator:2.2.14")

    // Test dependencies
    testImplementation("org.apache.flink:flink-test-utils:$flinkVersion")
    testImplementation("org.apache.flink:flink-runtime:$flinkVersion:tests")
    testImplementation("org.apache.flink:flink-streaming-java:$flinkVersion:tests")
}

application {
    mainClass.set("com.pricing.flink.PricingJobMain")
}

tasks.shadowJar {
    archiveClassifier.set("")
    mergeServiceFiles()

    isZip64 = true
    exclude("META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA")
    
    // Exclude S3 filesystem plugin classes - loaded as Flink plugin instead
    // This prevents class loading conflicts between shaded JAR and plugin JAR
    exclude("org/apache/flink/fs/s3/**")
    exclude("org/apache/flink/fs/s3hadoop/**")
    exclude("org/apache/flink/fs/s3common/**")
}

// Fix task dependencies for shadowJar
tasks.named("distZip") {
    dependsOn("shadowJar")
}

tasks.named("distTar") {
    dependsOn("shadowJar")
}

tasks.named("startScripts") {
    dependsOn("shadowJar")
}

tasks.named("startShadowScripts") {
    dependsOn("jar")
}

tasks.named("run") {
    dependsOn("shadowJar")
}