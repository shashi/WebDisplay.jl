using JSON

include("./bundlepaths.jl")
include("./jupyter.jl")

download_js_bundles()

try
    install_jupyter_labextension(; condajl=true)
catch exc
    @warn "Unable to install JupyterLab extension" exception=exc
end

try
    install_jupyter_nbextension(; condajl=true)
catch exc
    @warn "Unable to install Jupyter Notebook extension" exception=exc
end
