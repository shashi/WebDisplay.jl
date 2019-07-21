using Pkg
using Pkg.TOML

const PROJECT_FILENAME = normpath(joinpath(@__DIR__, "Project.toml"))
const PROJECT = TOML.parsefile(PROJECT_FILENAME)
const CURRENT_VERSION = VersionNumber(PROJECT["version"])
major, minor, patch = Int.(getfield.(CURRENT_VERSION, [:major, :minor, :patch]))

if length(ARGS) == 0 || ARGS[1] == "bump"
    target_version = VersionNumber("$(major).$(minor).$(patch + 1)")
    @info "Bumping WebIO version: $CURRENT_VERSION => $target_version"
else
    target_version = VersionNumber(ARGS[1])
    @info "Updating WebIO version: $CURRENT_VERSION => $target_version"
end

const PACKAGES_DIR = normpath(joinpath(@__DIR__, "packages"))
@info "Removing previous build artifacts..."
run(`sh -c "rm -rf ./deps/bundles $(PACKAGES_DIR)/node_modules $(PACKAGES_DIR)/*/node_modules $(PACKAGES_DIR)/*/dist"`)

@info "Running tests..."
# Build JS in prod mode.
ENV["WEBIO_BUILD_PROD"] = true
Pkg.test("WebIO")
