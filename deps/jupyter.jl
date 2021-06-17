if !(@isdefined BUNDLES_PATH)
    include("./bundlepaths.jl")
end

const CONFIG_BEGIN_MARKER = "###JULIA-WEBIO-CONFIG-BEGIN"
const CONFIG_END_MARKER = "###JULIA-WEBIO-CONFIG-END"

_tryrun(args...; kwargs...) = try run(args...; kwargs...) catch nothing end

"""
    install_notebook_config()

Install necessary configuration for the `jlstaticserve` notebook (server)
extension. This function only configures the notebook extension, not the browser
nbextension or Jupyter Lab extension.
* Adds the path to `./deps` to Python's `sys.path` so that we can load the
    `jlstaticserve.py` extension. This is done in `jupyter_notebook_config.py`
    because there's no way to add to `sys.path` from the JSON config file.
* Adds `jlstaticserve` to the list of extensions loaded in the notebook server.
    This is done in `jupyter_notebook_config.json` because that file has higher
    precedence when both the `.py` and `.json` files exist (IPyWidgets, for
    example, writes to the JSON file, so if we only wrote to the `.py` file,
    that directive would take precedence and the `jlstaticserve` extension would
    **not** be loaded).
"""
function install_jupyter_serverextension()
    config_dir = jupyter_config_dir()
    mkpath(config_dir)
    config_file_py = joinpath(config_dir, "jupyter_notebook_config.py")
    config_py = isfile(config_file_py) ? read(config_file_py, String) : ""

    # Remove previous config
    config_regex = Regex(
        "\n?" * CONFIG_BEGIN_MARKER * ".*" * CONFIG_END_MARKER * "\n?",
        "s",
    )
    config_py = replace(config_py, config_regex => "")

    # We do a repr to make sure that all the necessary characters are escaped
    # and the whole path is wrapped in quotes.
    deps_dir = dirname(@__FILE__)
    deps_dir_esc = repr(deps_dir)
    error_msg = strip("""
        Directory $deps_dir could not be found; WebIO will not work as expected.
        """)
    config_py *= """

    $CONFIG_BEGIN_MARKER
    # Add the path to WebIO/deps so that we can load the `jlstaticserve` extension.
    import os, sys, warnings
    webio_deps_dir = $deps_dir_esc
    if os.path.isfile(os.path.join(webio_deps_dir, "jlstaticserve.py")):
        sys.path.append(webio_deps_dir)
    else:
        warning_msg = (
            'Directory %s could not be found; WebIO.jl will not work as expected. '
            + 'Make sure WebIO.jl is installed correctly (try running '
            + 'Pkg.add("WebIO") and Pkg.build("WebIO") from the Julia console to '
            + 'make sure it is).'
        ) % webio_deps_dir
        warnings.warn(warning_msg)
    $CONFIG_END_MARKER
    """

    config_file_json = joinpath(config_dir, "jupyter_notebook_config.json")
    config_json = isfile(config_file_json) ? read(config_file_json, String) : "{}"
    config_json = try
        JSON.parse(config_json)
    catch exc
        @error "Unable to parse Jupyter notebook config file ($config_file_json). Please fix it and rebuild WebIO." exception=exc
        rethrow()
    end

    # Magic to safely access nested JSON objects and set them to empty objects
    # if they don't exist yet.
    app_config = get!(config_json, "NotebookApp", Dict())
    extensions_config = get!(app_config, "nbserver_extensions", Dict())
    extensions_config["jlstaticserve"] = true

    # Defer writing until both files until the end to avoid inconsistent state.
    write(config_file_py, config_py)
    write(config_file_json, json(config_json, 4))
    return nothing
end

function find_condajl_jupyter_cmd(;
    check_nodejs::Bool=false,
)::Cmd
    conda_root = joinpath(first(Base.DEPOT_PATH), "conda", "3")
    conda_bin_dir = joinpath(
        conda_root,
        @static(Sys.iswindows() ? "Scripts" : "bin"),
    )

    jupyter = joinpath(conda_bin_dir, exe("jupyter"))
    if !isfile(jupyter)
        error(
            "Could not find the Conda.jl `jupyter` executable " *
            "(is it installed?)."
        )
    end

    # We need to add Conda's bin directory to the PATH so that jupyterlab can
    # detect nodejs.
    conda_env = copy(ENV)
    conda_env["PATH"] = string(conda_bin_dir, ":", conda_env["PATH"])
    cmd = Cmd(`$jupyter`, env=conda_env)

    if check_nodejs
        node_exe = joinpath(conda_bin_dir, exe("node"))
        if !Sys.isfile(node_exe)
            install_node = Base.prompt(
                "NodeJS is not installed in your Conda environment " *
                "but is neccessary to install the JupyterLab extension. " *
                "Install it? [Y/n]"
            )
            if isyes(install_node)
                @eval Main using IJulia
                @eval Main.IJulia Conda.add("nodejs")
            end
        end
    end

    return cmd
end

function find_path_jupyter_cmd()::Cmd
    jupyter = Sys.which("jupyter")
    if jupyter === nothing
        error("Could not find `jupyter` executable in PATH.")
    end
    return `$jupyter`
end

"""
    find_jupyter_cmd([; condajl=false])

Find the most likely candidate for the `jupyter` executable.
This will locate `jupyter` by searching the `PATH` environment variable and,
if not found, tries to return Conda.jl's jupyter.
If both of these approaches fail, an error is thrown.
"""
function find_jupyter_cmd(;
    # DEPRECATED: use `condajl` keyword argument
    force_conda_jupyter::Union{Nothing, Bool}=nothing,
    condajl::Union{Nothing, Bool}=force_conda_jupyter,
    check_nodejs::Bool=false,
)::Cmd
    # Try to find the "system" Jupyter (unless we explicitly want to force
    # using IJulia's Jupyter installation).
    if condajl === nothing || condajl === false
        try
            return find_path_jupyter_cmd()
        catch
            # If conda is false, we explicitly don't want to look for jupyter
            # in Conda.jl's installation, so we fail now.
            # Otherwise, conda is nothing and we can continue searching.
            if condajl === false
                rethrow()
            end
        end
    end

    try
        return find_condajl_jupyter_cmd(check_nodejs=check_nodejs)
    catch
        if condajl === nothing
            error("Could not find `jupyter` executable in PATH or Conda.jl.")
        end
        rethrow()
    end
end

"""
    install_jupyter_labextension([jupyter]; condajl=false)

Install the Jupyter Lab extension for WebIO using the specified `jupyter`
executable.
The executable defaults to the first one found in the `PATH` or Jupyter
installed via IJulia/Conda.jl.
To force using Conda.jl's jupyter, specify the `force_conda_jupyter=true`
keyword; this might be necessary if you launch Jupyter via IJulia in the Julia
REPL.

The [IJulia provider documentation](https://juliagizmos.github.io/WebIO.jl/latest/providers/ijulia/)
provides some more information (and caveats) about the relationship between
Jupyter Lab and WebIO.
"""
function install_jupyter_labextension(
        jupyter::Union{Cmd, Nothing}=nothing;
        # Deprecated: use `condajl` keyword argument.
        force_conda_jupyter::Union{Bool, Nothing}=nothing,
        condajl::Union{Bool, Nothing}=force_conda_jupyter,
        dev::Bool=isdev()
)
    if jupyter === nothing
        jupyter = find_jupyter_cmd(; condajl=condajl, check_nodejs=true)
        @info(
            "Using default Jupyter executable at $jupyter; to use a different "
            * "executable, see the documentation by running "
            * "`?WebIO.install_jupyter_labextension`."
        )
    end
    install_jupyter_serverextension()

    _tryrun(`$jupyter labextension unlink --no-build @webio/webio`)
    _tryrun(`$jupyter labextension uninstall --no-build @webio/jupyter-lab-provider`)

    if dev
        @info "Installing Jupyter labextension in dev mode..."
        core_path = joinpath(PACKAGES_PATH, "webio")
        lab_provider_path = joinpath(PACKAGES_PATH, "jupyter-lab-provider")
        run(`$jupyter labextension link --no-build $core_path`)
        run(`$jupyter labextension install --no-build $lab_provider_path`)
    else
        run(`$jupyter labextension install --no-build @webio/jupyter-lab-provider@$(WEBIO_VERSION)`)
    end
    run(`$jupyter lab build`)
end


"""
    install_jupyter_nbextension([jupyter])

Install the Jupyter Notebook extension (nbextension) for WebIO.
This copies the nbextension code to the appropriate place and writes the
appropriate configuration files.
"""
function install_jupyter_nbextension(
        jupyter=nothing;
        condajl::Union{Bool,Nothing}=nothing,
        nbextension_flags::Cmd=`--user`,
)
    install_jupyter_serverextension()

    if jupyter === nothing
        jupyter = find_jupyter_cmd(; condajl=condajl)
    end

    # Copy the nbextension files.
    install_cmd = `$jupyter nbextension install $nbextension_flags $JUPYTER_NBEXTENSION_PATH`
    @info "Installing Jupyter WebIO extension..." cmd=install_cmd
    run(install_cmd)

    enable_cmd = `$jupyter nbextension enable $nbextension_flags $JUPYTER_NBEXTENSION_NAME`
    @info "Enabling Jupyter WebIO extension..." cmd=enable_cmd
    run(enable_cmd)

    return nothing
end

### BEGIN BORROWED CODE ###
# This code is adapted from IJulia.jl (MIT license).
# https://github.com/JuliaLang/IJulia.jl/blob/68748c2b88b4b394e2802e911eb154b7008ebdd2/deps/kspec.jl
@static if Sys.iswindows()
    function appdata() # return %APPDATA%
        path = zeros(UInt16, 300)
        CSIDL_APPDATA = 0x001a
        result = ccall((:SHGetFolderPathW,:shell32), stdcall, Cint,
            (Ptr{Cvoid},Cint,Ptr{Cvoid},Cint,Ptr{UInt16}),C_NULL,CSIDL_APPDATA,C_NULL,0,path)
        return result == 0 ? transcode(String, resize!(path, findfirst(iszero, path)-1)) : get(ENV, "APPDATA", "")
    end
    function default_jupyter_data_dir()
        APPDATA = appdata()
        return !isempty(APPDATA) ? joinpath(APPDATA, "jupyter") : joinpath(get(ENV, "JUPYTER_CONFIG_DIR", joinpath(homedir(), ".jupyter")), "data")
    end
elseif Sys.isapple()
    default_jupyter_data_dir() = joinpath(homedir(), "Library/Jupyter")
else
    function default_jupyter_data_dir()
        xdg_data_home = get(ENV, "XDG_DATA_HOME", "")
        data_home = !isempty(xdg_data_home) ? xdg_data_home : joinpath(homedir(), ".local", "share")
        joinpath(data_home, "jupyter")
    end
end

function jupyter_data_dir()
    env_data_dir = get(ENV, "JUPYTER_DATA_DIR", "")
    !isempty(env_data_dir) ? env_data_dir : default_jupyter_data_dir()
end
### END BORROWED CODE ###

function jupyter_config_dir()
    env_config_dir = get(ENV, "JUPYTER_CONFIG_DIR", "")
    !isempty(env_config_dir) ? env_config_dir : joinpath(homedir(), ".jupyter")
end
jupyter_nbextensions_dir() = joinpath(jupyter_data_dir(), "nbextensions")
jupyter_nbconfig_dir() = joinpath(jupyter_config_dir(), "nbconfig")

isyes(s) = isempty(s) || lowercase(strip(s)) in ("y", "yes")

@static if Sys.iswindows()
    exe(x::String) = endswith(x, "exe") ? x : string(x, ".exe")
else
    exe(x::String) = x
end
