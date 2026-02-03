const webpack = require('webpack')
const HtmlWebpackPlugin = require('html-webpack-plugin')
const path = require('path')
const fs = require('fs')

class CopyConfigPlugin {
    apply(compiler) {
        compiler.hooks.emit.tapAsync('CopyConfigPlugin', (compilation, callback) => {
            const configPath = path.resolve(__dirname, 'src/config.js')
            const contents = fs.readFileSync(configPath)
            compilation.assets['config.js'] = {
                source: () => contents,
                size: () => contents.length
            }
            callback()
        })
    }
}

module.exports = {
    mode: 'development',
    entry: './src/script.js',
    output: {
        filename: 'main.js',
        path: path.resolve(__dirname, 'dist')
    },
    plugins: [
        new HtmlWebpackPlugin({
            template: './src/index.html'
        }),
        new webpack.ProvidePlugin({
            $: 'jquery',
            jQuery: 'jquery'
        }),
        new CopyConfigPlugin()
    ]
}
