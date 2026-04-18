# ------------------------------------------------------------------------------
cmake_minimum_required(VERSION 3.31)
project(local-lua-debugger-vscode NONE)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include("cmake/macros.cmake")

# ------------------------------------------------------------------------------
# Configuration
set(DEBUGGER_SRC "${CMAKE_CURRENT_SOURCE_DIR}")
# Extract version from package.json
file(READ "${DEBUGGER_SRC}/package.json" PACKAGE_JSON_CONTENT)
string(JSON PACKAGE_NAME GET "${PACKAGE_JSON_CONTENT}" "name")
string(JSON DEBUGGER_VERSION GET "${PACKAGE_JSON_CONTENT}" "version")
message(STATUS "Detected Extension: ${PACKAGE_NAME} v${DEBUGGER_VERSION}")
# Option for signing
option(SIGN_PACKAGE "Code-sign VSIX package" OFF)

# ------------------------------------------------------------------------------
# Search for tools
find_program(NPM_EXECUTABLE NAMES npm REQUIRED)
find_program(VSCE_EXECUTABLE NAMES vsce REQUIRED)
if(SIGN_PACKAGE)
  find_program(SIGN_PACKAGE_EXE NAMES sign REQUIRED)
endif()

# ------------------------------------------------------------------------------
# Setup signing stuff if vsix-package shall be signed
if(SIGN_PACKAGE AND CODE_SIGN_ID)
  # Calculate SHA256 fingerprint (needed by sign.exe)
  get_cert_fingerprint_sha256("${CODE_SIGN_ID}" AUTO_FINGERPRINT)
  if(AUTO_FINGERPRINT)
    set(CODE_SIGN_FINGERPRINT "${AUTO_FINGERPRINT}" CACHE STRING "Auto-detected Fingerprint" FORCE)
    message(STATUS "Auto-detected Certificate Fingerprint: ${CODE_SIGN_FINGERPRINT}")
  else()
    message(FATAL_ERROR "Could not auto-detect fingerprint for Subject: ${CODE_SIGN_ID}")
  endif()
endif()

# ------------------------------------------------------------------------------
# 1. npm install
# Uses package-lock.json as a timestamp marker
add_custom_command(
  OUTPUT "${DEBUGGER_SRC}/node_modules/.package-lock.json"
  COMMAND ${NPM_EXECUTABLE} install
  WORKING_DIRECTORY "${DEBUGGER_SRC}"
  COMMENT "Running npm install..."
  VERBATIM
)

# ------------------------------------------------------------------------------
# 2. Build
# Transpiles TypeScript (usually creates files in the 'out' directory)
add_custom_command(
  OUTPUT "${DEBUGGER_SRC}/debugger/lldebugger.lua"
  COMMAND ${NPM_EXECUTABLE} run build
  WORKING_DIRECTORY "${DEBUGGER_SRC}"
  DEPENDS "${DEBUGGER_SRC}/node_modules/.package-lock.json"
  COMMENT "Running npm build (transpiling)..."
  VERBATIM
)

# ------------------------------------------------------------------------------
# 3. Bundle
# Bundles everything into the final extension/extension.js
add_custom_command(
  OUTPUT "${DEBUGGER_SRC}/extension/extension.js"
  COMMAND ${NPM_EXECUTABLE} run bundle
  WORKING_DIRECTORY "${DEBUGGER_SRC}"
  DEPENDS "${DEBUGGER_SRC}/debugger/lldebugger.lua"
  COMMENT "Running npm bundle (webpacking)..."
  VERBATIM
)

# ------------------------------------------------------------------------------
# 4. VSIX Packaging
set(VSIX_FILE "${CMAKE_BINARY_DIR}/${PACKAGE_NAME}-${DEBUGGER_VERSION}.vsix")

add_custom_command(
  OUTPUT "${VSIX_FILE}"
  COMMAND cmd /c ${VSCE_EXECUTABLE} package -o "${VSIX_FILE}"
  WORKING_DIRECTORY "${DEBUGGER_SRC}"
  DEPENDS "${DEBUGGER_SRC}/extension/extension.js"
  COMMENT "Creating VSIX package: ${VSIX_FILE}"
  VERBATIM
)

# ------------------------------------------------------------------------------
# 5. Optional Signing
# Uses the signing logic from your first script
if(SIGN_PACKAGE AND CODE_SIGN_FINGERPRINT)
  add_custom_command(
    APPEND
    OUTPUT "${VSIX_FILE}"
    COMMAND "${SIGN_PACKAGE_EXE}" code certificate-store "${VSIX_FILE}"
    -cfp "${CODE_SIGN_FINGERPRINT}" -pn OneLuaPro -v information
    COMMENT "Signing VSIX package with fingerprint ${CODE_SIGN_FINGERPRINT}..."
  )
endif()

# ------------------------------------------------------------------------------
# Targets, Dependencies & Install
add_custom_target(bundle_debugger DEPENDS "${DEBUGGER_SRC}/extension/extension.js")
add_custom_target(package_debugger ALL DEPENDS "${VSIX_FILE}")
add_dependencies(package_debugger bundle_debugger)
install(FILES "${VSIX_FILE}"
  DESTINATION "opt/vscode"
)

# ------------------------------------------------------------------------------
# Clean Target
set(CLEAN_FILES
  #"${DEBUGGER_SRC}/node_modules"
  #"${DEBUGGER_SRC}/out"
  "${DEBUGGER_SRC}/debugger/lldebugger.lua"
  "${DEBUGGER_SRC}/extension/extension.js"
  "${VSIX_FILE}"
)
set_directory_properties(PROPERTIES ADDITIONAL_CLEAN_FILES "${CLEAN_FILES}")
# ------------------------------------------------------------------------------
# Notes
#
# cmake . -G "Visual Studio 17 2022" -A x64 -DCODE_SIGN_ID="Open Source Developer" -DCMAKE_INSTALL_PREFIX=c:/Apps/OneLuaPro -DSIGN_PACKAGE=ON
# cmake --build . --config Release
# cmake --install .
#
# cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=c:/Apps/OneLuaPro -DCODE_SIGN_ID="Open Source Developer" -DCMAKE_INSTALL_PREFIX=c:/Apps/OneLuaPro -DSIGN_PACKAGE=ON .
# cmake --build .
# cmake --install .
