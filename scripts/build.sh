#!/bin/bash
# build.sh - Build operations
#
# Usage:
#   ./scripts/build.sh all     - Build everything (API, Generator, Flink job)
#   ./scripts/build.sh flink   - Build Flink job only
#   ./scripts/build.sh api     - Build Pricing API only
#   ./scripts/build.sh gen     - Build Event Generator only
#   ./scripts/build.sh clean   - Clean build artifacts

set -e
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Build all projects
#######################################
build_all() {
    echo -e "${BLUE}🔨 Building All Projects${NC}"
    echo "=========================================="
    
    echo -e "\n${YELLOW}Building:${NC}"
    echo "  • Pricing API"
    echo "  • Event Generator"
    echo "  • Flink Pricing Job"
    echo ""
    
    cd "$PROJECT_ROOT"
    ./gradlew \
        :services:pricing-api:bootJar \
        :services:event-generator:bootJar \
        :flink-pricing-job:shadowJar
    
    echo ""
    echo -e "${GREEN}✅ Build complete!${NC}"
    echo ""
    echo "Artifacts:"
    echo "  • API: services/pricing-api/build/libs/"
    echo "  • Generator: services/event-generator/build/libs/"
    echo "  • Flink: flink-pricing-job/build/libs/"
    echo ""
}

#######################################
# Build Flink job only
#######################################
build_flink() {
    echo -e "${BLUE}🔨 Building Flink Pricing Job${NC}"
    echo "=========================================="
    
    cd "$PROJECT_ROOT"
    ./gradlew :flink-pricing-job:shadowJar
    
    echo ""
    echo -e "${GREEN}✅ Flink job built!${NC}"
    echo "Artifact: flink-pricing-job/build/libs/flink-pricing-job-1.0.0.jar"
    echo ""
}

#######################################
# Build Pricing API only
#######################################
build_api() {
    echo -e "${BLUE}🔨 Building Pricing API${NC}"
    echo "=========================================="
    
    cd "$PROJECT_ROOT"
    ./gradlew :services:pricing-api:bootJar
    
    echo ""
    echo -e "${GREEN}✅ Pricing API built!${NC}"
    echo "Artifact: services/pricing-api/build/libs/"
    echo ""
}

#######################################
# Build Event Generator only
#######################################
build_generator() {
    echo -e "${BLUE}🔨 Building Event Generator${NC}"
    echo "=========================================="
    
    cd "$PROJECT_ROOT"
    ./gradlew :services:event-generator:bootJar
    
    echo ""
    echo -e "${GREEN}✅ Event Generator built!${NC}"
    echo "Artifact: services/event-generator/build/libs/"
    echo ""
}

#######################################
# Clean build artifacts
#######################################
build_clean() {
    echo -e "${BLUE}🧹 Cleaning Build Artifacts${NC}"
    echo "=========================================="
    
    cd "$PROJECT_ROOT"
    ./gradlew clean
    
    echo ""
    echo -e "${GREEN}✅ Clean complete!${NC}"
    echo ""
}

# Main
case "${1:-}" in
    all)
        build_all
        ;;
    flink)
        build_flink
        ;;
    api)
        build_api
        ;;
    gen|generator)
        build_generator
        ;;
    clean)
        build_clean
        ;;
    *)
        echo "Usage: $0 {all|flink|api|gen|clean}"
        echo ""
        echo "Commands:"
        echo "  all   - Build everything (API, Generator, Flink job)"
        echo "  flink - Build Flink job only"
        echo "  api   - Build Pricing API only"
        echo "  gen   - Build Event Generator only"
        echo "  clean - Clean build artifacts"
        echo ""
        echo "Examples:"
        echo "  $0 all          # Build everything"
        echo "  $0 flink        # Just rebuild Flink job"
        echo "  $0 clean        # Clean before fresh build"
        exit 1
        ;;
esac

