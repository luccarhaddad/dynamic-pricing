plugins {
    java
    id("org.springframework.boot") version "3.3.4" apply false
    id("io.spring.dependency-management") version "1.1.6" apply false
    id("com.github.johnrengelman.shadow") version "8.1.1" apply false
}

allprojects {
    group = "com.pricing"
    version = "1.0.0"

    repositories {
        mavenCentral()
        maven {
            url = uri("https://repository.apache.org/content/repositories/snapshots/")
            mavenContent {
                snapshotsOnly()
            }
        }
    }
}

subprojects {
    apply(plugin = "java")

    java {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(17))
        }
    }

    dependencies {
        implementation("org.slf4j:slf4j-api:2.0.9")
        implementation("ch.qos.logback:logback-classic:1.4.14")
        
        testImplementation("org.junit.jupiter:junit-jupiter:5.10.1")
        testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    }

    tasks.withType<Test> {
        useJUnitPlatform()
    }

    tasks.withType<JavaCompile> {
        options.encoding = "UTF-8"
        options.compilerArgs.addAll(listOf("-parameters", "-Xlint:deprecation"))
    }
}