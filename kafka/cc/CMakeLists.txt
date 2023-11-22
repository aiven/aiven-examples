cmake_minimum_required(VERSION "3.20")

project("Modern C++ Kafka API Aiven Example" VERSION 1.0.0)

get_property(parent_directory DIRECTORY PROPERTY PARENT_DIRECTORY)
if (NOT parent_directory)
    set(cppkafka_master_project ON)
    # Use Strict Options
    if ((CMAKE_CXX_COMPILER_ID STREQUAL "Clang") OR (CMAKE_CXX_COMPILER_ID STREQUAL "GNU"))
        add_compile_options("-Wall" "-Werror" "-Wextra" "-Wshadow" "-Wno-unused-result")
    elseif (CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        add_definitions(-D_CRT_SECURE_NO_WARNINGS)
    endif ()
    if (CMAKE_CXX_STANDARD EQUAL 14)
        add_compile_options("-Wno-maybe-uninitialized")
    endif ()
endif ()

include(CheckCXXCompilerFlag)
include(CMakePushCheckState)


#---------------------------
# C++17 (by default)
#---------------------------
if (NOT CMAKE_CXX_STANDARD)
    set(CMAKE_CXX_STANDARD 17)
endif ()
set(CMAKE_CXX_STANDARD_REQUIRED False)


include(FetchContent)

FetchContent_Declare(
    modern_cpp_kafka
    GIT_REPOSITORY https://github.com/morganstanley/modern-cpp-kafka.git
    GIT_TAG main
)

FetchContent_MakeAvailable(modern_cpp_kafka)

# Target: example_KafkaProducer_Simple
add_executable("avn_KafkaProducer_Simple" "avn_KafkaProducer_Simple.cc")
target_link_libraries("avn_KafkaProducer_Simple" modern-cpp-kafka-api)

# Target: example_KafkaConsumer_Simple
add_executable("avn_KafkaConsumer_Simple" "avn_KafkaConsumer_Simple.cc")
target_link_libraries("avn_KafkaConsumer_Simple" modern-cpp-kafka-api)
