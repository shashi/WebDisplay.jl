# This file is sometimes included as a standalone script, but we need some of
# the values from bundlepaths.jl
if !(@isdefined BUNDLES_PATH)
    include("./bundlepaths.jl")
end

# Avoid namespace pollution with let
let
    @info BUNDLES_PATH
    package_dir = dirname(@__DIR__)

    # NodeJS isn't a hard requirement of WebIO, but is needed to build packages,
    # so we need to install it in CI.
    if isci()
        @info "CI detected, installing NodeJS..."

        using Pkg
        Pkg.add("NodeJS")
    end

    # Don't build packages outside of a dev environment (or CI).
    if !isdev()
        @warn(
            "Can't build WebIO JS when not checked out for development. "
            * "Run `Pkg.dev(\"WebIO\")` if you want to build JS."
        )
        return
    end

    # Build the dang packages!
    using NodeJS
    package_dir = normpath(joinpath(@__DIR__, "..", "packages"))
    npm = `$(NodeJS.npm_cmd()) -C $(package_dir)`

    install_cmd = `$npm install --scripts-prepend-node-path=auto --unsafe-perm`
    @info "Installing NPM dependencies..." cmd=install_cmd
    run(install_cmd)

    args = (
        haskey(ENV, "WEBIO_WEBPACK_ARGS")
        ? [ENV["WEBIO_WEBPACK_ARGS"]]
        : []
    )
    build_cmd = `$npm run build-prod --scripts-prepend-node-path=auto --unsafe-perm -- $args`
    @info "Building packages..." cmd=build_cmd
    run(build_cmd)

    # Copy important things to the right place
    core_bundle_out = joinpath(package_dir, "webio", "dist", "webio.bundle.js")
    @info "Copying $(core_bundle_out) to $(CORE_BUNDLE_PATH)..."
    cp(core_bundle_out, CORE_BUNDLE_PATH; force=true)

    generic_http_bundle_out = joinpath(package_dir, "generic-http-provider", "dist", "generic-http.bundle.js")
    @info "Copying $(core_bundle_out) to $(CORE_BUNDLE_PATH)..."
    cp(core_bundle_out, CORE_BUNDLE_PATH; force=true)
end
