cmake_minimum_required(VERSION 3.27...3.31)
set(CMAKE_CONFIGURATION_TYPES Debug RelWithDebInfo)
project(64tass)
set(CMAKE_SKIP_INSTALL_RULES YES)
set_property(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} PROPERTY VS_STARTUP_PROJECT 64tass)

##########################################################################
##########################################################################

# buncha warnings with /W4 that I'm not massively inclined to trawl
# through.

# # Force /W4.
# #
# # http://stackoverflow.com/questions/2368811/how-to-set-warning-level-in-cmake
# if(CMAKE_C_FLAGS MATCHES "/W[0-4]")
#   string(REGEX REPLACE "/W[0-4]" "/W4" CMAKE_C_FLAGS "${CMAKE_C_FLAGS}")
#   string(REGEX REPLACE "/W[0-4]" "/W4" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
# else()
#   set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} /W4")
#   set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /W4")
# endif()

# Enable multithreaded compiles. (There's an actual msbuild flag for
# this, but CMake doesn't seem to support it.)
#
# https://randomascii.wordpress.com/2014/03/22/make-vc-compiles-fast-through-parallel-compilation/
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} /MP")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /MP")

# Use statically linked CRT, to reduce the chances of needing to
# install the VC++ runtime redist.
#
# (Copied verbatim from another project, and I didn't rethink the
# DebugDLL aspect.)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:DebugDLL>")

##########################################################################
##########################################################################

set(TASS_PATH ../tass64-code.r3243)

##########################################################################
##########################################################################

add_executable(64tass)
target_sources(64tass PRIVATE
  ${TASS_PATH}/64tass.c
  ${TASS_PATH}/64tass.h
  ${TASS_PATH}/addressobj.c
  ${TASS_PATH}/addressobj.h
  ${TASS_PATH}/anonsymbolobj.c
  ${TASS_PATH}/anonsymbolobj.h
  ${TASS_PATH}/arguments.c
  ${TASS_PATH}/arguments.h
  ${TASS_PATH}/argvalues.c
  ${TASS_PATH}/argvalues.h
  ${TASS_PATH}/attributes.h
  ${TASS_PATH}/avl.c
  ${TASS_PATH}/avl.h
  ${TASS_PATH}/bitsobj.c
  ${TASS_PATH}/bitsobj.h
  ${TASS_PATH}/boolobj.c
  ${TASS_PATH}/boolobj.h
  ${TASS_PATH}/bytesobj.c
  ${TASS_PATH}/bytesobj.h
  ${TASS_PATH}/codeobj.c
  ${TASS_PATH}/codeobj.h
  ${TASS_PATH}/console.c
  ${TASS_PATH}/console.h
  ${TASS_PATH}/dictobj.c
  ${TASS_PATH}/dictobj.h
  ${TASS_PATH}/encobj.c
  ${TASS_PATH}/encobj.h
  ${TASS_PATH}/encoding.c
  ${TASS_PATH}/encoding.h
  ${TASS_PATH}/error.c
  ${TASS_PATH}/error.h
  ${TASS_PATH}/errorobj.c
  ${TASS_PATH}/errorobj.h
  ${TASS_PATH}/errors_e.h
  ${TASS_PATH}/eval.c
  ${TASS_PATH}/eval.h
  ${TASS_PATH}/file.c
  ${TASS_PATH}/file.h
  ${TASS_PATH}/floatobj.c
  ${TASS_PATH}/floatobj.h
  ${TASS_PATH}/foldobj.c
  ${TASS_PATH}/foldobj.h
  ${TASS_PATH}/functionobj.c
  ${TASS_PATH}/functionobj.h
  ${TASS_PATH}/gapobj.c
  ${TASS_PATH}/gapobj.h
  ${TASS_PATH}/instruction.c
  ${TASS_PATH}/instruction.h
  ${TASS_PATH}/intobj.c
  ${TASS_PATH}/intobj.h
  ${TASS_PATH}/inttypes.h
  ${TASS_PATH}/isnprintf.c
  ${TASS_PATH}/isnprintf.h
  ${TASS_PATH}/labelobj.c
  ${TASS_PATH}/labelobj.h
  ${TASS_PATH}/listing.c
  ${TASS_PATH}/listing.h
  ${TASS_PATH}/listobj.c
  ${TASS_PATH}/listobj.h
  ${TASS_PATH}/longjump.c
  ${TASS_PATH}/longjump.h
  ${TASS_PATH}/macro.c
  ${TASS_PATH}/macro.h
  ${TASS_PATH}/macroobj.c
  ${TASS_PATH}/macroobj.h
  ${TASS_PATH}/main.c
  ${TASS_PATH}/main.h
  ${TASS_PATH}/math.c
  ${TASS_PATH}/math.h
  ${TASS_PATH}/mem.c
  ${TASS_PATH}/mem.h
  ${TASS_PATH}/memblocksobj.c
  ${TASS_PATH}/memblocksobj.h
  ${TASS_PATH}/mfuncobj.c
  ${TASS_PATH}/mfuncobj.h
  ${TASS_PATH}/my_getopt.c
  ${TASS_PATH}/my_getopt.h
  ${TASS_PATH}/namespaceobj.c
  ${TASS_PATH}/namespaceobj.h
  ${TASS_PATH}/noneobj.c
  ${TASS_PATH}/noneobj.h
  ${TASS_PATH}/obj.c
  ${TASS_PATH}/obj.h
  ${TASS_PATH}/opcodes.c
  ${TASS_PATH}/opcodes.h
  ${TASS_PATH}/oper_e.h
  ${TASS_PATH}/operobj.c
  ${TASS_PATH}/operobj.h
  ${TASS_PATH}/opt_bit.c
  ${TASS_PATH}/opt_bit.h
  ${TASS_PATH}/optimizer.c
  ${TASS_PATH}/optimizer.h
  ${TASS_PATH}/registerobj.c
  ${TASS_PATH}/registerobj.h
  ${TASS_PATH}/section.c
  ${TASS_PATH}/section.h
  ${TASS_PATH}/stdbool.h
  ${TASS_PATH}/str.c
  ${TASS_PATH}/str.h
  ${TASS_PATH}/strobj.c
  ${TASS_PATH}/strobj.h
  ${TASS_PATH}/symbolobj.c
  ${TASS_PATH}/symbolobj.h
  ${TASS_PATH}/ternary.c
  ${TASS_PATH}/ternary.h
  ${TASS_PATH}/typeobj.c
  ${TASS_PATH}/typeobj.h
  ${TASS_PATH}/unicode.c
  ${TASS_PATH}/unicode.h
  ${TASS_PATH}/unicodedata.c
  ${TASS_PATH}/unicodedata.h
  ${TASS_PATH}/values.c
  ${TASS_PATH}/values.h
  ${TASS_PATH}/variables.c
  ${TASS_PATH}/variables.h
  ${TASS_PATH}/version.h
  ${TASS_PATH}/wait_e.h
  ${TASS_PATH}/wchar.c
  ${TASS_PATH}/wchar.h)
target_compile_definitions(64tass PRIVATE
  _CRT_SECURE_NO_WARNINGS
  _CRT_NONSTDC_NO_WARNINGS)
