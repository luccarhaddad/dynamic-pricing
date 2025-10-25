rootProject.name = "dynamic-pricing"

include(
    ":flink-pricing-job",
    ":services:event-generator", 
    ":services:pricing-api"
)