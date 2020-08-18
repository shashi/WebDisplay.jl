# Test for load-order-specific issues with WebIO and IJulia
# when running outside of Jupyter.
#
# See: https://github.com/JuliaGizmos/WebIO.jl/issues/117
using Test
using WebIO
using Conda, IJulia

@testset "IJulia initialization" begin
    @test :ijulia in WebIO.providers_initialised
end

if haskey(ENV, "CI")
    # This takes a long time so only run in CI by default.
    @testset "Jupyter setup" begin
        # We need conda-forge for node.
        Conda.add_channel("conda-forge")
        Conda.add.(["jupyterlab=1", "nodejs"])

        # Remove path to make sure that we can find Conda if nothing else exists.
        oldpath = ENV["PATH"]
        ENV["PATH"] = ""
        conda_jupyter = WebIO.find_jupyter_cmd()

        # Restore the old PATH because we need to have node.
        pathsep = Sys.iswindows() ? ";" : ":"
        ENV["PATH"] = string(Conda.BINDIR, pathsep, oldpath)
        @assert Sys.which("node") !== nothing

        @testset "JupyterLab setup" begin
            # Uninstall before actual tests begin
            run(Cmd(
                `$conda_jupyter labextension uninstall @webio/jupyter-lab-provider`,
                ignorestatus=true,
            ))
            WebIO.install_jupyter_labextension(conda_jupyter)
            errpipe = Pipe()
            run(pipeline(`$conda_jupyter labextension list`, stderr=errpipe))
            close(errpipe.in)
            installed_extensions = read(errpipe, String)
            @test occursin("@webio/jupyter-lab-provider", installed_extensions)
        end

        @testset "Jupyter Notebook setup" begin
            WebIO.install_jupyter_nbextension()
            installed_extensions = read(`$conda_jupyter nbextension list`, String)
            @test occursin("webio", installed_extensions)
        end

        @testset "Jupyter serverextension setup" begin
            # Note: The server extension should be automatically installed after
            # installing either the lab or notebook plugins.
            installed_extensions = read(`$conda_jupyter serverextension list`, String)
            @test occursin("jlstaticserve", installed_extensions)
        end

        # Restore path for good hygiene
        ENV["PATH"] = oldpath
    end
else
    @info(
        "Skipping Conda/Jupyter installation tests; set the CI environment "
        * "variable to run these tests as well.",
    )
end

# Test the demo jupyter notebook and make sure all of its cells execute
# without error.
using NBInclude

@testset "Demo notebook" begin
    @nbinclude(joinpath(@__DIR__, "assets", "jupyter-test.ipynb"))
end
