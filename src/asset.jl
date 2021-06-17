using JSON

export Asset, Async, Sync

"""
    Asset(url)
    Asset(name, url)
    Asset(name => url)
    Asset(filetype, name, url)

A browser asset that can be loaded by WebIO.

The `url` parameter may be either a remote URL or a local filepath (which will
be served via AssetRegistry.jl).
All of the following are valid `url` values.
  * `https://unpkg.com/react@16/umd/react.development.js`
  * `//unpkg.com/react@16/umd/react.development.js`
  * `./path/to/foo.js`

By default, the filetype is guessed as the extension of the specified url
(only `"js"`, `"css"`, and `"html"` are currently supported) but may be
specified if nonstandard extensions are in use.
"""
struct Asset
    filetype::String
    name::Union{Nothing, String}
    url::String
end

Asset(name, url) = Asset(getextension(url), name, url)
Asset(url) = Asset(nothing, url)
Asset(x::Pair) = Asset(string(x[1]), x[2])
Asset(x::Asset) = x
function Asset(spec::Dict)
    Base.depwarn(
        "`Asset(::Dict)` is deprecated, use `Asset(url)` instead.`",
        :webio_asset_dict_constructor,
    )

    spec = Dict(string(k) => v for (k, v) in spec)
    url = get(spec, "url") do
        error("Invalid Asset dict specification: missing key \"url\".")
    end
    filetype = get(spec, "type", getextension(url))
    name = get(spec, "name", nothing)

    return Asset(filetype, name, url)
end

function JSON.lower(asset::Asset)
    Dict(
         "type" => asset.filetype,
         "url"  => dep2url(asset.url),
         "name" => asset.name,
    )
end


function tojs(asset::Asset)
    return js"WebIO.importResource($(JSON.lower(asset)))"
end

"""
    Sync(assets...)

A group ("block") of assets that will be imported sequentially (synchronously)
in the browser.
This is useful when dependencies have side effects that must be executed in
order.
The elements of `assets` may either be [`Asset`](@ref)s themselves, any valid
constructor for an [`Asset`](@ref), or a [`Sync`](@ref) or [`Async`](@ref).

If the imports do not need to be imported sequentially, use [`Async`](@ref)
instead.

# Examples
```julia-repl
julia> WebIO.Sync(Asset("foo.js"), "bar" => "bar.js")
Sync(Asset[Asset("js", nothing, "foo.js"), Asset("js", "bar", "bar.js")])
```
"""
struct Sync
    # This is untyped because we can't define a union type that includes all of
    # Asset, Sync, and Async that is then used within Sync and Async.
    imports::Array{Any}

    Sync(imports::Array) = new([ensure_asset(asset) for asset in imports])
end
Sync(assets...) = Sync([assets...])

"""
    Async(assets...)

A group ("block") of assets that will be imported with no specified order
(asynchronously) in the browser.
This is useful when dependencies can be imported in any order.
The elements of `assets` may either be [`Asset`](@ref)s themselves, any valid
constructor for an [`Asset`](@ref), or a [`Sync`](@ref) or [`Async`](@ref).

If the imports need to be imported sequentially, use [`Sync`](@ref) instead.
"""
struct Async
    # See comment about (lack of) typing in Sync above.
    imports::Array{Any}

    Async(imports::Array) = new([ensure_asset(asset) for asset in imports])
end
Async(assets...) = Async([assets...])

# This allows js"await $(Async([....]))" on a tree of assets!
function tojs(asset::Union{Async,Sync})
    return js"WebIO.importBlock($(lowerassets(asset)))"
end

# The output of lowerassets is initially sent with the Scope
# this should trigger loading of the assets before onmount callbacks
lowerassets(x) = JSON.lower(Asset(x))
lowerassets(x::Asset) = JSON.lower(x)
lowerassets(x::Async) = Dict(
    "type" => "async_block",
    "data" => map(lowerassets, x.imports),
)
lowerassets(x::AbstractArray) = lowerassets(Async(x))
lowerassets(x::Sync) = Dict(
    "type"=>"sync_block",
    "data" => map(lowerassets, x.imports),
)

"""
    ensure_asset(asset)

Ensure that `asset` is a valid [`Asset`](@ref) or [`Async`](@ref) or
[`Sync`](@ref).
If it's not, calls the [`Asset`](@ref) constructor on the argument.
"""
ensure_asset(asset::Union{Asset, Sync, Async}) = asset
ensure_asset(arg) = Asset(arg)


"""
    getextension(path)

Get the file extension of the path.
The extension is defined to be the bit after the last dot, excluding any query
string.

# Examples
```julia-repl
julia> WebIO.getextension("foo.bar.js")
"js"
julia> WebIO.getextension("https://my-cdn.net/foo.bar.css?version=1")
"css"
```
"""
getextension(path) = lowercase(last(split(first(split(path, "?")), ".")))

"""
    islocal(path)

Determine whether or not the specified path is a local filesystem path (and not
a remote resource that is hosted on, for example, a CDN).
"""
islocal(path) = !any(startswith.(path, ("//", "https://", "http://", "ftp://")))

"""
    path2url(path)

Register the specified path with AssetRegistry and return the url that
corresponds to that path.

# Examples
```julia-repl
julia> WebIO.path2url(expanduser("~/Documents/foo.js"))
"/assetserver/bd67c48cbe6388c22f85faef9840ff9a2dfc1df6-foo.js"
```
"""
function path2url(path::AbstractString)
    if startswith(path, "/pkg/")
        Base.depwarn(
            "/pkg/ URLs are deprecated, specify files using their absolute paths.",
            :webio_pkg_urls,
        )
        return path
    # check if file or containing directory has already been registered
    elseif startswith(path, "/assetserver/") && haskey(AssetRegistry.registry, join(split(path, "/")[1:3],"/"))
        return path
    elseif isfile(abspath(path)) || isdir(abspath(path))
        # TODO: this should be implemented in AssetRegistry, not here.
        path = abspath(path)
        # first lookup to see if any of the file itself or any of the parent
        # directories are registered.
        AssetRegistry.isregistered(path) && return AssetRegistry.getkey(path)
        cur_path = path
        while true
            if AssetRegistry.isregistered(cur_path) && isdir(cur_path)
                key = AssetRegistry.getkey(cur_path)
                #strip cur_path and convert all backslashes to slashes (for windows ;-) )
                url = key * replace(SubString(path, length(cur_path) + 1, length(path)), "\\" => "/")
                return url
            end
            cur_path1 = dirname(cur_path)
            if cur_path1 == cur_path
                # this means we have reached root directory,
                # and none of the parents are in registry
                # register the original path uniquely
                return AssetRegistry.register(path)
            end
            cur_path = cur_path1
        end
    end
    error("Invalid dependency (must be a url, file, or AssetRegistry path): $path")
end

"""
    dep2url(dep)

Return the URL where the dependency can be fetched from.
If the dependency is a URL (e.g. hosted at a CDN), the same URL is returned.
Otherwise, the depency is registered with AssetRegistry.jl and served from
there.
"""
function dep2url(dep::AbstractString)
    # if is an url, we are done :)
    islocal(dep) || return dep
    # split query from url path, including further '?'s
    url_parts = split(dep, "?")
    # register the url file without the query part
    url_parts[1] = path2url(baseurl[] * url_parts[1])
    return join(url_parts, "?")
end
