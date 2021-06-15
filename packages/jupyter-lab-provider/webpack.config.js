console.log("configuring Webpack for @webio/jupyter-lab-provider");

module.exports = {
    // Webpack 5
    resolve: {
        fallback: {
            fs: false,
        }
    }
}
