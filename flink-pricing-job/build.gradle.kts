plugins {
    application
    id("com.github.johnrengelman.shadow")
}

val flinkVersion = "1.17.2"
val kafkaVersion = "3.9.0"
val postgresqlVersion = "42.7.4"

dependencies {
    // Flink Core - need to be included for standalone execution
    implementation("org.apache.flink:flink-streaming-java:$flinkVersion")
    implementation("org.apache.flink:flink-clients:$flinkVersion")

    // Flink Connectors - packaged with application
    implementation("org.apache.flink:flink-connector-kafka:$flinkVersion")
    implementation("org.apache.flink:flink-connector-jdbc:1.16.3")

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

    // Exclude conflicting files
    exclude("META-INF/*.SF", "META-INF/*.DSA", "META-INF/*.RSA")
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