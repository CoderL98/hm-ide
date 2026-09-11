# hm-ide Native NAPI modules (HarmonyOS NEXT / API 12+)
# Targets: hm_pty (always), hm_git (libgit2 optional), hm_clang (libclang optional)
cmake_minimum_required(VERSION 3.5.0)
project(hm_ide_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include
)

# ---------- libhm_pty.so ----------
add_library(hm_pty SHARED
    napi_init.cpp
    pty_session.cpp
)
target_compile_options(hm_pty PRIVATE -Wall -Wextra)
find_library(UTIL_LIB util)
if(UTIL_LIB)
    target_compile_definitions(hm_pty PRIVATE HM_LINK_LIBUTIL=1)
    target_link_libraries(hm_pty PUBLIC libace_napi.z.so ${UTIL_LIB})
else()
    target_link_libraries(hm_pty PUBLIC libace_napi.z.so)
endif()

# ---------- libhm_git.so ----------
set(HM_GIT_SOURCES
    git/napi_git_init.cpp
    git/git_service.cpp
)
add_library(hm_git SHARED ${HM_GIT_SOURCES})
target_compile_options(hm_git PRIVATE -Wall -Wextra)
target_include_directories(hm_git PRIVATE ${NATIVERENDER_ROOT_PATH}/git)

# Optional: -DHM_GIT2_ROOT=/path/to/libgit2 install (OHOS NDK prebuilt)
if(DEFINED HM_GIT2_ROOT AND EXISTS "${HM_GIT2_ROOT}/include/git2.h")
    message(STATUS "hm_git: linking libgit2 from ${HM_GIT2_ROOT}")
    target_compile_definitions(hm_git PRIVATE HM_HAS_LIBGIT2=1)
    target_include_directories(hm_git PRIVATE ${HM_GIT2_ROOT}/include)
    if(EXISTS "${HM_GIT2_ROOT}/lib/libgit2.a")
        target_link_libraries(hm_git PUBLIC libace_napi.z.so ${HM_GIT2_ROOT}/lib/libgit2.a)
    elseif(EXISTS "${HM_GIT2_ROOT}/lib/libgit2.so")
        target_link_libraries(hm_git PUBLIC libace_napi.z.so ${HM_GIT2_ROOT}/lib/libgit2.so)
    else()
        target_link_libraries(hm_git PUBLIC libace_napi.z.so git2)
    endif()
else()
    message(STATUS "hm_git: stub mode (set HM_GIT2_ROOT to enable libgit2)")
    target_compile_definitions(hm_git PRIVATE HM_HAS_LIBGIT2=0)
    target_link_libraries(hm_git PUBLIC libace_napi.z.so)
endif()

# ---------- libhm_clang.so ----------
set(HM_CLANG_SOURCES
    clang/napi_clang_init.cpp
    clang/clang_service.cpp
)
add_library(hm_clang SHARED ${HM_CLANG_SOURCES})
target_compile_options(hm_clang PRIVATE -Wall -Wextra)
target_include_directories(hm_clang PRIVATE ${NATIVERENDER_ROOT_PATH}/clang)

# Optional: -DLLVM_ROOT=/path/to/llvm-ohos (must contain include/clang-c/Index.h)
if(DEFINED LLVM_ROOT AND EXISTS "${LLVM_ROOT}/include/clang-c/Index.h")
    message(STATUS "hm_clang: linking libclang from ${LLVM_ROOT}")
    target_compile_definitions(hm_clang PRIVATE HM_HAS_LIBCLANG=1)
    target_include_directories(hm_clang PRIVATE ${LLVM_ROOT}/include)
    if(EXISTS "${LLVM_ROOT}/lib/libclang.a")
        target_link_libraries(hm_clang PUBLIC libace_napi.z.so ${LLVM_ROOT}/lib/libclang.a)
    elseif(EXISTS "${LLVM_ROOT}/lib/libclang.so")
        target_link_libraries(hm_clang PUBLIC libace_napi.z.so ${LLVM_ROOT}/lib/libclang.so)
    else()
        target_link_libraries(hm_clang PUBLIC libace_napi.z.so clang)
    endif()
else()
    message(STATUS "hm_clang: stub mode (set LLVM_ROOT to enable libclang)")
    target_compile_definitions(hm_clang PRIVATE HM_HAS_LIBCLANG=0)
    target_link_libraries(hm_clang PUBLIC libace_napi.z.so)
endif()


# ---------- libhm_ssh.so (full NAPI surface; ENOSYS until HM_HAS_LIBSSH2) ----------
add_library(hm_ssh SHARED
    ssh/napi_ssh_init.cpp
)
target_compile_options(hm_ssh PRIVATE -Wall -Wextra)
target_link_libraries(hm_ssh PUBLIC libace_napi.z.so)
