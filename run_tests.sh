#!/bin/bash

# GraphGo Test Runner Script
# This script runs different types of tests for the GraphGo Flutter app

set -e

echo "🚀 GraphGo Test Suite Runner"
echo "=============================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    print_error "Flutter is not installed or not in PATH"
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    print_error "pubspec.yaml not found. Please run this script from the project root."
    exit 1
fi

# Install dependencies
print_status "Installing dependencies..."
flutter pub get

# Generate mock files if needed
print_status "Generating mock files..."
flutter packages pub run build_runner build --delete-conflicting-outputs

# Function to run tests
run_tests() {
    local test_type=$1
    local test_path=$2
    local description=$3
    
    print_status "Running $description..."
    
    if flutter test $test_path; then
        print_success "$description completed successfully"
    else
        print_error "$description failed"
        return 1
    fi
}

# Parse command line arguments
RUN_UNIT=false
RUN_WIDGET=false
RUN_INTEGRATION=false
RUN_ALL=false
GENERATE_COVERAGE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --unit)
            RUN_UNIT=true
            shift
            ;;
        --widget)
            RUN_WIDGET=true
            shift
            ;;
        --integration)
            RUN_INTEGRATION=true
            shift
            ;;
        --all)
            RUN_ALL=true
            shift
            ;;
        --coverage)
            GENERATE_COVERAGE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --unit         Run unit tests only"
            echo "  --widget       Run widget tests only"
            echo "  --integration  Run integration tests only"
            echo "  --all          Run all tests"
            echo "  --coverage     Generate coverage report"
            echo "  --help         Show this help message"
            echo ""
            echo "If no options are provided, runs all tests by default."
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# If no specific test type is specified, run all tests
if [ "$RUN_UNIT" = false ] && [ "$RUN_WIDGET" = false ] && [ "$RUN_INTEGRATION" = false ]; then
    RUN_ALL=true
fi

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

# Run unit tests
if [ "$RUN_UNIT" = true ] || [ "$RUN_ALL" = true ]; then
    if run_tests "unit" "test/providers/" "Unit Tests"; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi
fi

# Run widget tests
if [ "$RUN_WIDGET" = true ] || [ "$RUN_ALL" = true ]; then
    if run_tests "widget" "test/screens/ test/widget_test.dart" "Widget Tests"; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi
fi

# Run integration tests
if [ "$RUN_INTEGRATION" = true ] || [ "$RUN_ALL" = true ]; then
    if run_tests "integration" "integration_test/" "Integration Tests"; then
        ((TESTS_PASSED++))
    else
        ((TESTS_FAILED++))
    fi
fi

# Generate coverage report if requested
if [ "$GENERATE_COVERAGE" = true ]; then
    print_status "Generating coverage report..."
    if flutter test --coverage; then
        print_success "Coverage report generated in coverage/lcov.info"
        
        # Check if genhtml is available for HTML report
        if command -v genhtml &> /dev/null; then
            genhtml coverage/lcov.info -o coverage/html
            print_success "HTML coverage report generated in coverage/html/"
        else
            print_warning "genhtml not found. Install lcov to generate HTML coverage reports."
        fi
    else
        print_error "Failed to generate coverage report"
    fi
fi

# Print summary
echo ""
echo "=============================="
echo "Test Summary"
echo "=============================="

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "All tests passed! 🎉"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
else
    print_error "Some tests failed! ❌"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    exit 1
fi

echo ""
print_status "Test run completed!"
