# Getting Started

## Installing WebIO
WebIO is installed just like any other Julia package.
```julia
using Pkg
Pkg.add("WebIO")
using WebIO
```
Make sure to watch for any errors during the build process;
WebIO does its best to install everything to the right location, but sometimes
it can't find all the right things (especially for Jupyter).
If you get any warnings, please file an issue on GitHub.

## Displaying to a Frontend
First, load the appropriate frontend (e.g. Jupyter or Blink or Atom/Juno).
For simplicity, Jupyter is recommended while you're getting started.

### Jupyter
In a Julia Jupyter notebook (either via the classic notebook interface or in
JupyterLab), any WebIO content is automagically rendered into the browser.
For example, try displaying a paragraph.
```julia
In[*]: node(:p, "Hello, Jupyter")
```

### Blink
Blink is a Julia interface for [Electron](https://electronjs.org/) (a way to
write desktop apps using web technologies).
WebIO content can be displayed in a Blink window using the `body!` function.

```julia
using Blink
w = Window()
body!(w, dom"p"("Hello, Blink!"))
```

### Mux
Return a WebIO [`Node`](@ref Node) from a web app to render it.
Use [`webio_serve`](@ref WebIO.webio_serve) to serve the application.


```julia
function myapp(req)
    return node(:p, "Hello, Mux!")
end

webio_serve(page("/", req -> myapp(req)))
```

### Generic HTTP
```julia
# Create your own display function
function Base.display(d::MyWebDisplay, m::WebIO.WEBIO_APPLICATION_MIME, app)
    println(d.io, "outer html")
    # Calling show will make sure a server is running and serves dependencies
    # from AssetRegistry and a websocket connection gets established.
    show(d.io, m, app) #<- prints the html + scripts webio needs to work into io
    println(d.io, "close outer html")
end
```

### Juno
WebIO nodes should be automatically rendered when displayed.

## Composing Content
Suppose we want to display the following HTML.
```html
<ul class="my-list">
    <li>get milk</li>
    <li>make a pie</li>
</ul>
```

We can nest nodes inside of each other to accomplish this.
```julia
Node(
    :ul,
    Node(:li, "get milk"),
    Node(:li, "make a pie"),
    attributes=Dict(:class => "my-list"),
)
```

Some DOM properties (most importantly, `style` and `events`) can be specified as Julia dictionaries.
```julia
Node(
    :div,
    "Hello, world!",
    style=Dict(
        :backgroundColor => "black",
        :color => "white",
        :padding => "12px",
   ),
)
```

This is equivalent to this snippet using `attributes`.
```julia
Node(
    :div,
    "Hello, World",
    attributes=Dict(
        :style => "background-color: black; color: white; padding: 12px",
    ),
)
```

Checkout out the [`Node`](@ref) reference for more information.

!!! note

    The `attributes` keyword argument sets the attributes of the HTML element (via the [`setAttribute`](https://developer.mozilla.org/en-US/docs/Web/API/Element/setAttribute) DOM API function). Any other keyword argument is set as the property of the [DOM node](https://developer.mozlla.org/en-US/docs/Web/API/Document_Object_Model/Introduction) itself.

    **N.B.** Attribute values should be strings (or `nothing`, in which case the attribute is deleted). Attribute keys are specified with the name as would be written in HTML (e.g. `class` for the CSS class name) whereas properties are specified as the name in the browser DOM API (e.g. `className`). This is because one writes
    ```html
    <p class="important">Don't stuff beans up your nose!</p>
    ```
    whereas the DOM API would be
    ```js
    myParagraph = document.createElement("p");
    myParagraph.className = "important";
    // Or, equivalently...
    myParagraph.setAttribute("class", "important");
    ```

    For example, the following are equivalent.
    ```julia
    node(:ul, className="my-list")
    node(:ul, attributes=Dict(:class => "my-list"))
    ```

    When in doubt, use `attributes` for everything except the `style` and
    `events` properties.

### The `dom""` macro

The `dom""` string macro can be used to simplify the creation of DOM nodes and
is based on the [`querySelector`](https://developer.mozilla.org/en-US/docs/Web/API/Document/querySelector)
DOM API.
The syntax for the macro is
```julia
dom"<tag>.<class>#<id>[<attr>=<value>,...]"(children...; props...)
```
which is equivalent to
```julia
Node(
    :tag,
    children...,
    className="<class>",
    id="<id>",
    attributes=Dict(:attr1 => val1, :attr2 => val2...);
    props...
)
```

For example
```julia
dom"div.warning.big-text#my-modal[aria-modal=true]"(
    dom"p"("Uh oh! A bad thing happened."),
)
```
yields this HTML
```html
<div id="my-modal" class="warning big-text" aria-modal="true">
    <p>Uh oh! A bad thing happened.</p>
</div>
```

Everything except the tag is optional, so all of these are valid.
* `dom"div"`
* `dom"div.class1"`
* `dom"div.class1.class2"`
* `dom"div#my-id"`
* `dom"input.check[type=checkbox]"`

## JavaScript
### Executing JavaScript
Event handlers can be set up by passing a dict as the `events` keyword argument to `Node`, (and the [`dom""`](@ref @dom_str) macro). For example,
```julia
dom"button"(
    "Greet",
     events=Dict(
        "click" => js"function() { alert('Hello, World!'); }",
    ),
)
```

This will create a button which shows an alert box with the message
"Hello, World!" when clicked.

There are 2 ways to write JavaScript in conjunction with WebIO.
First, you can use the [`js""`](@ref @js_str) string macro to just write any
JavaScript as a string. For example
```
js"""
alert("Hello, World!")
"""
```

This will return an object of type `JSString` which can be used anywhere WebIO
expects JavaScript expressions.
The [`js""`](@ref @js_str) macro also appropriately escapes any interpolated
variables.
```julia-repl
julia> myvar = [1, "foo", Dict("foo" => "bar")];
julia> println(js"console.log($myvar);")
console.log([1,"foo",{"foo":"bar"}]);
```

The second way is to use the `@js` macro from [JSExpr.jl](https://github.com/JuliaGizmos/JSExpr.jl).
The `@js` macro can translate arbitrary Julia expressions to the equivalent
JavaScript.
```julia
using JSExpr
@js alert("Hello, World!")
```

We can rewrite our greeting example above using the `@js` macro too.
```julia
dom"button"(
    "Greet",
    events=Dict(
        "click" => (@js () -> alert("Hello, World!")),
    ),
)
```

!!! note
    The variables and functions you reference in a `@js` expression must be
    defined in the JavaScript context where the expression will be executed
    (for example, in an event callback) and do not need to be defined in Julia.

    Values from Julia can be interpolated into both the `js""` and `@js` macros,
    but this interpolation happens when the [`JSString`](@ref) is created (and
    **not** when the JavaScript code is executed).

    For example, consider the following snippet.
    ```julia
    myname = "Walter"
    display(dom"button"("Greet Me!", events=Dict("click" => @js alert($myname))))
    ```
    When you click the button, it will alert "Walter" as expected.
    But if you later change the value of `myname`,
    ```julia
    myname = "Sylvia"
    ```
    clicking the button will still result in "Walter" since the value of
    `myname` was interpolated when the expression was parsed.

    See [Communicating between Julia and JavaScript](@ref) to learn how to use
    the latest value of a variable in either Julia or JavaScript.

### Communicating between Julia and JavaScript

A [`Scope`](@ref) acts as a medium for bidirectional communication between
Julia and JavaScript.
The primary method of communication is `Observable`s which are essentially
wrappers around values that may change over time.
A [`Scope`](@ref) may contain several observables whose values can be updated and read
from either JavaScript or Julia.

We associate an observable with a scope as follows.
```julia
w = Scope()
obs = Observable(w, "rand-value", 0.0)
```
The `"rand-value"` argument is the name of the observable and must be unique
for a given scope.

You can get the value of `obs` in Julia with the syntax `obs[]`.
You can set the value using the syntax `obs[] = val`.
To listen to changes to the value you can use the `on` function to set up a
listener.

```julia
on((value) -> println("Value is now $(value)!"), obs)
```
or, using do-block syntax,
```julia
on(obs) do value
    println("Value is now $(value)!")
end
```

### Sending values from JavaScript to Julia

Sending values from JavaScript to Julia is easiest via the `@js` macro.
Consider this simple example.

```julia
scope = Scope()
obs = Observable(scope, "rand-value", 0.0)

on(obs) do x
    println("JavaScript sent $(x)!")
end

scope(
    dom"button"(
        "Generate Random Number",
        events=Dict("click" => @js () -> $obs[] = Math.random()),
    ),
)
```

!!! note
    Notice that the last expression actually _calls_ the scope `scope` with the contents that should be displayed.
    This causes the contents to be _wrapped_ in the scope's context.
    All uses of observables associated with `scope` (e.g. `obs`) should be
    enclosed in the scope `scope`.

Note that we use the syntax `$obs[] = ...` inside the `@js` macro to update the
value of the `obs` Observable.

Using the [`js""`](@ref @js_str) macro, we can write
```julia
js"_webIOScope.getObservableValue('obs')"
```
and
```julia
_webIOScope.setObservableValue("obs", ...);
```
wherever we want to get and set the values of observables (respectively).

!!! note
    The values of `WebIO` and `_webIOScope` are defined when executing any
    JavaScript code in WebIO.
    The value of `_webIOScope` is the nearest ancestor scope (or `undefined` if
    there is none).

### Sending values from Julia to JavaScript

The [`onjs`](@ref) function allows us to hook up a JavaScript listener on an
`Observable` just like we can use `on` for a Julia listener.
For example, we can log to the console whenever the value of our observable
changes.
```julia
s = Scope()
obs = Observable(s, "logme", "")
onjs(
    obs,
    js"""
    function(newValue) {
        console.log(newValue);
    }
    """
)
```

### Rendering Observables

For an even easier way to send values from Julia to JavaScript, we can simply
rely on the fact that WebIO knows how to render `Observable`s directly to HTML.
In this case WebIO will automatically construct a `Scope` and insert the
relevant JavaScript to update the rendered content whenever the `Observable`
changes value.

```julia
using Dates
timestr() = Dates.format(now(), "HH:MM:SS")

time = Observable(timestr())
@async while true
    sleep(1)
    time[] = timestr()
end

display(time)
```

### Loading JavaScript dependencies

You can load dependencies by creating a [`Scope`](@ref) object and providing the
`imports` argument.
The `onmount` function will add a mount callback to a scope that will be called
with all of the dependencies provided via the `imports` argument.

```julia
using WebIO, JSExpr

w = Scope(imports=["//cdnjs.cloudflare.com/ajax/libs/p5.js/0.5.11/p5.js"])
onmount(w, @js function (p5)
    function sketch(s)
        s.setup = () -> s.createCanvas(640, 480)

        s.draw = function ()
          if s.mouseIsPressed
            s.fill(0)
          else
            s.fill(255)
          end
          s.ellipse(s.mouseX, s.mouseY, 80, 80)
        end
    end
    @new p5(sketch, this.dom.querySelector(".container"))
end)
w(dom"div.container"())
```

## Examples

### Clock (Julia to JS Communication)
```julia
s = Scope()
s(dom"span.current-time"())
time = Observable(s, "time", "")
timestr() = Dates.format(now(), "HH:MM:SS")

# Update the time every second
@async while true
    time[] = timestr()
    sleep(1)
end

# Setup a JavaScript listener
onjs(
    time,
    js"""
    function(time) {
        this.dom.querySelector(".current-time").textContent = time;
    }
    """
)
```

!!! note
    In the `onjs` callback, `this` is set to the [`Scope`](@ref) object (though
    the value of `_webIOScope` is also set, as noted above).

    The value of `this.dom` refers to the DOM node of the scope.
    Importantly, this is **not** the content of the scope, but rather, the DOM
    node that encloses the scope (so we need to use `querySelector` to find the
    actual DOM node that we want to update).
    For example, consider a scope whose content is simply a `<span />`; the
    value of `this.dom` will be a `<div />` whose only child is that `<span />`.
