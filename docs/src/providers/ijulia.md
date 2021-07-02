# IJulia

## WebIO Not Detected
For troubleshooting information, visit the [WebIO Not Detected](@ref) section
of the documentation.

## JupyterLab Considerations
JupyterLab presents a few issues that are different that than those associated
with the classic notebook.
JupyterLab extensions are bundled together with the core application code (so
that all of the JavaScript associated with JupyterLab is served as a single
file).

This can sometimes present issues if there are multiple versions of JupyterLab
installed on a system (e.g. for multiple virtual environments or if installed
using Conda and Pip) because these bundles are separate for each JupyterLab
installation.

!!! note
    For example, if you installed JupyterLab via
    `pip install --user jupyterlab` and `pip install jupyterlab` in a virtualenv
    at `~/venv`, then there will be two bundles (at
    `~/.local/share/jupyter/lab/` and `~/env/share/jupyter/lab/` respectively,
    on Linux).

This presents issues when the JupyterLab that is launched is not the
JupyterLab that WebIO was installed for (for example, the labextension was
installed for the Conda version of JupyterLab but you're launching the version
that is installed in a Python virtual environment).

### Fixing Things Up
If you suspect that WebIO isn't installed for a specific version of JupyterLab,
you can check with the `jupyter labextension list` command.
First, make sure that you're using the version of JupyterLab that you mean to
be using (this usually entails activating the correct Conda environment or
Python virtual environment).
```
$ which jupyter
/home/user/.local/bin/jupyter
```
Then, make sure that the WebIO extension is installed.
The output should look something like this (though the specific versions and
paths will likely be different).
```
$ jupyter labextension list
JupyterLab v0.35.5
Known labextensions:
   app dir: /home/user/.julia/conda/3/share/jupyter/lab
        @webio/jupyter-lab-provider v0.8.3  enabled  OK*

   local extensions:
        @webio/jupyter-lab-provider: /home/user/.julia/dev/WebIO/packages/jupyter-lab-provider

   linked packages:
        @webio/webio: /home/user/.julia/dev/WebIO/packages/webio
```

If the WebIO extension isn't present, then simply fire up Julia and install it.
This can either be done by running `Pkg.build("WebIO")` or by running
```julia
using WebIO, IJulia
WebIO.install_jupyter_labextension()
```

If you open IJulia with
```
using IJulia; notebook()
```
you should install the WebIO extension in the jupyter notebook by running
```
WebIO.install_jupyter_nbextension()
```

## API Reference
```@docs
WebIO.find_jupyter_cmd
WebIO.install_jupyter_labextension
WebIO.install_jupyter_nbextension
WebIO.install_jupyter_serverextension
```
