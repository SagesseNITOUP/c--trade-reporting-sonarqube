cmake_minimum_required(VERSION 3.16)
project(TradeReportingBoost LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(ENABLE_COVERAGE "Activer l'instrumentation de couverture GCC" OFF)

add_library(trade_validator STATIC src/trade_validator.cpp)
target_include_directories(trade_validator PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_compile_options(trade_validator PRIVATE -Wall -Wextra -Wpedantic)

if(ENABLE_COVERAGE)
    if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        message(FATAL_ERROR "Cette configuration de couverture necessite GCC/G++.")
    endif()
    target_compile_options(trade_validator PRIVATE --coverage -O0 -g)
    target_link_options(trade_validator INTERFACE --coverage)
endif()

find_path(BOOST_TEST_INCLUDE_DIR boost/test/included/unit_test.hpp)
if(NOT BOOST_TEST_INCLUDE_DIR)
    message(FATAL_ERROR "Boost.Test introuvable. Installer : sudo apt install libboost-test-dev")
endif()

enable_testing()
add_executable(trade_validator_tests tests/test_trade_validator.cpp)
target_include_directories(trade_validator_tests PRIVATE "${BOOST_TEST_INCLUDE_DIR}")
target_link_libraries(trade_validator_tests PRIVATE trade_validator)

add_test(NAME trade_validator_tests COMMAND trade_validator_tests --log_level=test_suite)
