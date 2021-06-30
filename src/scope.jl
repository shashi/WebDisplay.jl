using JSON

export Scope,
       withscope,
       Observable,
       @private,
       setobservable!,
       on, onjs,
       evaljs,
       onmount,
       onimport,
       ondependencies,
       adddeps!,
       import!,
       addconnection!

import Sockets: send
import Observables: Observable, AbstractObservable, listeners

# bool marks if it is synced
const ObsDict = Dict{String, Tuple{AbstractObservable, Union{Nothing,Bool}}}

mutable struct Scope
    dom::Any
    observs::ObsDict
    private_obs::Set{String}
    systemjs_options::Any
    # This should be an array of scopes, but there currently exist some circular
    # relationships between imports and scopes.
    imports::Vector{Asset}
    # A collection of handler functions associated with various observables in
    # this scope. Of the form
    # "observable-name" => ["array", "of", "JS", "strings"]
    # where each JS-string is a function that is invoked when the observable
    # changes.
    jshandlers::Any
    pool::ConnectionPool

    mount_callbacks::Vector{JSString}

    function Scope(
            dom::Any,
            observs::ObsDict, # bool marks if it is synced
            private_obs::Set{String},
            systemjs_options::Any,
            imports::Vector{Asset},
            jshandlers::Any,
            pool::ConnectionPool,
            mount_callbacks::Vector{JSString}
        )
        scope = new(
            dom, observs, private_obs,
            systemjs_options, imports, jshandlers, pool,
            mount_callbacks
        )
        register_scope!(scope)
        return scope
    end
end

function Base.getproperty(scope::Scope, property::Symbol)
    if property === :id
        Base.depwarn(
            "Accessing `scope.id` is deprecated, use `scopeid(scope)` instead.",
            :webio_scope_id,
        )
        return scopeid(scope)
    end
    return getfield(scope, property)
end

"""
    scopeid(scope)

Get a unique identifier for the specified scope.
This is the identifier that is used to reference scopes when communicating
between Julia and the Browser.

This defers to `Base.objectid` under the hood, though is cast to a string for
mostly historical reasons.
"""
scopeid(scope::Scope) = string(objectid(scope))

const global_scope_registry = Dict{String, Scope}()

function register_scope!(scope::Scope)
    global_scope_registry[scopeid(scope)] = scope
end

function deregister_scope!(scope::Scope)
    delete!(global_scope_registry, scopeid(scope))
end

function lookup_scope(uuid::String)
    get(global_scope_registry, uuid) do
        error("Could not find scope $(uuid)")
    end
end

"""
    Scope(<keyword arguments>)

An object which can send and receive messages.

# Arguments
- `dom`: The DOM node that will be rendered when the scope is displayed in the
    browser.
- `imports`: An collection of `Asset`s to load (see [`Asset`](@ref) for
    more documentation) when the scope is mounted. If the entry is not an
    `Asset` then it should be an argument to construct an `Asset`.

# Examples
```julia
myscope = Scope(
    dom=node(:p, "I'm a little scope!"),
    imports=[Asset("foo.js"), "bar.css", "spam" => "spam.js"],
)
```
"""
function Scope(;
        dom = dom"span"(),
        outbox::Union{Channel, Nothing} = nothing,
        observs::Dict = ObsDict(),
        private_obs::Set{String} = Set{String}(),
        systemjs_options = nothing,
        imports = Asset[],
        jshandlers::Dict = Dict(),
        mount_callbacks::Vector{JSString} = JSString[],
        # Deprecated
        id=nothing,
    )
    if id !== nothing
        Base.depwarn(
            "`Scope(; id, kwargs...)` is deprecated, "
                * "use `Scope(kwargs...)` instead.",
            :webio_scope_id_keyword_arg,
        )
    end
    imports = Asset[Asset(i) for i in imports]
    pool = outbox !== nothing ? ConnectionPool(outbox) : ConnectionPool()
    return Scope(
        dom, observs, private_obs, systemjs_options,
        imports, jshandlers, pool, mount_callbacks
    )
end

function Scope(id; kwargs...)
    Base.depwarn(
        "Scope(id; kwargs...) is deprecated, use Scope(kwargs...) instead.",
        :webio_scope_id_positional_arg,
    )
    return Scope(; kwargs...)
end

(w::Scope)(arg) = (w.dom = arg; w)
Base.wait(scope::Scope) = ensure_connection(scope.pool)

function Observables.on(f, w::Scope, key)
    key = string(key)
    listener, _ = get!(()->(Observable{Any}(w, key, nothing), nothing), w.observs, key)
    on(f, listener)
end

private(scope::Scope, props...) = foreach(p->push!(scope.private_obs, string(p)), props)

macro private(ex)
    if ex.head == :(=)
        ref, val = ex.args
        scope, key = ref.args
        quote
            x=$(esc(ex))
            private($(esc(scope)), $(esc(key)))
            x
        end
    else
        error("Wrong usage of @private. Use as in `@private scope[\"key\"] = observable`")
    end
end

# we need to maintain mapping from an ID to observable
# in order to allow interpolation of observables.
const observ_id_dict = WeakKeyDict()

function setobservable!(ctx, key, obs; sync=nothing)
    key = string(key)
    if haskey(ctx.observs, key)
        @warn("An observable named $key already exists in scope $(scopeid(ctx)).
             Overwriting.")
    end

    ctx.observs[key] = (obs, sync)

    # the following metadata is stored for use in interpolation
    # of observables into DOM trees and `@js` expressions
    observ_id_dict[obs]  = (WeakRef(ctx), key)
    obs
end

# Ask JS to send stuff
function setup_comm(f, ob::AbstractObservable)
    if haskey(observ_id_dict, ob)
        scope, key = observ_id_dict[ob]
        # if !(key in scope.value.private_obs)
        #     evaljs(scope.value, js"""
        #            console.log(this)
        #            this.observables[$key].sync = true
        #     """)
        # end
    end
end

# TODO: hook `off` up

function Base.getindex(w::Scope, key)
    key = string(key)
    if haskey(w.observs, key)
        w.observs[key][1]
    else
        Observable{Any}(w, key, nothing)
    end
end

function Base.setindex!(w::Scope, obs, key)
    setobservable!(w, key, obs)
end

function Observable{T}(ctx::Scope, key, value; sync=nothing) where {T}
    setobservable!(ctx, key, Observable{T}(value), sync=sync)
end

function Observable(ctx::Scope, key, val::T; sync=nothing) where {T}
    Observable{T}(ctx, key, val; sync=sync)
end

function JSON.lower(scope::Scope)
    obs_dict = Dict()
    for (k, ob_) in scope.observs
        ob, sync = ob_
        if k in scope.private_obs
            continue
        end
        if sync === nothing
            # by default, we sync if there are any listeners
            # other than the JS back edge
            sync = any(f-> !isa(f, SyncCallback), listeners(ob))
        end
        obs_dict[k] = Dict(
            "sync" => sync,
            "value" => ob[],
            "id" => obsid(ob)
        )
    end
    Dict(
        "id" => scopeid(scope),
        "systemjs_options" => scope.systemjs_options,
        "imports" => lowerassets(scope.imports),
        "handlers" => scope.jshandlers,
        "mount_callbacks" => scope.mount_callbacks,
        "observables" => obs_dict
    )
end

function render(s::Scope)
    node(s, s.dom)
end

"""
    send_command(scope, command[, "key" => "value", ...])

Send a command message for a scope. A command is essentially a fire-and-forget
style message; no response or acknowledgement is expected.
"""
function send_command(scope::Scope, command, data::Pair...)
    message = Dict(
        "type" => "command",
        "command" => command,
        "scope" => scopeid(scope),
        data...
    )
    send(scope.pool, message)
    nothing
end

"""
Send a command to update the frontend's value for an observable.
"""
send_update_observable(scope::Scope, name::AbstractString, value) = send_command(
    scope,
    "update_observable",
    "name" => name,
    "value" => value,
)

function send_request(scope::Scope, request, data::Pair...)
    send_request(scope.pool, request, "scope" => scopeid(scope), data...)
end

macro evaljs(ctx, expr)
    @warn("@evaljs is deprecated, use evaljs function instead")
    :(send_request($(esc(ctx)), "eval", "expression" => $(esc(expr))))
end

function evaljs(ctx, expr)
    send_request(ctx, "eval", "expression" => expr)
end

function onmount(scope::Scope, f::JSString)
    push!(scope.mount_callbacks, f)
    return scope
end

function onimport(scope::Scope, f::JSString)
    onmount(scope, js"""
        function () {
            var handler = ($(f));
            ($(Async(scope.imports))).then((imports) => handler.apply(this, imports));
        }
        """)
end

onmount(scope::Scope, f) = onmount(scope, JSString(f))
onimport(scope::Scope, f) = onimport(scope, JSString(f))

Base.@deprecate ondependencies(ctx, jsf) onimport(ctx, jsf)

"""
A callable which updates the frontend
"""
struct SyncCallback
    ctx
    f
end

(s::SyncCallback)(xs...) = s.f(xs...)

"""
Set observable without synchronizing with the counterpart on the browser
"""
function set_nosync(ob, val)
    for f in listeners(ob)
        if !(f isa SyncCallback)
            Base.invokelatest(f, val)
        end
    end
    return
end

const lifecycle_commands = ["scope_created"]

function dispatch(ctx, key, data)
    if haskey(ctx.observs, string(key))
        # this message has come from the browser
        # so don't update the browser back!
        set_nosync(ctx.observs[key][1], data)
    else
        if !(key in lifecycle_commands)
            @warn("$key does not have a handler for scope id $(scopeid(ctx))")
        end
    end
end

function onjs(ctx, key, f)
    push!(get!(()->[], ctx.jshandlers, key), f)
end

function offjs(ctx, key, f)
    if f in get(ctx.jshandlers, key, [])
        keys = ctx.jshandlers[key]
        deleteat!(keys, findall(in(f), keys))
    end
    nothing
end

function ensure_sync(ctx, key)
    ob = ctx.observs[key][1]
    # have at most one synchronizing handler per observable
    if !any(x->isa(x, SyncCallback) && x.ctx==ctx, listeners(ob))
        f = SyncCallback(ctx, (msg) -> send_update_observable(ctx, key, msg))
        on(SyncCallback(ctx, f), ob)
    end
end

function onjs(ob::AbstractObservable, f)
    if haskey(observ_id_dict, ob)
        ctx, key = observ_id_dict[ob]
        ctx = ctx.value
        # make sure updates are set up to propagate to JS
        ensure_sync(ctx, key)
        onjs(ctx, key, f)
    else
        error("This observable is not associated with any scope.")
    end
end

function Base.show(io::IO, ::WEBIO_NODE_MIME, x::Scope)
    write(io, JSON.json(render(x)))
end
function Base.show(io::IO, m::MIME"text/html", x::Scope)
    show(io, m, render(x))
end

function _show(io::IO, el::Scope, indent_level=0)
    showindent(io, indent_level)
    _show(io, el.dom, indent_level)
end

Base.@deprecate_binding Context Scope
Base.@deprecate handle! on
Base.@deprecate handlejs! onjs

# Adding assets to scopes
import!(scope::Scope, x) = push!(scope.imports, Asset(x))
Base.@deprecate adddeps!(scope, x) import!(scope, x)
